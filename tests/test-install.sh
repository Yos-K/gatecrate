#!/bin/sh
# tests/test-install.sh — install.sh の挙動テスト
#
# 文脈: install.sh は 489行・12以上の文書が参照する「エージェント無し/CI/Codex 消費者の唯一の入口」なのに
# 挙動テストが無かった（テスト無しゲートが黙って壊れた file-line の教訓は installer にも当てはまる）。
# 本テストは非対話・非ネットワーク経路（--with-cc-sdd の npx は対象外）の配布挙動を回帰固定する。
#
# 検証する性質:
#   1. minimal: コア衛生6本が実行可能で入り、standard-core（es-lint 等）は入らない（プロファイル境界）
#   2. harness.config.sh はテンプレから生成され、既存なら上書きしない（固有設定の保護）
#   3. git-first スクリプトは raw コピー＝kit と byte 一致（差分ゼロ同期の前提）
#   4. rust: スタックアダプタ（run-tests/run-mutation）と standard-core が入る
#   5. --profile auto: Cargo.toml → rust / ビルド定義なし → minimal
#   6. 不正プロファイル -> exit 1
#   7. git repo への install はダッシュボード初期スナップショットを生成（standard-core 配布時）
#   8. 導入したゲートが導入先で実走できる（smoke: check-file-line-limit が pass）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL="$ROOT/install.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT

echo "property 1: minimal installs the six core hygiene scripts and nothing stack-specific"
T1="$D/t-min"; mkdir -p "$T1"
sh "$INSTALL" --profile minimal --target "$T1" >/dev/null 2>&1 || fail "minimal install failed"
for s in check-conventional-title.sh check-no-committed-secrets.sh check-file-line-limit.sh \
         probe-gate-liveness.sh check-test-compiles.sh check-posix-portability.sh; do
  [ -x "$T1/scripts/$s" ] && pass "minimal has $s (executable)" || fail "minimal missing $s"
done
[ -f "$T1/scripts/es-lint.sh" ] && fail "minimal wrongly includes standard-core (es-lint)" \
  || pass "standard-core stays out of minimal"
[ -f "$T1/scripts/es-coverage.sh" ] && fail "minimal wrongly includes es-coverage" \
  || pass "new tools also stay out of minimal"

echo "property 2: harness.config.sh is generated once and never overwritten"
[ -f "$T1/harness.config.sh" ] && pass "config generated from template" || fail "config not generated"
printf '# consumer-owned value\nFILE_LINE_LIMIT=123\n' > "$T1/harness.config.sh"
sh "$INSTALL" --profile minimal --target "$T1" >/dev/null 2>&1
grep -q 'FILE_LINE_LIMIT=123' "$T1/harness.config.sh" \
  && pass "existing config preserved on re-install" || fail "re-install clobbered consumer config"

echo "property 3: git-first scripts are raw copies (byte-identical to the kit)"
cmp -s "$ROOT/core/scripts/check-file-line-limit.sh" "$T1/scripts/check-file-line-limit.sh" \
  && pass "byte-identical copy (diff-free sync precondition)" || fail "installed copy differs from kit"

echo "property 4: rust profile installs the stack adapter plus standard-core"
T2="$D/t-rust"; mkdir -p "$T2"
sh "$INSTALL" --profile rust --target "$T2" >/dev/null 2>&1 || fail "rust install failed"
[ -x "$T2/scripts/run-tests.sh" ] && pass "rust adapter run-tests.sh installed" || fail "run-tests.sh missing"
[ -x "$T2/scripts/run-mutation.sh" ] && pass "rust adapter run-mutation.sh installed" || fail "run-mutation.sh missing"
[ -x "$T2/scripts/es-lint.sh" ] && pass "standard-core (es-lint) included for stack profiles" || fail "es-lint missing"
for s2 in es-coverage.sh check-es-assertions.sh check-model-refuted.sh probe-semantic-liveness.sh measure-modularity.sh; do
  [ -x "$T2/scripts/$s2" ] && pass "standard-core ships $s2" || fail "standard-core missing $s2"
