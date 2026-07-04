#!/bin/sh
# tests/test-probe-gate-liveness.sh — core/scripts/probe-gate-liveness.sh の挙動テスト
#
# 文脈（ROADMAP P4・ハーネスの二階ループ）: 予防型ゲートは「発火ゼロが正常」なので、
# 効いているのか黙って壊れているのか外からは区別できない。合成違反を注入して
# ゲートが拒否するかを見る「生存証明」が要る（mutation testing と同型）。
#
# 検証する性質:
#   1. 実在の予防ゲートに合成違反を注入すると、ゲートは拒否する＝ALIVE（効いている）
#   2. 違反を見逃すゲート（常に成功）は DEAD と判定され exit 1（効いていないゲートの検出）
#   3. 既定モードは kit 自身の予防ゲートを probe し、全 ALIVE なら exit 0（自己 dogfood）
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PROBE="$ROOT/core/scripts/probe-gate-liveness.sh"
PASS=0
FAIL=0

fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }

# probe_one <gate_path> <kind> -> stdout を $OUT、終了コードを $RC に格納
probe_one() { OUT="$(sh "$PROBE" --one "$1" "$2" 2>&1)" && RC=0 || RC=$?; }

# ---- 性質1: 実在の予防ゲートは合成違反を拒否する（ALIVE） ----
echo "property 1: real prevention gates reject an injected violation -> ALIVE"
probe_one "$ROOT/core/scripts/check-conventional-title.sh" title
[ "$RC" -eq 0 ] && pass "title gate ALIVE" || fail "title gate not ALIVE (rc=$RC): $OUT"
printf '%s\n' "$OUT" | grep -q "ALIVE" && pass "reports ALIVE for title" || fail "no ALIVE for title gate"

probe_one "$ROOT/core/scripts/check-no-committed-secrets.sh" secrets
[ "$RC" -eq 0 ] && pass "secrets gate ALIVE" || fail "secrets gate not ALIVE (rc=$RC): $OUT"

probe_one "$ROOT/core/scripts/check-file-line-limit.sh" filesize
[ "$RC" -eq 0 ] && pass "filesize gate ALIVE" || fail "filesize gate not ALIVE (rc=$RC): $OUT"

# ---- 性質2: 違反を見逃すゲート（常に成功）は DEAD ----
echo "property 2: a gate that ignores violations is reported DEAD"
DUMMY_DIR="$(mktemp -d)"
DUMMY="$DUMMY_DIR/always-pass.sh"
printf '#!/bin/sh\nexit 0\n' > "$DUMMY"
probe_one "$DUMMY" title
[ "$RC" -eq 1 ] && pass "dead gate exit 1" || fail "expected exit 1 for dead gate, got $RC"
printf '%s\n' "$OUT" | grep -q "DEAD" && pass "reports DEAD for the silent gate" || fail "no DEAD report"
rm -rf "$DUMMY_DIR"

# ---- 性質3: 既定モードは kit 自身のゲートを probe -> 全 ALIVE で exit 0 ----
echo "property 3: default mode probes kit's own gates -> all ALIVE, exit 0"
OUT="$(sh "$PROBE" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "default mode exit 0" || fail "expected exit 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q "DEAD" && fail "a kit gate reported DEAD" || pass "no DEAD among kit gates"

# ---- 性質4: 消費者は harness.config.sh の PROBE_GATES で自分のゲートを probe できる ----
# 一時消費者リポ（消費モデル: probe を scripts/ にコピー）で、実ゲート(ALIVE)と
# 拒否経路が壊れたゲート(DEAD)を混在させ、PROBE_GATES が両者を正しく区別することを確認する。
echo "property 4: consumer PROBE_GATES drives the gate list (ALIVE/DEAD mix)"
C="$(mktemp -d)"
git -C "$C" init -q
mkdir -p "$C/scripts"
cp "$PROBE" "$C/scripts/probe-gate-liveness.sh"
cp "$ROOT/core/scripts/check-no-committed-secrets.sh" "$C/scripts/check-no-committed-secrets.sh"
# 壊れたゲート: 違反を受理してしまう（常に exit 0）= DEAD であるべき
printf '#!/bin/sh\nexit 0\n' > "$C/scripts/broken-secrets.sh"
printf 'PROBE_GATES="scripts/check-no-committed-secrets.sh:secrets scripts/broken-secrets.sh:secrets"\n' \
  > "$C/harness.config.sh"
OUT="$(sh "$C/scripts/probe-gate-liveness.sh" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "consumer probe exit 1 (a gate is DEAD)" || fail "expected exit 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q "ALIVE check-no-committed-secrets.sh" \
  && pass "real consumer gate ALIVE" || fail "real gate not ALIVE: $OUT"
