#!/bin/sh
# tests/test-check-hard-constraints.sh — core/scripts/check-hard-constraints.sh の挙動テスト
#
# 文脈（意図の境界の機械強制）: プロダクトの破ってはいけない不変条件を設定駆動(TSV)で固定するゲート。
# git ls-files でパススペックを解決するので一時 git リポで決定論に検証する。
#
# 検証する性質:
#   1. forbid: マッチ在り -> 違反(exit 1)・該当ファイルを列挙
#   2. forbid: マッチ無し -> ok(exit 0)
#   3. require: 在り -> ok / 無し -> 違反
#   4. mode=nows: 複数行/整形ゆれのパターンを空白除去で捕捉（localmd の JS 無効化チェック相当）
#   5. require のリテラル必須ファイル欠落 -> 違反（glob 0件は vacuous pass）
#   6. 制約ファイル不在 -> skip(exit 0)
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/check-hard-constraints.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
TAB="$(printf '\t')"

new_repo() { W="$(mktemp -d)"; git -C "$W" init -q; mkdir -p "$W/scripts"; cp "$SCRIPT" "$W/scripts/check-hard-constraints.sh"; echo "$W"; }
add() { mkdir -p "$W/$(dirname "$1")"; printf '%s' "$2" > "$W/$1"; git -C "$W" add "$1" >/dev/null 2>&1 || true; }
con() { printf '%s\n' "$1" > "$W/hard-constraints.tsv"; }
run() { OUT="$(cd "$W" && sh scripts/check-hard-constraints.sh 2>&1)" && RC=0 || RC=$?; }

echo "property 1/2: forbid pattern present -> FAIL; absent -> ok"
W=$(new_repo)
add src/App.java 'class App {}'
con "forbid${TAB}src/App.java${TAB}INTERNET${TAB}no internet permission"
run; [ "$RC" -eq 0 ] && pass "forbid absent -> ok" || fail "expected 0, got $RC: $OUT"
add src/App.java 'class App { String x = "android.permission.INTERNET"; }'; git -C "$W" add -A >/dev/null
run; [ "$RC" -eq 1 ] && pass "forbid present -> FAIL" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'src/App.java' && pass "names the offending file" || fail "file not named: $OUT"
rm -rf "$W"

echo "property 3: require present -> ok; absent -> FAIL"
W=$(new_repo)
add src/L.java 'class L {}'
con "require${TAB}src/L.java${TAB}Apache License${TAB}license header required"
run; [ "$RC" -eq 1 ] && pass "require absent -> FAIL" || fail "expected 1, got $RC: $OUT"
add src/L.java '// Apache License 2.0
class L {}'; git -C "$W" add -A >/dev/null
run; [ "$RC" -eq 0 ] && pass "require present -> ok" || fail "expected 0, got $RC: $OUT"
rm -rf "$W"

echo "property 4: mode=nows catches a multi-line / reformatted match (localmd JS case)"
W=$(new_repo)
add src/MainActivity.java 'settings
  .setJavaScriptEnabled(
     true
  );'
con "forbid${TAB}src/MainActivity.java${TAB}setJavaScriptEnabled\(true\)${TAB}reader WebView must keep JS off${TAB}nows"
run; [ "$RC" -eq 1 ] && pass "nows catches split-across-lines match" || fail "expected 1, got $RC: $OUT"
# raw モードなら同じパターンは（改行で分断され）捕捉できない＝nows の必要性を示す
con "forbid${TAB}src/MainActivity.java${TAB}setJavaScriptEnabled\(true\)${TAB}reader WebView must keep JS off"
run; [ "$RC" -eq 0 ] && pass "raw mode misses the split match (so nows is needed)" || fail "raw unexpectedly matched: $OUT"
rm -rf "$W"

echo "property 5: require literal file missing -> FAIL; glob 0-match -> vacuous pass"
W=$(new_repo); add placeholder.txt x
con "require${TAB}src/main/AndroidManifest.xml${TAB}<application${TAB}manifest required"
run; [ "$RC" -eq 1 ] && pass "missing literal required file -> FAIL" || fail "expected 1, got $RC: $OUT"
con "require${TAB}*.kt${TAB}package ${TAB}every kt has a package"
run; [ "$RC" -eq 0 ] && pass "glob with 0 matches -> vacuous pass" || fail "expected 0, got $RC: $OUT"
rm -rf "$W"

echo "property 6: missing constraints file -> skip (exit 0)"
W=$(new_repo); add a.txt x
run; [ "$RC" -eq 0 ] && pass "no constraints file -> exit 0" || fail "expected 0, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -qi 'nothing configured' && pass "reports skip" || fail "no skip notice: $OUT"
rm -rf "$W"

echo "property 7: multiple lanes, only the violated one is reported (forbid across a glob)"
W=$(new_repo)
add src/A.java 'ok'
add src/B.java 'has TODO marker'
con "forbid${TAB}*.java${TAB}TODO${TAB}no TODO left in sources"
run; [ "$RC" -eq 1 ] && pass "glob forbid finds the one bad file" || fail "expected 1, got $RC: $OUT"
printf '%s\n' "$OUT" | grep -q 'src/B.java' && pass "names B.java" || fail "B not named: $OUT"
printf '%s\n' "$OUT" | grep -q 'src/A.java' && fail "A wrongly flagged: $OUT" || pass "clean A not flagged"
rm -rf "$W"

echo "property 8: guard column makes a constraint conditional (third-party notices pattern)"
# vendored 依存が在るときだけ帰属表示を require。guard が在れば適用、無ければスキップ。
W=$(new_repo)
con "require${TAB}THIRD_PARTY_NOTICES.md${TAB}Mermaid${TAB}vendored mermaid must be attributed${TAB}raw${TAB}src/main/assets/mermaid.min.js"
# 依存(guard)が無い -> 制約スキップ -> ok（帰属ファイルが無くても落ちない）
run; [ "$RC" -eq 0 ] && pass "guard absent -> constraint skipped (ok)" || fail "expected 0, got $RC: $OUT"
# 依存(guard)を入れる -> 制約適用 -> 帰属が無いので FAIL
add src/main/assets/mermaid.min.js 'mermaid();'; git -C "$W" add -A >/dev/null
run; [ "$RC" -eq 1 ] && pass "guard present -> require applies, attribution missing -> FAIL" || fail "expected 1, got $RC: $OUT"
# 帰属を入れる -> ok
add THIRD_PARTY_NOTICES.md 'Mermaid 11 MIT'; git -C "$W" add -A >/dev/null
run; [ "$RC" -eq 0 ] && pass "guard present + attribution present -> ok" || fail "expected 0, got $RC: $OUT"
rm -rf "$W"

echo ""
echo "check-hard-constraints tests: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] || exit 1
