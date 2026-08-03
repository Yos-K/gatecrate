#!/bin/sh
# [POSIX shアダプタ] シェルスクリプトのミューテーションゲート — 挙動テストの検出力を測る
#
# WHY: シェルで書かれたハーネスには「テストの検出力」を測る手段が無かった。言語スタックには
# cargo-mutants / stryker / mutmut があるが、POSIX sh 用の等価物は存在しない。結果として
# **最も価値のある実践（変異テスト）が、唯一機械化されていない**状態が残る——ゲートは成果物を
# 検査するが、そのゲートを検査するテストが十分かは誰も見ない。
#
# 実測の根拠: あるセッションで手作業により26体の変異を注入したところ、**2体は sed が空振りして
# 「変異が生き残った」という偽の結果**を出した（置換パターンがファイルに一致しなかったのに、
# 実行は成功し結果が変わらないため「テストが検出できなかった」と見える）。さらに新設ゲートの初版が
# `grep -P` 依存で黙って壊れていた事例もあり、手作業の変異テストは信頼できないと判明した。
#
# だから本スクリプトの中心的な不変条件は次の1点である:
#   **変異が実際にファイルを書き換えたことを確認してからテストを回す。**
#   書き換わっていない変異は SKIP として報告し、生存(survived)には数えない。
#   これを守らないと「適用されていない変異」が「テストが弱い」と誤報告され、逆の結論を導く。
#
# 判定: 変異を1体ずつ注入し、挙動テストが**落ちれば killed**（検出力あり）、**通れば survived**
# （テストの穴）。survived が floor を超えたら非0。
#
# Config (optional, from harness.config.sh):
#   SH_MUTATION_TARGETS   — 変異対象のグロブ（既定: core/scripts/*.sh が在ればそれ、無ければ scripts/*.sh）
#   SH_MUTATION_TEST_CMD  — 検出に使うコマンド（既定: 同アダプタの run-tests.sh）
#   SH_MUTATION_MAX_SURVIVORS — 許容する生存数（既定: 0）
#   MUTATION_SCOPE        — diff | full（既定: full。core/scripts/mutation-scope.sh の共通契約に従う）
#   MUTATION_DIFF_BASE    — diff モードの基準 ref
#
# Usage: sh adapters/posix-sh/scripts/run-mutation.sh
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"

if [ -z "${SH_MUTATION_TARGETS:-}" ]; then
  if [ -d "core/scripts" ]; then SH_MUTATION_TARGETS="core/scripts/*.sh"; else SH_MUTATION_TARGETS="scripts/*.sh"; fi
fi
MAX_SURVIVORS="${SH_MUTATION_MAX_SURVIVORS:-0}"
ADAPTER_DIR="$(dirname -- "$0")"
TEST_CMD="${SH_MUTATION_TEST_CMD:-sh $ADAPTER_DIR/run-tests.sh}"

# --- 変異演算子 -----------------------------------------------------------------
# シェルには意味を保つ変異演算子の標準が無いため、「ゲートの判定を無力化する」方向の置換に絞る。
# ゲートが守るべき性質は「違反を非0で拒否する」ことなので、それを壊す変異をテストが捕まえられるか、
# が測りたいことである。各行は "<説明>|<sed式>"。
MUTATORS='reject を無効化(exit 1 -> exit 0)|s/exit 1$/exit 0/
条件を常に真に(if ... ; then -> if true; then)|s/^\( *\)if \[ [^]]* \]; then/\1if true; then/
条件を常に偽に|s/^\( *\)if \[ [^]]* \]; then/\1if false; then/
境界比較を緩める(-gt -> -ge)|s/ -gt / -ge /
境界比較を緩める(-lt -> -le)|s/ -lt / -le /
等値比較を反転(= -> !=)|s/ = / != /
早期 return を成功に|s/return 1$/return 0/'

