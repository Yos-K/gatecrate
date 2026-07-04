#!/bin/sh
# scripts/sync-check.sh — gatecrate 同期チェックスクリプト
#
# 使い方: sh scripts/sync-check.sh <consumer_path>
#   <consumer_path>: 消費側プロジェクトのルートディレクトリパス
#
# 出力: 採用済みファイルのドリフト/欠落/未充足の依存（要対応）+ 未採用スクリプト件数（情報）
# 終了コード: 0=採用済みにドリフト無し且つ依存充足, 1=要対応あり, 2=エラー
#
# co-dependency 検証（issue #34）: 採用済みスクリプトが source する別の kit スクリプト（`$ROOT/scripts/<x>`）が
# 未採用なら実行時に壊れる。これを静的抽出で検出し `[DEP]` として要対応に含める。
#
# 採用集合（adopted set）モデル（issue #28）: 部分採用の消費者でも誤検知しないよう、
# 「消費側が採用したスクリプト」だけをドリフト判定の対象にする。採用集合は
#   優先: 消費側 sync-manifest.yaml の consumed_scripts 宣言（sync-propose.yml と同じ opt-in）
#   代替: 宣言が無ければ 消費側 scripts/ の実在ファイルから推定
# 未採用の kit スクリプトは「同期が必要」ではなく情報（件数のみ）として扱う。
#
# 設計根拠: design.md §3.2 sync-manifest + PR 型伝播
# 固有設定保護: ホワイトリスト方式（templates/, profiles/ は列挙されない）

set -eu

KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONSUMER_DIR="${1:-}"
MANIFEST="$KIT_DIR/sync-manifests/android-jvm.yaml"

# ---- managed ファイルのリストを取得（core_scripts + adapter_scripts セクションのみ）----
# POSIX 互換: \s の代わりに [[:space:]] を使用（macOS BSD sed 対応）
get_managed_files() {
  grep -E '^[[:space:]]+(- )(core|adapters)/' "$MANIFEST" \
    | sed 's/^[[:space:]]*- //'
}

# ---- 引数確認 ----
if [ -z "$CONSUMER_DIR" ]; then
  echo "エラー: 消費側プロジェクトのパスを指定してください" >&2
  echo "使い方: sh scripts/sync-check.sh <consumer_path>" >&2
  exit 2
fi

if [ ! -d "$CONSUMER_DIR" ]; then
  echo "エラー: 消費側ディレクトリが存在しません: $CONSUMER_DIR" >&2
  exit 2
fi

if [ ! -f "$MANIFEST" ]; then
  echo "エラー: sync-manifest が存在しません: $MANIFEST" >&2
  exit 2
fi

# ---- バージョン比較 ----
KIT_VERSION="$(cd "$KIT_DIR" && git describe --tags --abbrev=0 2>/dev/null || echo "unreleased")"

CONSUMER_MANIFEST="$CONSUMER_DIR/sync-manifest.yaml"
if [ -f "$CONSUMER_MANIFEST" ]; then
  CONSUMER_VERSION="$(grep '^harness_kit_version:' "$CONSUMER_MANIFEST" \
    | sed 's/harness_kit_version:[[:space:]]*//' \
    | sed 's/"//g; s/'"'"'//g' \
    | tr -d '[:space:]' \
    | sed 's/#.*//')"
else
  CONSUMER_VERSION="none"
fi

echo "=== gatecrate 同期チェック ==="
echo "gatecrate バージョン : $KIT_VERSION"
echo "消費側参照バージョン    : $CONSUMER_VERSION"
echo "消費側パス              : $CONSUMER_DIR"
echo ""

if [ "$KIT_VERSION" = "$CONSUMER_VERSION" ]; then
  echo "✓ バージョンは最新です。同期不要。"
  exit 0
fi

echo "バージョン差分を検出。sync-manifest に基づきファイルを確認します..."
echo ""

