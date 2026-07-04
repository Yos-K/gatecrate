#!/bin/sh
# [汎用コア] ESドメイン分析の成果物完全性ゲート（prevention） — スタック非依存
# gatecrate-type: prevention
#
# WHY: 「TO-BEを作らずコンテキストマップだけ」等の手抜き(成果物の欠落)は、スキルの自己レビュー(判断)に委ねると
# 抜ける。完成＝6タブ(AS-IS/TO-BE/コンテキストマップ/用語集/ビジネス分析/分析レポート)の源泉が揃うこと、で
# **機械判定できる**。これをゲートで強制し、終了条件を権威化する（TAKTループ/品質バーがこれをgreenに駆動）。
# 用語集は .es からの射影なので別ファイル不要＝AS-IS/TO-BEがあれば満たす。
#
# 合格条件（<dir> に揃い、各 .es/.cmap が文法ゲートを通ること）:
#   D1 AS-IS の .es（`*-tobe.es` でない .es が最低1つ）        D2 TO-BE の .es（`*-tobe.es`）
#   D3 コンテキストマップ `.cmap`                              D4 ビジネス分析: TO-BE の .es に `biz=` がある
#   D5 分析レポート: リファクタ計画 と 永続化設計 の md        D6 各 .es は es-lint、各 .cmap は es-cmap-lint を通る
# Usage: sh check-es-deliverables.sh <model-dir>   ( 欠落/違反で exit 1 )
set -eu
DIR="${1:?usage: check-es-deliverables.sh <model-dir>}"
[ -d "$DIR" ] || { echo "check-es-deliverables: not a dir: $DIR" >&2; exit 2; }
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

miss="$(mktemp)"; trap 'rm -f "$miss"' EXIT
# *.es のうち AS-IS（-tobe でない）と TO-BE を分ける
asis=""; tobe=""
for f in "$DIR"/*.es; do
  [ -f "$f" ] || continue
  case "$f" in *-tobe.es) tobe="${tobe} $f" ;; *) asis="${asis} $f" ;; esac
done
cmaps=""; for f in "$DIR"/*.cmap; do [ -f "$f" ] && cmaps="${cmaps} $f"; done

[ -n "$asis" ] || echo "  [ERROR] D1 AS-IS の .es が無い（コードの流れ。例 <domain>.es）" >> "$miss"
[ -n "$tobe" ] || echo "  [ERROR] D2 TO-BE の .es が無い（あるべき設計。例 <domain>-tobe.es）← TO-BE省略は不可" >> "$miss"
[ -n "$cmaps" ] || echo "  [ERROR] D3 コンテキストマップ .cmap が無い" >> "$miss"
# D4 ビジネス分析: TO-BE に biz=
if [ -n "$tobe" ]; then
  grep -lq 'biz=' $tobe 2>/dev/null || echo "  [ERROR] D4 ビジネス分析の源泉が無い（TO-BE の event に biz=revenue|value|degrade）" >> "$miss"
fi
# D5 分析レポート: roadmap と persistence の md
ls "$DIR"/*refactoring*roadmap*.md "$DIR"/*roadmap*.md >/dev/null 2>&1 || echo "  [ERROR] D5 リファクタリング＋ハーネス ロードマップ(md)が無い" >> "$miss"
ls "$DIR"/*persistence*design*.md "$DIR"/*persistence*.md >/dev/null 2>&1 || echo "  [ERROR] D5 永続化設計(md)が無い" >> "$miss"
# D6 各 .es/.cmap が文法ゲートを通る
for f in $asis $tobe; do
  sh "$ROOT/es-lint.sh" "$f" >/dev/null 2>&1 || echo "  [ERROR] D6 es-lint 違反: $(basename "$f")（文法を直す）" >> "$miss"
done
for f in $cmaps; do
  sh "$ROOT/es-cmap-lint.sh" "$f" >/dev/null 2>&1 || echo "  [ERROR] D6 es-cmap-lint 違反: $(basename "$f")" >> "$miss"
done

echo "=== check-es-deliverables: $DIR ==="
if [ -s "$miss" ]; then
  cat "$miss"
  echo "---- ERROR=$(wc -l < "$miss" | tr -d ' ') ----（6タブの源泉が揃うまで未完成。足りないものを作る）"
  exit 1
fi
echo "  OK: AS-IS / TO-BE / コンテキストマップ / ビジネス分析源泉 / 分析レポート が揃い、文法ゲート通過"
echo "---- ERROR=0 ----"