# --- 対象の解決（diff スコープは共通エンジンに従う） ------------------------------
SCOPE_TOOL="core/scripts/mutation-scope.sh"
[ -f "$SCOPE_TOOL" ] || SCOPE_TOOL="scripts/mutation-scope.sh"
TARGETS=""
if [ "${MUTATION_SCOPE:-full}" = "diff" ] && [ -f "$SCOPE_TOOL" ]; then
  TARGETS="$(sh "$SCOPE_TOOL" changed '*.sh' 2>/dev/null || true)"
  [ -n "$TARGETS" ] || { echo "run-mutation: no changed *.sh vs base — skipping (diff scope)"; exit 0; }
else
  # shellcheck disable=SC2086  # 意図したグロブ展開
  TARGETS="$(ls $SH_MUTATION_TARGETS 2>/dev/null || true)"
fi
[ -n "$TARGETS" ] || { echo "run-mutation: no target scripts matched $SH_MUTATION_TARGETS" >&2; exit 1; }

# 結果は while がサブシェルで走るため変数に貯められない。1ファイルに集約して後から数える
# （killed/skipped も数えることで、生存ゼロでも「何体試したか」が診断できる）
RESULTS="$(mktemp)"
trap 'rm -f "$RESULTS"' EXIT INT TERM

echo "run-mutation: injecting shell mutants (targets: $(printf '%s\n' "$TARGETS" | wc -l | tr -d ' ') file(s))"

for f in $TARGETS; do
  [ -f "$f" ] || continue
  case "$f" in */test-*.sh|tests/*) continue ;; esac   # テスト自身は変異させない
  printf '%s\n' "$MUTATORS" | while IFS='|' read -r label expr; do
    [ -n "$expr" ] || continue
    backup="$(mktemp)"; cp "$f" "$backup"
    sed "$expr" "$backup" > "$f" 2>/dev/null || cp "$backup" "$f"

    # ★中心的な不変条件: 変異が実際に適用されたか確認する。
    #   適用されていない(=元と同一)変異でテストを回すと、結果が変わらないため
    #   「テストが検出できなかった=survived」と誤報告される。手作業で2度踏んだ罠。
    if cmp -s "$backup" "$f"; then
      cp "$backup" "$f"; rm -f "$backup"
      echo "SKIP    $f — ${label}（このファイルに該当箇所なし）" | tee -a "$RESULTS"
      continue
    fi

    if $TEST_CMD >/dev/null 2>&1; then
      echo "SURVIVED $f — $label" | tee -a "$RESULTS"
    else
      echo "killed   $f — $label" | tee -a "$RESULTS"
    fi
    cp "$backup" "$f"; rm -f "$backup"
  done
done

# `grep -c PAT f || echo 0` は使わない: grep -c はマッチ0件でも「0」を出力した上で exit 1 するため
# || も発火し "0\n0" になる。条件文脈では [ の型エラー(2)が偽扱いされ**偶然**動くが、サマリが機械
# 可読でなくなり、比較を条件文脈の外へ動かした瞬間に set -e で死ぬ。set -e ガードだけ残す。
killed="$(grep -c '^killed'   "$RESULTS" || :)"
survived="$(grep -c '^SURVIVED' "$RESULTS" || :)"
skipped="$(grep -c '^SKIP'    "$RESULTS" || :)"
echo "run-mutation: killed=$killed survived=$survived skipped=$skipped (max allowed: $MAX_SURVIVORS)"
if [ "$survived" -gt "$MAX_SURVIVORS" ]; then
  echo "run-mutation: FAIL — surviving mutants mean the behavior tests do not detect these breakages:" >&2
  grep '^SURVIVED' "$RESULTS" | sed 's/^/  /' >&2
  echo "  Add a property that fails for each, then re-run. Do NOT weaken the mutator set." >&2
  exit 1
fi
echo "run-mutation: pass — every applied mutant was killed by the behavior tests."
