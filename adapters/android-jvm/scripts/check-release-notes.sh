#!/bin/sh
# [Android-JVMアダプタ] リリースノートの存在・文字数ゲート。
#
# WHY: Play Store にアップロードする前に、ロケール別の whatsnew.txt が欠けていたり、
# Play の文字数上限（既定 500）を超えていると、アップロードが失敗するか審査で差し戻される。
# 加えてプロジェクトのリポジトリ内リリースノート（docs/release/）の欠落も止める。これらを
# リリースより手前で機械検証し、落ちる基準を CI/ストアではなく手元で捕まえる。
#
# Play の whatsnew.txt（ロケールディレクトリ + 500 文字上限）は Play 固有のため
# core ではなくアダプタに置く。sh + wc のみ（python3 非依存・Termux 互換）。
#
# 設定（harness.config.sh または環境変数）:
#   RELEASE_NOTES_LOCALES   — whatsnew.txt のロケール（空白区切り。既定: "en-US ja-JP"）
#   WHATSNEW_DIR            — whatsnew.txt の基底ディレクトリ
#                            （既定: play-store/release-notes。<dir>/<locale>/whatsnew.txt を期待）
#   WHATSNEW_CHAR_LIMIT     — whatsnew.txt の文字数上限（既定: 500 = Play の上限）
#   RELEASE_DOCS_DIR        — リポジトリ内リリースノートの基底（既定: docs/release）
#   RELEASE_DOCS_SUFFIXES   — 確認するリリースノートのサフィックス（空白区切り。
#                            既定: ".md .ja.md"。<dir>/release-notes-v<VERSION>.<suffix> を期待。
#                            空文字なら docs リリースノートチェックをスキップ）
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
. "$ROOT/scripts/version-env.sh"

RELEASE_NOTES_LOCALES="${RELEASE_NOTES_LOCALES:-en-US ja-JP}"
WHATSNEW_DIR="${WHATSNEW_DIR:-play-store/release-notes}"
WHATSNEW_CHAR_LIMIT="${WHATSNEW_CHAR_LIMIT:-500}"
RELEASE_DOCS_DIR="${RELEASE_DOCS_DIR:-docs/release}"
# Use a sentinel so an explicitly empty value disables the docs check.
RELEASE_DOCS_SUFFIXES="${RELEASE_DOCS_SUFFIXES-.md .ja.md}"

fail() {
  echo "Release notes check failed: $1" >&2
  exit 1
}

# 1. Play whatsnew.txt: presence + character count per locale.
for locale in $RELEASE_NOTES_LOCALES; do
  f="$ROOT/$WHATSNEW_DIR/$locale/whatsnew.txt"
  if [ ! -f "$f" ]; then
    fail "missing $WHATSNEW_DIR/$locale/whatsnew.txt"
  fi
  char_count=$(wc -m < "$f")
  if [ "$char_count" -gt "$WHATSNEW_CHAR_LIMIT" ]; then
    fail "$WHATSNEW_DIR/$locale/whatsnew.txt exceeds $WHATSNEW_CHAR_LIMIT chars (got $char_count)"
  fi
done

# 2. In-repo release notes presence (one file per configured suffix).
for suffix in $RELEASE_DOCS_SUFFIXES; do
  f="$RELEASE_DOCS_DIR/release-notes-v$VERSION_NAME$suffix"
  if [ ! -f "$ROOT/$f" ]; then
    fail "missing $f"
  fi
done

echo "Release notes present for v$VERSION_NAME"
