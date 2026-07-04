#!/bin/sh
# tests/test-es-lint.sh — core/scripts/es-lint.sh の挙動テスト
#
# 文脈: ESの文法（actor→command→aggregate→event→policy）をプロンプト（判断層）に置くとAIが破る。実害として
# 手描き図で「ルールを集約と誤ラベル」「イベントをイベントへ直結」が同時に混入した。es-lint はその文法を機械
# 強制する予防ゲート。本テストは「AIがやらかす典型違反を必ず reject し、正しいモデルは通す」を回帰固定する。
#
# 検証する性質:
#   1. 文法的に正しいモデル -> pass(exit 0)
#   2. event→event 直結 -> FAIL(exit 1) で名指し
#   3. command→event（集約スキップ）-> FAIL(exit 1) で名指し
#   4. 不変条件のない aggregate -> FAIL(exit 1)（「集約ではなくルール」を検出）
#   5. 1イベントを複数集約がemit -> FAIL(exit 1)
#   6. 未宣言ノードを参照するエッジ -> FAIL(exit 1)
#   7. 証拠リンクのないイベント -> warn は出るが exit 0（ブロックしない）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/es-lint.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

D="$(mktemp -d)"
trap 'rm -rf "$D"' EXIT
run() { OUT="$(sh "$SCRIPT" "$1" 2>&1)" && RC=0 || RC=$?; }

echo "property 1: a grammatically valid model passes (exit 0)"
cat > "$D/good.es" <<'EOF'
N u actor 利用者
N c command 文書を開く
N a aggregate タブ集約 | invariant=タブ1以上 | evidence=Tabs.java:12
N e event タブが開かれた | evidence=Tabs.java:28
E u issues c
E c handles a
E a emits e
EOF
run "$D/good.es"
[ "$RC" -eq 0 ] && pass "valid model -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property 2: event -> event is rejected"
cat > "$D/ev-ev.es" <<'EOF'
N u actor 利用者
N c command 文書を開く
N a aggregate タブ集約 | invariant=タブ1以上 | evidence=x:1
N e1 event 文書が開かれた | evidence=x:1
N e2 event タブが開かれた | evidence=x:2
E u issues c
E c handles a
E a emits e1
E e1 triggers e2
EOF
run "$D/ev-ev.es"
[ "$RC" -eq 1 ] && pass "event->event -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'event(e1) --triggers--> event(e2)' && pass "names the event->event edge" || fail "edge not named: $OUT"

echo "property 3: command -> event (skipping aggregate) is rejected"
cat > "$D/cmd-ev.es" <<'EOF'
N u actor 利用者
N c command ピン留めする
N e event ピン留めされた | evidence=Pin.java:37
E u issues c
E c emits e
EOF
run "$D/cmd-ev.es"
[ "$RC" -eq 1 ] && pass "command->event -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q '集約' && pass "explains the skipped aggregate" || fail "no aggregate hint: $OUT"

echo "property 4: an aggregate without an invariant is rejected (rule-not-aggregate)"
cat > "$D/no-inv.es" <<'EOF'
N u actor 利用者
N c command 文書を開く
N a aggregate ファイル読込検証 | evidence=x:1
N e event 文書が開かれた | evidence=x:1
E u issues c
E c handles a
E a emits e
EOF
run "$D/no-inv.es"
[ "$RC" -eq 1 ] && pass "invariant-less aggregate -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q '集約に不変条件がない: a' && pass "names the invariant-less aggregate" || fail "not named: $OUT"

echo "property 5: an event emitted by more than one aggregate is rejected"
cat > "$D/multi.es" <<'EOF'
N u actor 利用者
N c command 文書を開く
N a1 aggregate 集約1 | invariant=x | evidence=x:1
N a2 aggregate 集約2 | invariant=y | evidence=x:2
N e event 文書が開かれた | evidence=x:1
E u issues c
E c handles a1
E a1 emits e
E a2 emits e
EOF
run "$D/multi.es"
[ "$RC" -eq 1 ] && pass "multi-emitter event -> exit 1" || fail "expected 1, got $RC: $OUT"

echo "property 6: an edge referencing an undeclared node is rejected"
cat > "$D/undecl.es" <<'EOF'
N u actor 利用者
N c command 文書を開く
E u issues c
E c handles aMissing
EOF
run "$D/undecl.es"
[ "$RC" -eq 1 ] && pass "undeclared node -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'aMissing' && pass "names the undeclared node" || fail "not named: $OUT"

echo "property 7: an event without evidence warns but does NOT block (exit 0)"
cat > "$D/no-ev.es" <<'EOF'
N u actor 利用者
N c command 文書を開く
N a aggregate タブ集約 | invariant=タブ1以上
N e event タブが開かれた
E u issues c
E c handles a
E a emits e
EOF
run "$D/no-ev.es"
[ "$RC" -eq 0 ] && pass "evidence-less event -> exit 0 (advisory)" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q '証拠リンクなしイベント' && pass "warns about missing evidence" || fail "no warn: $OUT"

echo "property 8: a hotspot edge with a non-marks relation is rejected (vocabulary enforced)"
cat > "$D/hot-bad.es" <<'EOF'
N h hotspot 未決定論点
N a aggregate タブ集約 | invariant=タブ1以上 | evidence=x:1
N e event タブが開かれた | evidence=x:1
E h emits e
EOF
run "$D/hot-bad.es"
[ "$RC" -eq 1 ] && pass "hotspot with emits -> exit 1" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'hotspot のエッジは marks のみ' && pass "names the hotspot vocabulary violation" || fail "not named: $OUT"

echo "property 9: a hotspot edge using marks is accepted"
cat > "$D/hot-ok.es" <<'EOF'
N h hotspot 未決定論点
N a aggregate タブ集約 | invariant=タブ1以上 | evidence=x:1
N e event タブが開かれた | evidence=x:1
N u actor 利用者
N c command 開く
E u issues c
E c handles a
E a emits e
E h marks a
EOF
run "$D/hot-ok.es"
[ "$RC" -eq 0 ] && pass "hotspot with marks -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property: command -> external system is allowed (コマンドの次は集約か外部)"
cat > "$D/cmd-ext.es" <<'EOF'
N u actor 利用者
N c command 通知する
N x external 通知基盤
N e event 通知された
E u issues c
E c handles x
E x emits e
EOF
run "$D/cmd-ext.es"
[ "$RC" -eq 0 ] && pass "command->external -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "property: event -> actor is allowed (イベントの次はポリシーかアクター)"
cat > "$D/ev-actor.es" <<'EOF'
N u actor 利用者
N c command 開く
N a aggregate 集約 | invariant=x | evidence=x:1
N e event 開かれた | evidence=x:1
N r actor 受信者
E u issues c
E c handles a
E a emits e
E e triggers r
EOF
run "$D/ev-actor.es"
[ "$RC" -eq 0 ] && pass "event->actor -> exit 0" || fail "expected 0, got $RC: $OUT"

echo "---- test-es-lint: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
