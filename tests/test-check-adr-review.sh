#!/bin/sh
# tests/test-check-adr-review.sh — core/scripts/check-adr-review.sh の挙動テスト
#
# 文脈（issue #25）: feat/fix コミットが古い設計判断を黙って覆すのを防ぐため、対象コミットに
# `ADR-Review:` トレーラを1つだけ要求する。実 git フィクスチャで全棄却経路を決定論に検証する。
#
# 検証する性質:
#   1. 妥当な ADR パス宣言の feat コミット -> pass(exit 0)
#   2. 理由付き none -> pass ／ 裸の none -> fail
#   3. トレーラ欠落・複数トレーラ -> fail
#   4. 実在しない ADR 参照・companion(.ja.md) 直接参照 -> fail
#   5. 参照は「宣言コミット時点」で検査（同コミット追加は pass・後から追加は fail）
#   6. companion 欠落・必須セクション欠落（正典/companion 双方）-> fail
#   7. 対象外タイプ(chore)はトレーラ不要で pass
#   8. 解決不能な base -> 明示 fail(exit 2)・黙って skip しない
#   9. 設定面: ADR_ALLOW_REASONED_NONE=false で理由付き none も fail、
#      ADR_COMPANION_SUFFIXES='' で companion 不要
#  10. --message モード（commit-msg フック用）: 妥当 -> 0／トレーラ欠落・裸 none -> 1
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-adr-review.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

new_repo() {
  W="$(mktemp -d)"
  git -C "$W" init -q -b main
  git -C "$W" config user.email t@t.t
  git -C "$W" config user.name t
  git -C "$W" config commit.gpgsign false
  mkdir -p "$W/docs/adr"
}
gc() { git -C "$W" "$@"; }
cmt() { gc add -A; gc commit -q --allow-empty -m "$1" ${2:+-m "$2"}; }
run() { OUT="$(cd "$W" && sh "$SCRIPT" "$@" 2>&1)" && RC=0 || RC=$?; }

# adr <NNNN>-<slug> — 全必須セクションを持つ正典+companion を書く
adr() {
  { echo "# t"
    for s in 'Decision' 'Alternatives Considered' 'Why This Decision' \
             'Why Alternatives Were Rejected' 'Reconsider When'; do
      printf '## %s\nbody\n' "$s"; done; } > "$W/docs/adr/$1.md"
  { echo "# t"
    for s in '決定事項' '検討した選択肢' '選択理由' '選択しなかった理由' '決定を見直す契機'; do
      printf '## %s\nbody\n' "$s"; done; } > "$W/docs/adr/$1.ja.md"
}

echo "property 1: a feat commit declaring a valid ADR passes"
new_repo; adr 0001-base; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: docs/adr/0001-base.md"
run main
[ "$RC" -eq 0 ] && pass "valid declaration exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: reasoned none passes; bare none fails"
new_repo; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: none (pure addition, no decision touched)"
run main
[ "$RC" -eq 0 ] && pass "reasoned none exit 0" || fail "expected 0, got $RC: $OUT"
echo y > "$W/y.txt"; cmt "fix: add y" "ADR-Review: none"
run main
[ "$RC" -eq 1 ] && pass "bare none exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'explain why' && pass "explains the reason rule" || fail "no guidance: $OUT"

echo "property 3: missing trailer and multiple trailers fail"
new_repo; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x"
run main
[ "$RC" -eq 1 ] && pass "missing trailer exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'exactly one ADR-Review' && pass "reports trailer count" || fail "no count msg: $OUT"
new_repo; adr 0001-a; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"
gc add -A; gc commit -q -m "feat: add x" -m "ADR-Review: docs/adr/0001-a.md" -m "ADR-Review: none (dup)"
run main
[ "$RC" -eq 1 ] && pass "multiple trailers exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 4: nonexistent ADR and companion-path references fail"
new_repo; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: docs/adr/0009-ghost.md"
run main
[ "$RC" -eq 1 ] && pass "ghost ADR exit 1" || fail "expected 1, got $RC: $OUT"
new_repo; adr 0001-a; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: docs/adr/0001-a.ja.md"
run main
[ "$RC" -eq 1 ] && pass "companion reference exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'canonical' && pass "points to the canonical rule" || fail "no canonical msg: $OUT"

