#!/bin/sh
# [汎用core] 差分カバレッジ（patch coverage）ゲート — レガシー/brownfield 向け ratchet
# gatecrate-type: detection  (実コードの変更を起点に発火する検出型。発火履歴で価値を証明する層)
#
# WHY: テストの無いレガシーに絶対カバレッジ floor（coverage>=80）を入れると初日に必ず落ちる。すると消費側は
# ゲートごと外し、テストレーンの価値はゼロのまま安全網も育たない。diff-coverage はレガシー本体には何も要求せず
# 「このPRで追加/変更した行だけ」に被覆を要求する。＝ボーイスカウトルール（触った所を少し良く）の機械強制であり、
# テストゼロから「新規分から安全網を張る → ベースライン上昇 → いずれ floor/mutation へ昇格」の段階的な道を作る。
#
# 設計: 判定（git diff の変更行 ∩ カバレッジ報告）はスタック非依存。唯一スタック固有なのは報告フォーマットで、
# そこを COVERAGE_FORMAT でパラメータ化する: jacoco（Kotlin/Android=kover/JaCoCo XML）/ lcov（rust=cargo llvm-cov --lcov、
# typescript=vitest coverage reporter lcov、python=coverage lcov）/ gocover（go test -coverprofile）。
# 既知の限界: 報告に現れない変更行（全くテストでロードされない新規ファイル等）は「未計装」として分母から外れる
# ＝被覆要求が掛からない。これは diff-coverage 一般の限界で、別途 floor/test 存在ゲートで補う前提。
#
# Config (env, from harness.config.sh or CLI env):
#   COVERAGE_REPORT          — カバレッジ報告のパス（必須。jacoco の XML）
#   COVERAGE_FORMAT          — 報告フォーマット（jacoco / lcov / gocover。既定 jacoco）
#   DIFF_BASE                — 比較元 ref（既定 origin/main。無ければ HEAD の親へフォールバック）
#   DIFF_COVERAGE_THRESHOLD  — 変更行被覆率の floor [%]（既定 80。>= で通す）
#   DIFF_PATHSPEC            — diff 対象の pathspec（既定 "*.kt *.java"。他言語は "*.rs" 等を設定）
#   DIFF_LINES_FILE          — test seam: 設定時 git を使わず path<TAB>nr を変更行として読む
#
# Usage: sh check-diff-coverage.sh
# Consumption model: repo root を git で解決するので kit(core/scripts/)でも消費者(scripts/)でも動く。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

COVERAGE_REPORT="${COVERAGE_REPORT:?COVERAGE_REPORT must be set (path to the coverage report, e.g. build/reports/jacoco/test/jacocoTestReport.xml)}"
COVERAGE_FORMAT="${COVERAGE_FORMAT:-jacoco}"
DIFF_COVERAGE_THRESHOLD="${DIFF_COVERAGE_THRESHOLD:-80}"
DIFF_BASE="${DIFF_BASE:-origin/main}"
DIFF_PATHSPEC="${DIFF_PATHSPEC:-*.kt *.java}"

if [ ! -f "$COVERAGE_REPORT" ]; then
  echo "diff-coverage: ERROR — coverage report not found: $COVERAGE_REPORT" >&2
  echo "  テスト実行で報告を生成してから本ゲートを回してください（例: ./gradlew koverXmlReport / jacocoTestReport）。" >&2
  exit 2
fi
case "$COVERAGE_FORMAT" in
  jacoco|lcov|gocover) ;;
  *)
    echo "diff-coverage: ERROR — unsupported COVERAGE_FORMAT='$COVERAGE_FORMAT' (jacoco / lcov / gocover)." >&2
    exit 2
    ;;
esac

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
COV="$WORK/coverage"     # 計装行の被覆実態:  <pkgpath>/<sourcefile><TAB><nr><TAB><cov 0|1>
CHANGED="$WORK/changed"  # 変更行:            <path><TAB><nr>