# ---- 固有設定の除外確認（ホワイトリスト方式の保証検証）----
echo "--- 固有設定の除外確認 ---"
VIOLATION=false
for rel_path in $(get_managed_files); do
  case "$rel_path" in
    templates/*|profiles/*)
      echo "❌ 設計エラー: 固有設定パスが管理対象に含まれています: $rel_path" >&2
      VIOLATION=true
      ;;
  esac
done

if [ "$VIOLATION" = "true" ]; then
  echo "設計を修正し、templates/ および profiles/ を sync-manifest から除外してください。" >&2
  exit 2
fi
echo "✓ templates/ および profiles/ は管理対象外（ホワイトリスト保護確認済み）"
echo ""

# ---- 採用集合（adopted set）の決定（opt-in モデル・sync-propose.yml と一致）----
# 消費側が「どのスクリプトを採用したか」を基準にする。これにより部分採用の消費者でも、
# 未採用の任意スクリプトを「同期が必要」と誤報告しない（issue #28）。
#   優先: 消費側 sync-manifest.yaml の consumed_scripts 宣言（opt-in の正典）
#   代替: 宣言が無ければ 消費側 scripts/ に実在するファイルから推定
ADOPTED="$(mktemp)"
trap 'rm -f "$ADOPTED"' EXIT
ADOPTION_SOURCE="消費側 scripts/ の実在ファイルから推定"
if [ -f "$CONSUMER_MANIFEST" ] && grep -q '^consumed_scripts:' "$CONSUMER_MANIFEST"; then
  ADOPTION_SOURCE="消費側 sync-manifest.yaml の consumed_scripts（opt-in 宣言）"
  grep -A10000 '^consumed_scripts:' "$CONSUMER_MANIFEST" \
    | grep -E '^[[:space:]]*-[[:space:]]' \
    | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//' \
    | while IFS= read -r p; do [ -n "$p" ] && basename "$p"; done \
    | sort -u > "$ADOPTED"
elif [ -d "$CONSUMER_DIR/scripts" ]; then
  ls -1 "$CONSUMER_DIR/scripts" 2>/dev/null | sort -u > "$ADOPTED"
fi

# kit が管理する全スクリプトの basename 集合（co-dependency が kit 由来か判定するのに使う）。
MANAGED="$(mktemp)"
trap 'rm -f "$ADOPTED" "$MANAGED"' EXIT
for rel_path in $(get_managed_files); do basename "$rel_path"; done | sort -u > "$MANAGED"

# あるスクリプトが source する kit スクリプト依存（basename）を静的抽出する。
# 依存は `$ROOT/scripts/<name>` という文字列としてコード内に必ず現れる（直接 source でも
# 変数代入経由でも）。依存宣言がコード自体に在るのでドリフトしない。issue #34。
extract_script_deps() {
  grep -oE '\$ROOT/scripts/[A-Za-z0-9._-]+\.(sh|java|py)' "$1" 2>/dev/null \
    | sed 's#.*/##' | sort -u
}

# ---- 採用済みファイルのドリフト確認（要対応）/ 未採用は情報扱い ----
DRIFT_CNT=0      # 採用済みで kit master と差分あり（要対応）
MISSING_CNT=0    # consumed 宣言済みだが消費側に存在しない（要対応）
AVAIL_CNT=0      # kit にあるが未採用（情報・同期不要）

echo "--- 採用済みファイルのドリフト確認（採用集合: ${ADOPTION_SOURCE}）---"
for rel_path in $(get_managed_files); do
  kit_file="$KIT_DIR/$rel_path"
  base_name="$(basename "$rel_path")"
  consumer_file="$CONSUMER_DIR/scripts/$base_name"

  if [ ! -f "$kit_file" ]; then
    echo "  [WARN] kit 側にファイルが存在しません: $rel_path"
    continue
  fi

  if ! grep -qxF "$base_name" "$ADOPTED"; then
    AVAIL_CNT=$((AVAIL_CNT + 1))   # 未採用 = この消費者の対象外（ノイズにしない）
    continue
  fi

  if [ ! -f "$consumer_file" ]; then
    echo "  [MISSING] scripts/$base_name (consumed 宣言済みだが消費側に存在しない)"
    MISSING_CNT=$((MISSING_CNT + 1))
  elif ! diff -q "$kit_file" "$consumer_file" > /dev/null 2>&1; then
    echo "  [UPDATED] scripts/$base_name  <- $rel_path"
    DRIFT_CNT=$((DRIFT_CNT + 1))
  fi
done

# ---- co-dependency 確認（採用済みスクリプトが source する kit スクリプトが未採用なら壊れる・issue #34）----
DEP_CNT=0
for rel_path in $(get_managed_files); do
  base_name="$(basename "$rel_path")"
  grep -qxF "$base_name" "$ADOPTED" || continue          # 採用済みスクリプトだけを起点に解析
  kit_file="$KIT_DIR/$rel_path"
  [ -f "$kit_file" ] || continue
  for dep in $(extract_script_deps "$kit_file"); do
    [ "$dep" = "$base_name" ] && continue                # 自己参照は無視
    grep -qxF "$dep" "$MANAGED" || continue              # kit 管理外（消費側固有）の参照は対象外
    if ! grep -qxF "$dep" "$ADOPTED"; then
      echo "  [DEP] scripts/$base_name は scripts/$dep を source しますが未採用です（consumed_scripts に追加）"
      DEP_CNT=$((DEP_CNT + 1))
    fi
  done
done

ACTIONABLE=$((DRIFT_CNT + MISSING_CNT + DEP_CNT))
echo ""

if [ "$ACTIONABLE" -eq 0 ]; then
  echo "✓ 採用済みファイルに kit master とのドリフトはありません（diff-zero・依存も充足）"
  [ "$AVAIL_CNT" -gt 0 ] && \
    echo "  参考: kit に未採用の任意スクリプトが ${AVAIL_CNT} 件（採用は consumed_scripts で opt-in。同期不要）"
  exit 0
fi

echo "採用済みファイルに要対応を検出: 更新 ${DRIFT_CNT} / 欠落 ${MISSING_CNT} / 未充足の依存 ${DEP_CNT}"
[ "$AVAIL_CNT" -gt 0 ] && echo "  （未採用の任意スクリプト ${AVAIL_CNT} 件は対象外）"
echo ""
echo "次のステップ: harness-sync.yml（sync-propose）で採用済みファイル＋依存を更新するか、"
echo "  kit master を生のまま（git-first スクリプトは install 変換なし）vendoring して揃えてください。"
exit 1