echo "property 5: the reference is checked at the declaring commit"
new_repo; cmt "chore: init"
gc checkout -q -b f
adr 0002-new
echo x > "$W/x.txt"; cmt "feat: add x with adr" "ADR-Review: docs/adr/0002-new.md"
run main
[ "$RC" -eq 0 ] && pass "ADR added in the same commit passes" || fail "expected 0, got $RC: $OUT"
new_repo; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: docs/adr/0003-late.md"
adr 0003-late; cmt "docs: add adr later"
run main
[ "$RC" -eq 1 ] && pass "ADR added only later fails" || fail "expected 1, got $RC: $OUT"

echo "property 6: missing companion / missing required sections fail"
new_repo; adr 0001-a; rm "$W/docs/adr/0001-a.ja.md"; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: docs/adr/0001-a.md"
run main
[ "$RC" -eq 1 ] && pass "missing companion exit 1" || fail "expected 1, got $RC: $OUT"
new_repo; adr 0001-a
printf '# t\n## Decision\nbody\n' > "$W/docs/adr/0001-a.md"   # 他セクション欠落
cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: docs/adr/0001-a.md"
run main
[ "$RC" -eq 1 ] && pass "canonical missing sections exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'missing required section' && pass "names the gap" || fail "no section msg: $OUT"
new_repo; adr 0001-a
printf '# t\n## 決定事項\nbody\n' > "$W/docs/adr/0001-a.ja.md"
cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: docs/adr/0001-a.md"
run main
[ "$RC" -eq 1 ] && pass "companion missing sections exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 7: unconfigured commit types pass without a trailer"
new_repo; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "chore: tidy"
echo y > "$W/y.txt"; cmt "docs: note"
run main
[ "$RC" -eq 0 ] && pass "chore/docs need no trailer" || fail "expected 0, got $RC: $OUT"

echo "property 8: an unresolvable base fails explicitly"
new_repo; cmt "chore: init"
run origin/nope
[ "$RC" -eq 2 ] && pass "unresolvable base exit 2" || fail "expected 2, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'not resolvable' && pass "reports the base" || fail "no base msg: $OUT"

echo "property 9: configuration surface is honored"
new_repo; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: none (still fails when disabled)"
OUT="$(cd "$W" && ADR_ALLOW_REASONED_NONE=false sh "$SCRIPT" main 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "reasoned none rejected when disabled" || fail "expected 1, got $RC: $OUT"
new_repo; adr 0001-a; rm "$W/docs/adr/0001-a.ja.md"; cmt "chore: init"
gc checkout -q -b f
echo x > "$W/x.txt"; cmt "feat: add x" "ADR-Review: docs/adr/0001-a.md"
OUT="$(cd "$W" && ADR_COMPANION_SUFFIXES='' sh "$SCRIPT" main 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "no companion required when suffixes empty" || fail "expected 0, got $RC: $OUT"

echo "property 10: --message mode validates a commit-msg file"
new_repo; adr 0001-a; cmt "chore: init"
printf 'feat: add x\n\nADR-Review: docs/adr/0001-a.md\n' > "$W/msg.txt"
run --message msg.txt
[ "$RC" -eq 0 ] && pass "valid message exit 0" || fail "expected 0, got $RC: $OUT"
printf 'feat: add x\n' > "$W/msg.txt"
run --message msg.txt
[ "$RC" -eq 1 ] && pass "missing trailer exit 1" || fail "expected 1, got $RC: $OUT"
printf 'feat: add x\n\nADR-Review: none\n' > "$W/msg.txt"
run --message msg.txt
[ "$RC" -eq 1 ] && pass "bare none exit 1" || fail "expected 1, got $RC: $OUT"
printf 'chore: tidy\n' > "$W/msg.txt"
run --message msg.txt
[ "$RC" -eq 0 ] && pass "unconfigured type exit 0" || fail "expected 0, got $RC: $OUT"

echo ""
echo "check-adr-review tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