# --- 1) カバレッジ報告から計装行の被覆を取り出す（jacoco） ---
# JaCoCo XML: <package name="com/example/foo"> <sourcefile name="Foo.kt"> <line nr="N" mi=".." ci=".."/>
# ci>0 を covered とみなす。<line> に現れない行は未計装（=分母に入れない）。
extract_jacoco() {
  # RS=">" で1タグ1レコードに分割して package/sourcefile/line を追跡する。実 jacoco.xml は要素間に改行が無い
  # 単一行（751KB 等）なので「改行で1要素1行」前提のパーサ（tr/sed）は分割に失敗する——tr は文字を挿入できず、
  # macOS の sed は置換中の \n を literal n にする。awk の RS だけが移植的に効く（実プロジェクトの単一行 XML で実証）。
  awk -v OFS='\t' 'BEGIN { RS = ">" }
    function attr(s, name,   m) {
      m = s; if (match(m, name "=\"[^\"]*\"")) {
        m = substr(m, RSTART, RLENGTH); sub(name "=\"", "", m); sub(/"$/, "", m); return m
      }
      return ""
    }
    /<package[ \t]/      { pkg = attr($0, "name"); next }
    /<sourcefile[ \t]/   { sf  = attr($0, "name"); next }
    /<\/sourcefile/      { sf = ""; next }
    /<line[ \t]/ {
      if (sf == "") next
      nr = attr($0, "nr"); ci = attr($0, "ci"); if (nr == "") next
      key = (pkg == "" ? sf : pkg "/" sf)
      print key, nr, (ci + 0 > 0 ? 1 : 0)
    }
  ' "$COVERAGE_REPORT" > "$COV"
}

# --- 1b) lcov（rust: cargo llvm-cov --lcov / typescript: vitest reporter lcov / python: coverage lcov）---
# SF: がファイル（絶対パスあり得る→突合は対称サフィックス）、DA:<line>,<count> が計装行。
extract_lcov() {
  awk -v OFS='\t' '
    /^SF:/ { sf = substr($0, 4); sub(/^\.\//, "", sf); next }
    /^DA:/ { if (sf == "") next
             split(substr($0, 4), a, ","); print sf, a[1] + 0, (a[2] + 0 > 0 ? 1 : 0) }
    /^end_of_record/ { sf = "" }
  ' "$COVERAGE_REPORT" > "$COV"
}

# --- 1c) gocover（go test -coverprofile の出力）---
# 形式: <path>:<sl>.<sc>,<el>.<ec> <numstmt> <count>。ブロック範囲の各行を計装行とみなし、
# 同一行に複数ブロックが重なる場合は count>0 が1つでもあれば covered（max 集約）。
extract_gocover() {
  awk -v OFS='\t' '
    /^mode:/ { next }
    NF >= 3 {
      n = split($1, a, ":"); if (n < 2) next
      path = a[1]
      split(a[2], se, ","); split(se[1], st, "."); split(se[2], en, ".")
      cnt = $3 + 0
      for (l = st[1] + 0; l <= en[1] + 0; l++) {
        k = path SUBSEP l
        seen[k] = 1; pk[k] = path; ln[k] = l
        if (cnt > 0) hit[k] = 1
      }
    }
    END { for (k in seen) print pk[k], ln[k], (k in hit ? 1 : 0) }
  ' "$COVERAGE_REPORT" > "$COV"
}

# --- 2) 変更行（追加/変更された新側の行）を集める ---
collect_changed_from_git() {
  # diff は「いま検査する作業ツリー」＝カレントのリポジトリに対して行う（config 解決用の ROOT＝スクリプト自身の
  # リポジトリとは別物。消費側では scripts/ に同梱されるので両者は一致するが、kit から他リポを検査する場合は別）。
  diff_root="$(git rev-parse --show-toplevel 2>/dev/null || echo "$ROOT")"
  base="$DIFF_BASE"
  # origin/main が無い環境では HEAD の親へフォールバック（CI 以外・浅い clone 対策）。
  if ! git -C "$diff_root" rev-parse --verify --quiet "$base^{commit}" >/dev/null 2>&1; then
    base="$(git -C "$diff_root" rev-parse --verify --quiet HEAD~1 2>/dev/null || echo HEAD)"
  fi
  # --no-ext-diff / --no-pager: 消費者が difftastic 等の外部 diff ドライバを設定していても標準 unified hunk を
  # 強制する（外部 diff は @@ ハンクを出さず本パーサが空振りする）。
  # shellcheck disable=SC2086
  git -C "$diff_root" --no-pager diff --no-ext-diff --unified=0 --no-color "$base" -- $DIFF_PATHSPEC 2>/dev/null | awk -v OFS='\t' '
    /^\+\+\+ /      { f = $2; sub(/^b\//, "", f); next }
    /^@@ / {
      # @@ -a,b +c,d @@  の +c,d を取り出し、c..c+d-1 を変更行とする（d 省略時は 1 行）。
      if (match($0, /\+[0-9]+(,[0-9]+)?/)) {
        seg = substr($0, RSTART + 1, RLENGTH - 1)
        n = split(seg, a, ","); start = a[1] + 0; cnt = (n > 1 ? a[2] + 0 : 1)
        for (i = 0; i < cnt; i++) print f, start + i
      }
    }
  ' > "$CHANGED"
}

case "$COVERAGE_FORMAT" in
  jacoco)  extract_jacoco ;;
  lcov)    extract_lcov ;;
  gocover) extract_gocover ;;
esac
if [ -n "${DIFF_LINES_FILE:-}" ]; then
  cp "$DIFF_LINES_FILE" "$CHANGED"
else
  collect_changed_from_git
fi

# --- 3) 変更行 ∩ 計装行 を突き合わせ、被覆率を出す ---
# 対応付け: 変更パス P が JaCoCo キー K（<pkgpath>/<sourcefile>）を suffix に持つ（P==K または P が "/"+K で終わる）
# かつ行番号一致なら、その変更行は計装行。basename で候補を絞ってから suffix 判定する。
RESULT="$(awk -v thr="$DIFF_COVERAGE_THRESHOLD" '
  function base(p,   n, a) { n = split(p, a, "/"); return a[n] }
  # 1st file: coverage rows
  FNR == NR {
    key = $1; nr = $2; cov = $3
    bn = base(key)
    idx = bn SUBSEP nr
    # 同 basename/同 nr に複数 sourcefile があり得るので key をリスト保持
    klist[idx] = klist[idx] key "\034"
    covof[key SUBSEP nr] = cov
    next
  }
  # 2nd file: changed lines
  {
    p = $1; nr = $2
    bn = base(p)
    idx = bn SUBSEP nr
    if (!(idx in klist)) next            # 同 basename/行 の計装行が無い -> 未計装（分母外）
    cnt = split(klist[idx], cands, "\034")
    matched = ""
    for (i = 1; i <= cnt; i++) {
      k = cands[i]; if (k == "") continue
      # 対称サフィックス一致: p==k / p が "/"+k で終わる（jacoco: k が pkg 相対で短い）/
      # k が "/"+p で終わる（lcov 絶対 SF・gocover のモジュールプレフィックス: k が長い）。
      if (p == k || substr(p, length(p) - length(k)) == "/" k || substr(k, length(k) - length(p)) == "/" p) {
        matched = k; break
      }
    }
    if (matched == "") next
    seen = p ":" nr
    if (seen in done) next; done[seen] = 1
    total++
    if (covof[matched SUBSEP nr] + 0 > 0) covered++
    else print "  UNCOVERED " base(p) ":" nr "  (" p ")"
  }
  END {
    if (total == 0) { print "STATUS nothing"; exit 0 }
    pct = covered * 100.0 / total
    printf "STATUS pct %d %d %.1f\n", covered, total, pct
    if (pct + 0 < thr + 0) print "STATUS fail"; else print "STATUS pass"
  }
' "$COV" "$CHANGED")"

UNCOVERED="$(printf '%s\n' "$RESULT" | grep '^  UNCOVERED ' || true)"
STATUS="$(printf '%s\n' "$RESULT" | grep '^STATUS ' || true)"

if printf '%s\n' "$STATUS" | grep -q '^STATUS nothing'; then
  echo "diff-coverage: no instrumented changed lines — nothing to gate (pass)."
  exit 0
fi

line="$(printf '%s\n' "$STATUS" | sed -n 's/^STATUS pct \([0-9]*\) \([0-9]*\) \(.*\)/\1 \2 \3/p')"
covered="${line%% *}"; rest="${line#* }"; total="${rest%% *}"; pct="${rest#* }"

if printf '%s\n' "$STATUS" | grep -q '^STATUS fail'; then
  echo "diff-coverage: FAIL — changed-line coverage ${pct}% < floor ${DIFF_COVERAGE_THRESHOLD}% (${covered}/${total} instrumented changed lines covered)." >&2
  printf '%s\n' "$UNCOVERED" >&2
  echo "  変更した行にテストを足してください（レガシー本体は対象外・このPRの追加/変更分だけが対象）。" >&2
  exit 1
fi

echo "diff-coverage: changed-line coverage ${pct}% >= floor ${DIFF_COVERAGE_THRESHOLD}% (${covered}/${total} covered). pass."
