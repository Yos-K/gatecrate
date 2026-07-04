#!/bin/sh
# [汎用core] 消費スクリプトのドリフト検査（consumer 側・advisory）— スタック非依存
# gatecrate-type: advisory  (ADVISORY by design：既定は drift 検出でも exit 0・--strict で opt-in gating)
#
# WHY: gatecrate の「消費可能 sync」設計は1つの不変条件に乗っている——sync-manifest.yaml の
# `consumed_scripts` に挙げた各ファイルは、pin した `gatecrate_version`（旧 harness_kit_version）の
# キット原本と BYTE-IDENTICAL。これが "diff-zero sync" を真にし、週次の sync-propose PR を信頼可能にする。
# 消費スクリプトを upstream せず手元で編集する（or pin がズレる）と、不変条件が黙って壊れ、次の sync が
# 紛らわしい逆 diff を提案する。本ガードはその不変条件を再検査する。
#
# これは sync 機構の「消費者側の片割れ」: gatecrate 本体は producer（sync-propose）を出荷するが、
# 消費者が「pin 版と一致しているか」を検査する側は各自で自作する羽目になっていた（localmd が実装）。
# それを core 化したのが本スクリプト。
#
# ADVISORY by design: 既定では drift を検出しても build を落とさない（exit 0）＝検出はするがブロックしない。
#   --strict で drift を非0 に（opt-in gating）。ネットワーク/キット取得不能は --strict でも致命にしない
#   （オフラインが赤ゲートになってはいけない）——解決不能なら SKIP(exit 0)。
#
# Config (harness.config.sh または env):
#   KIT_REPO   キットの owner/name。既定: Yos-K/gatecrate（旧 HARNESS_KIT_REPO も honored）
#   KIT_DIR    既存のキット checkout を使う（clone せず・テスト/ローカル用）
#   GH_TOKEN   任意。clone URL に使う（rate limit 緩和）
#
# Usage: sh check-kit-drift.sh [--strict]
# Consumption model: repo root を git で解決するので kit/consumer 双方で動く（実用は consumer 側）。
set -u

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"

STRICT=0
[ "${1:-}" = "--strict" ] && STRICT=1

MANIFEST="$ROOT/sync-manifest.yaml"
KIT_REPO="${KIT_REPO:-${HARNESS_KIT_REPO:-Yos-K/gatecrate}}"

skip() { echo "kit-drift: SKIP — $1"; exit 0; }

[ -f "$MANIFEST" ] || skip "sync-manifest.yaml not found (nothing consumed yet)"

# Accept either the gatecrate or legacy harness-kit pin key.
PINNED="$(grep -E '^(gatecrate|harness_kit)_version:' "$MANIFEST" \
  | sed -E 's/^[^:]*: *//; s/"//g' | tr -d '[:space:]' | head -1)"
ADAPTER="$(grep '^adapter:' "$MANIFEST" \
  | sed 's/adapter: *//; s/"//g' | tr -d '[:space:]')"
[ -n "$PINNED" ] || skip "no gatecrate_version/harness_kit_version pinned in sync-manifest.yaml"
[ -n "$ADAPTER" ] || ADAPTER="android-jvm"

# consumed_scripts: entries under the `consumed_scripts:` key (strip "- ", inline "# ..." comments,
# trailing spaces). Same parse as sync-propose.yml.
CONSUMED="$(grep -A10000 '^consumed_scripts:' "$MANIFEST" \
  | grep -E '^[[:space:]]*-[[:space:]]' \
  | sed -E 's/^[[:space:]]*-[[:space:]]*//; s/[[:space:]]*#.*$//; s/[[:space:]]*$//')"
[ -n "$CONSUMED" ] || skip "consumed_scripts is empty"

# Resolve a kit checkout: an explicit KIT_DIR (tests/local), else clone the pinned tag into a
# temp dir. Clone failure is non-fatal (SKIP) so offline never turns into a red gate.
CLONED=""
if [ -n "${KIT_DIR:-}" ]; then
  [ -d "$KIT_DIR" ] || skip "KIT_DIR=$KIT_DIR does not exist"
else
  command -v git >/dev/null 2>&1 || skip "git not available to fetch kit"
  # mktemp only — a predictable PID-suffixed /tmp fallback is a symlink/collision risk (and is forbidden
  # by check-posix-portability). If mktemp is unavailable, skip (advisory) rather than use a guessable path.
  KIT_DIR="$(mktemp -d 2>/dev/null)" || skip "mktemp unavailable to stage kit clone — advisory only"
  [ -n "$KIT_DIR" ] || skip "mktemp returned empty path — advisory only"
  CLONED="$KIT_DIR"
  URL="https://github.com/${KIT_REPO}.git"
  [ -n "${GH_TOKEN:-}" ] && URL="https://x-access-token:${GH_TOKEN}@github.com/${KIT_REPO}.git"
  if ! git clone --depth 1 --branch "$PINNED" "$URL" "$KIT_DIR" >/dev/null 2>&1; then
    rm -rf "$CLONED"
    skip "could not clone $KIT_REPO@$PINNED (offline or tag missing) — advisory only"
  fi
fi
cleanup() { [ -n "$CLONED" ] && rm -rf "$CLONED"; }
trap cleanup EXIT INT TERM

KIT_WHITELIST="$KIT_DIR/sync-manifests/${ADAPTER}.yaml"
[ -f "$KIT_WHITELIST" ] || skip "kit whitelist $ADAPTER.yaml absent at $PINNED"

drift=0
unresolved=0
ok=0
report=""

for consumer_file in $CONSUMED; do
  [ -n "$consumer_file" ] || continue
  base="$(basename "$consumer_file")"
  # kit source path = the whitelist line ending in /<basename>
  rel_path="$(grep -E "/${base}\$" "$KIT_WHITELIST" \
    | grep -E '^[[:space:]]*-' | sed -E 's/^[[:space:]]*-[[:space:]]*//' | head -1)"
  if [ -z "$rel_path" ]; then
    report="${report}  UNRESOLVED  $consumer_file (not in kit whitelist)
"
    unresolved=$((unresolved + 1))
    continue
  fi
  kit_file="$KIT_DIR/$rel_path"
  if [ ! -f "$kit_file" ]; then
    report="${report}  UNRESOLVED  $consumer_file (kit source $rel_path missing at $PINNED)
"
    unresolved=$((unresolved + 1))
    continue
  fi
  if [ ! -f "$consumer_file" ]; then
    report="${report}  DRIFT       $consumer_file (declared consumed but absent locally)
"
    drift=$((drift + 1))
    continue
  fi
  if diff -q "$kit_file" "$consumer_file" >/dev/null 2>&1; then
    ok=$((ok + 1))
  else
    report="${report}  DRIFT       $consumer_file vs kit:$rel_path @ $PINNED
"
    drift=$((drift + 1))
  fi
done

echo "kit-drift: pinned=$PINNED adapter=$ADAPTER — ok=$ok drift=$drift unresolved=$unresolved"
[ -n "$report" ] && printf '%s' "$report"

if [ "$drift" -gt 0 ]; then
  cat <<MSG

$drift consumed script(s) no longer match gatecrate @ $PINNED.
The diff-zero invariant is broken. Reconcile by either:
  - reverting the local edit (consumed scripts must stay generic), or
  - upstreaming the change to gatecrate + bumping the pin.
MSG
  if [ "$STRICT" -eq 1 ]; then
    echo "kit-drift: FAIL (--strict)" >&2
    exit 1
  fi
  echo "kit-drift: advisory only — not failing the build (use --strict to gate)."
fi
exit 0