printf '%s\n' "$OUT" | grep -q "DEAD  broken-secrets.sh" \
  && pass "broken consumer gate DEAD" || fail "broken gate not DEAD: $OUT"
rm -rf "$C"

# ---- 性質5: 不正な kind は偽 ALIVE にせず setup error(exit 2) ----
# PROBE_GATES の kind 打ち間違い（"secret"・コロン欠落等）でゲートを実際に試さず exit 0＝
# 偽の生存証明になる回帰を防ぐ。run_gate の非ゼロを一律 ALIVE と解釈しないこと。
echo "property 5: an invalid kind is a setup error (exit 2), never a false ALIVE"
probe_one "$ROOT/core/scripts/check-no-committed-secrets.sh" secret   # typo: should be 'secrets'
[ "$RC" -eq 2 ] && pass "invalid kind -> exit 2" || fail "expected exit 2 for bad kind, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q "ALIVE" && fail "bad kind wrongly reported ALIVE" || pass "no false ALIVE for bad kind"

# ---- 性質6: 決定論的 pre-loop triage（--repairable-only が escalation-only を除外） ----
# exp3 の構造的失敗（converge ループが human-owned ゲートに編集圧力をかける）を根絶する。
# escalation-only マーカー付きの DEAD ゲートは:
#   - 既定モード（生存証明）では DEAD として surface し exit 1（人間が気づける）
#   - --repairable-only（converge ビュー）では SKIP され probe されない＝健全ゲートだけで exit 0
echo "property 6: --repairable-only deterministically excludes escalation-only gates"
G="$(mktemp -d)"
git -C "$G" init -q
mkdir -p "$G/scripts"
cp "$PROBE" "$G/scripts/probe-gate-liveness.sh"
cp "$ROOT/core/scripts/check-no-committed-secrets.sh" "$G/scripts/check-no-committed-secrets.sh"  # 健全 ALIVE
# DEAD かつ escalation-only マーカー付きの governed ゲート（違反を受理する＝本来 DEAD）
printf '#!/bin/sh\n# gatecrate-scope: escalation-only\nexit 0\n' > "$G/scripts/governed-gate.sh"
printf 'PROBE_GATES="scripts/check-no-committed-secrets.sh:secrets scripts/governed-gate.sh:secrets"\n' \
  > "$G/harness.config.sh"
# 既定モード: governed は DEAD として surface -> exit 1
OUT="$(sh "$G/scripts/probe-gate-liveness.sh" 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "default mode surfaces governed DEAD (exit 1)" || fail "expected exit 1, got $RC: $OUT"
# --repairable-only: governed は SKIP -> 健全ゲートのみ -> exit 0
OUT="$(sh "$G/scripts/probe-gate-liveness.sh" --repairable-only 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "repairable-only excludes governed gate (exit 0)" || fail "expected exit 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q "SKIP  governed-gate.sh" && pass "governed gate reported SKIP" || fail "no SKIP for governed gate: $OUT"
printf '%s\n' "$OUT" | grep -q "DEAD" && fail "repairable-only still probed the governed gate" || pass "governed gate not probed under repairable-only"
rm -rf "$G"

# ---- 性質7: 設定駆動 hard-constraints ゲートを probe できる（注入種別の拡張） ----
# config-driven ゲートも生存証明の対象にする。消費者の hard-constraints.tsv の最初の forbid 規則から
# 違反を合成注入し、健全ゲートは ALIVE・壊れたゲートは DEAD・規則が無ければ setup error(ALIVE にしない)。
echo "property 7: config-driven hard-constraints gate is probeable (ALIVE / DEAD / no-rule setup error)"
H="$(mktemp -d)"; git -C "$H" init -q; mkdir -p "$H/scripts" "$H/src"
cp "$ROOT/core/scripts/check-hard-constraints.sh" "$H/scripts/check-hard-constraints.sh"
printf 'forbid\tsrc/*.java\tandroid.permission.INTERNET\tno internet permission\n' > "$H/hard-constraints.tsv"
printf 'class A {}\n' > "$H/src/A.java"; git -C "$H" add -A >/dev/null 2>&1
OUT="$(HARD_CONSTRAINTS_FILE="$H/hard-constraints.tsv" sh "$PROBE" --one "$H/scripts/check-hard-constraints.sh" hard-constraints 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "healthy hard-constraints gate ALIVE" || fail "expected ALIVE(0), got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'ALIVE' && pass "reports ALIVE" || fail "no ALIVE: $OUT"
printf '#!/bin/sh\nexit 0\n' > "$H/scripts/broken.sh"
OUT="$(HARD_CONSTRAINTS_FILE="$H/hard-constraints.tsv" sh "$PROBE" --one "$H/scripts/broken.sh" hard-constraints 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "broken gate DEAD (exit 1)" || fail "expected DEAD(1), got $RC: $OUT"
printf 'require\tsrc/L.java\tLicense\tlicense\n' > "$H/only-require.tsv"
OUT="$(HARD_CONSTRAINTS_FILE="$H/only-require.tsv" sh "$PROBE" --one "$H/scripts/check-hard-constraints.sh" hard-constraints 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 2 ] && pass "no forbid rule -> setup error (not a false ALIVE)" || fail "expected setup(2), got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'cannot prove liveness' && pass "reports cannot-prove-liveness" || fail "no setup notice: $OUT"
rm -rf "$H"

