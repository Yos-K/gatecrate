#!/bin/sh
# [汎用core] THIRD_PARTY_NOTICES の現行性ゲート — スタック非依存
#
# WHY: バンドルした第三者成果物（ライブラリ・フォント・JS 等）はライセンス表記が
# 必須だが、表記は手で書くため「成果物を更新したのに NOTICES を更新し忘れる」事故が
# 起きる。本ゲートは「バンドル資産が存在するなら、対応する表記が NOTICES に揃って
# いること」を機械検証し、表記漏れ・バージョン不一致を赤で止める。
#
# 加えて、外部 CDN への参照（unpkg / jsdelivr / cdnjs）がアプリコードに混入して
# いないことも検査する（バンドルしているのに CDN も参照していると、表記対象と実体が
# ずれる／オフライン前提が崩れる）。
#
# 設定（harness.config.sh または環境変数）:
#   TPN_FILE          — 表記ファイルのパス（既定: THIRD_PARTY_NOTICES.md）
#   TPN_BUNDLED_ASSET — 存在を確認するバンドル資産のパス（既定: 空 = 資産チェックなし）
#   TPN_REQUIRED_STRINGS — TPN_FILE 内に存在すべき文字列（空白区切り。各語が必須）。
#                          例: "Mermaid 11.15.0 MIT" のように資産名・版・ライセンスを並べる
#   TPN_CDN_SCAN_PATHS — CDN 参照を検査するソースパス（空白区切り。既定: 空 = CDN 検査なし）
#
# TPN_BUNDLED_ASSET が未設定なら表記チェックはスキップ（資産を同梱していない消費者向け）。
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

TPN_FILE="${TPN_FILE:-THIRD_PARTY_NOTICES.md}"
TPN_BUNDLED_ASSET="${TPN_BUNDLED_ASSET:-}"
TPN_REQUIRED_STRINGS="${TPN_REQUIRED_STRINGS:-}"
TPN_CDN_SCAN_PATHS="${TPN_CDN_SCAN_PATHS:-}"

checked=0

# Notice-currency check: only when a bundled asset is configured AND present.
if [ -n "$TPN_BUNDLED_ASSET" ] && [ -f "$ROOT/$TPN_BUNDLED_ASSET" ]; then
  if [ ! -f "$ROOT/$TPN_FILE" ]; then
    echo "Bundled asset '$TPN_BUNDLED_ASSET' is present but '$TPN_FILE' is missing." >&2
    exit 1
  fi
  for needle in $TPN_REQUIRED_STRINGS; do
    if ! grep -q -- "$needle" "$ROOT/$TPN_FILE"; then
      echo "'$TPN_FILE' is missing required notice string: $needle" >&2
      exit 1
    fi
  done
  checked=1
fi

# CDN-reference check: refuse external CDN references in configured source paths.
if [ -n "$TPN_CDN_SCAN_PATHS" ]; then
  scan_targets=""
  for p in $TPN_CDN_SCAN_PATHS; do
    [ -e "$ROOT/$p" ] && scan_targets="$scan_targets $ROOT/$p"
  done
  if [ -n "$scan_targets" ]; then
    # shellcheck disable=SC2086  # intentional word-splitting of scan_targets
    if grep -R -n -E "unpkg|jsdelivr|cdnjs" $scan_targets; then
      echo "CDN references are not allowed in app code." >&2
      exit 1
    fi
    checked=1
  fi
fi

if [ "$checked" -eq 0 ]; then
  echo "Third-party notice checks: nothing to verify (no bundled asset / scan paths configured)."
else
  echo "Third-party notice checks passed"
fi