done

echo "property 5: --profile auto detects the stack from build files"
T3="$D/t-auto-rust"; mkdir -p "$T3"; touch "$T3/Cargo.toml"
OUT="$(sh "$INSTALL" --profile auto --target "$T3" 2>&1)" || fail "auto(rust) install failed"
printf '%s\n' "$OUT" | grep -q "profile='rust'" && pass "Cargo.toml -> rust" || fail "auto did not pick rust: $OUT"
T4="$D/t-auto-min"; mkdir -p "$T4"
OUT="$(sh "$INSTALL" --profile auto --target "$T4" 2>&1)" || fail "auto(minimal) install failed"
printf '%s\n' "$OUT" | grep -q "profile='minimal'" && pass "no build files -> minimal" || fail "auto did not pick minimal: $OUT"

echo "property 5b: brownfield = minimal base + ratchet lane, WITHOUT standard-core"
T7="$D/t-brown"; mkdir -p "$T7"
sh "$INSTALL" --profile brownfield --target "$T7" >/dev/null 2>&1 || fail "brownfield install failed"
[ -x "$T7/scripts/check-diff-coverage.sh" ] && pass "brownfield has diff-coverage ratchet" || fail "diff-coverage missing"
[ -x "$T7/scripts/check-no-received-approvals.sh" ] && pass "brownfield has received-approvals gate" || fail "no-received-approvals missing"
[ -x "$T7/scripts/check-no-committed-secrets.sh" ] && pass "brownfield includes the minimal core" || fail "minimal core missing"
[ -f "$T7/scripts/es-lint.sh" ] && fail "brownfield wrongly includes standard-core (es-lint)" \
  || pass "standard-core stays out of brownfield"

echo "property 6: invalid profile -> exit 1"
sh "$INSTALL" --profile nosuch --target "$D/t-bad" >/dev/null 2>&1 && fail "invalid profile accepted" \
  || pass "invalid profile rejected"

echo "property 7: installing into a git repo seeds the dashboard snapshot (standard-core profiles)"
T5="$D/t-dash"; mkdir -p "$T5"; git -C "$T5" init -q
sh "$INSTALL" --profile rust --target "$T5" >/dev/null 2>&1 || fail "rust install into git repo failed"
[ -f "$T5/docs/harness-status.md" ] && grep -q 'gates' "$T5/docs/harness-status.md" \
  && pass "docs/harness-status.md seeded" || fail "dashboard snapshot not generated"

echo "property 8: an installed gate actually runs in the consumer (smoke)"
# 独立ターゲット（property 2 の config 改変と干渉しない）。消費者らしい config を置いて実走する。
T6="$D/t-smoke"; mkdir -p "$T6"
sh "$INSTALL" --profile minimal --target "$T6" >/dev/null 2>&1
git -C "$T6" init -q
printf 'FILE_LINE_LIMIT=300\nFILE_LINE_NAMES="*.md"\n' > "$T6/harness.config.sh"
printf '# small doc\n' > "$T6/README.md"
( cd "$T6" && sh scripts/check-file-line-limit.sh >/dev/null 2>&1 ) \
  && pass "check-file-line-limit runs and passes in the consumer" || fail "installed gate does not run"
# 消費者 config が実際に効くこと（limit=1 にすると同じゲートが reject する）
printf 'FILE_LINE_LIMIT=1\nFILE_LINE_NAMES="*.md"\n' > "$T6/harness.config.sh"
printf 'line1\nline2\n' > "$T6/README.md"
( cd "$T6" && sh scripts/check-file-line-limit.sh >/dev/null 2>&1 ) \
  && fail "consumer config ignored (limit=1 did not reject)" \
  || pass "consumer harness.config.sh drives the installed gate"

echo "---- test-install: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