# ---- 性質8: 注入種別の拡張 — posix / escalation も生存証明できる ----
echo "property 8: posix and escalation reject-type gates are probeable -> ALIVE"
probe_one "$ROOT/core/scripts/check-posix-portability.sh" posix
[ "$RC" -eq 0 ] && pass "posix gate ALIVE" || fail "posix gate not ALIVE (rc=$RC): $OUT"
probe_one "$ROOT/core/scripts/check-mutation-escalation.sh" escalation
[ "$RC" -eq 0 ] && pass "escalation gate ALIVE" || fail "escalation gate not ALIVE (rc=$RC): $OUT"

# ---- 性質8b: git シナリオ/設定駆動の reject ゲートも生存証明できる（注入器の全域化） ----
echo "property 8b: scenario/config reject-type gates are probeable -> ALIVE"
for kv in "check-doc-currency.sh:doc-currency" "check-rule-doc-currency.sh:rule-doc" \
          "check-merge-integrity.sh:merge-integrity" "check-release-version-name.sh:release-version" \
          "check-third-party-notices.sh:third-party"; do
  probe_one "$ROOT/core/scripts/${kv%:*}" "${kv##*:}"
  [ "$RC" -eq 0 ] && pass "${kv##*:} gate ALIVE" || fail "${kv##*:} gate not ALIVE (rc=$RC): $OUT"
done

# ---- 性質9: --audit メタチェック — probe 可能な reject 型ゲートが PROBE_GATES 未登録なら fail ----
echo "property 9: --audit fails when a probeable reject-type gate is not registered, passes when it is"
A="$(mktemp -d)"; git -C "$A" init -q; mkdir -p "$A/scripts"
cp "$PROBE" "$A/scripts/probe-gate-liveness.sh"
cp "$ROOT/core/scripts/check-conventional-title.sh" "$ROOT/core/scripts/check-posix-portability.sh" "$A/scripts/"
# posix を登録し忘れ -> MISS で exit 1
OUT="$(cd "$A" && PROBE_GATES="scripts/check-conventional-title.sh:title" sh scripts/probe-gate-liveness.sh --audit 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 1 ] && pass "unregistered injectable gate -> audit fail (exit 1)" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'MISS  check-posix-portability.sh' && pass "names the unregistered gate" || fail "no MISS: $OUT"
# 全 injectable を登録 -> pass
OUT="$(cd "$A" && PROBE_GATES="scripts/check-conventional-title.sh:title scripts/check-posix-portability.sh:posix" sh scripts/probe-gate-liveness.sh --audit 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "all registered -> audit pass (exit 0)" || fail "expected 0, got $RC: $OUT"
rm -rf "$A"

# ---- 性質10: --list-reject-gates — 予防型(reject型)レジストリを単一ソースとして出力する ----
# classify-gate-type がこの一覧を予防型判定の単一ソースとして参照する（REJECT_GATES の二重定義=drift を防ぐ）。
echo "property 10: --list-reject-gates emits the prevention(reject-type) registry, one base per line"
OUT="$(sh "$PROBE" --list-reject-gates 2>&1)" && RC=0 || RC=$?
[ "$RC" -eq 0 ] && pass "--list-reject-gates exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qx 'check-conventional-title.sh' && pass "lists a known prevention gate (title)" || fail "title missing: $OUT"
printf '%s\n' "$OUT" | grep -qx 'check-posix-portability.sh' && pass "lists posix prevention gate" || fail "posix missing: $OUT"
printf '%s\n' "$OUT" | grep -qx 'measure-complexity.sh' && fail "must NOT list a non-reject measure gate" || pass "excludes non-reject measure gate"

echo ""
echo "probe-gate-liveness tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
