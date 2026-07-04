#!/bin/sh
# tests/test-es-render-html.sh — core/scripts/es-render-html.sh のスモークテスト
#
# 文脈: es-render-html は .es(+spec/cmap) を自己完結HTMLへ決定論射影する道具。出力が壊れる（Mermaid構文・
# JS構文・タブ欠落）と人もAIも読めない。本テストは「単一モデルで妥当なHTML構造を出す／AS-IS+TO-BE+cmapで
# 3タブ・3モデルが揃う／生成JSが構文的に妥当（node があれば）」をスモークで固定する。
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT="$ROOT/core/scripts/es-render-html.sh"
PASS=0; FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT

cat > "$D/asis.es" <<'EOF'
N u actor 利用者
N c command 文書を開く | in=id | out=開く|失敗 | decide="idが有効なら開く" | becomes=c | R4: 受付に純化
N a aggregate タブ集約 | fields=id:数値; 状態:[開|閉] | invariant=id一意
N e event 文書が開かれた | fields=id:数値
N h hotspot 同一性は要確認 | discuss=決めること:idの採番が他系と同一か / 決裁者:基盤
E u issues c
E c handles a
E a emits e
E h marks a
EOF
cat > "$D/tobe.es" <<'EOF'
N u actor 利用者
N c command 文書を開く | in=id | out=開く|失敗 | decide="idが有効なら開く"
N a aggregate タブ集約 | fields=id:数値 | states=閉 // 文書を読めない待機の局面|開 // 文書を読める局面 | transitions=開く:閉->開 // 文書を読める状態にする; 閉じる:開->閉 // 読み終えて手放す | invariant=id一意
N e event 文書が開かれた | fields=id:数値 | biz=value;revenue | measure=開封率・レイテンシ | capture=開封イベントでログ出力 | compute=開封率=count(開封)/count(要求)
N ef event 開封に失敗した | fields=id:数値 | biz=degrade | measure=失敗率
E u issues c
E c handles a
E a emits e
E a emits ef
EOF
cat > "$D/m.cmap" <<'EOF'
BC bc_a 閲覧BC | kind=core | aggregates=タブ集約 | summary=文書閲覧
EXT ext_x ストレージ | summary=保存先
REL bc_a Conformist ext_x | key=id | reason=保存形式に順応
EOF
cat > "$D/m.cld" <<'EOF'
V demand 要求数
V success 成功数
V failure 失敗数
L demand success +
L success demand +
L demand failure +
L failure success -
LOOP R1 R demand,success 成長
LOOP B1 B demand,failure,success 抑制
EOF
cat > "$D/analysis.md" <<'EOF'
# 設計分析レポート

## 整合性

本文は**強整合**と`結果整合`を区別する。

| データ | 整合性 |
|---|---|
| 決済 | 強整合 |
| 通知 | 結果整合 |

- 箇条書き1
- 箇条書き2
EOF

echo "property 1: single .es -> valid HTML skeleton"
H="$(sh "$SCRIPT" "$D/asis.es")"
printf '%s' "$H" | grep -q '<!DOCTYPE html>' && pass "has doctype" || fail "no doctype"
printf '%s' "$H" | grep -q 'class="mermaid"' && pass "has mermaid block" || fail "no mermaid"
printf '%s' "$H" | grep -q 'MODELS.asis=' && pass "embeds MODELS.asis" || fail "no asis model"
printf '%s' "$H" | grep -q 'flowchart LR' && pass "has flowchart" || fail "no flowchart"
printf '%s' "$H" | grep -q 'このページの見方' && pass "has help guide button" || fail "no help button"
printf '%s' "$H" | grep -q 'イベントストーミングとは' && pass "help explains event storming" || fail "no ES explanation"
printf '%s' "$H" | grep -q 'コンテキストマップとは' && pass "help explains context map" || fail "no cmap explanation"

echo "property 2: asis + tobe + cmap -> 3 tabs / 3 models"
H3="$(sh "$SCRIPT" "$D/asis.es" "$D/tobe.es" "$D/m.cmap")"
printf '%s' "$H3" | grep -q 'tab_tobe' && pass "has TO-BE tab" || fail "no tobe tab"
printf '%s' "$H3" | grep -q 'tab_cmap' && pass "has context-map tab" || fail "no cmap tab"
printf '%s' "$H3" | grep -q 'MODELS.cmap=' && pass "embeds MODELS.cmap" || fail "no cmap model"
printf '%s' "$H3" | grep -q 'view_cmap' && pass "has cmap view" || fail "no cmap view"

echo "property 2a2: glossary tab — ubiquitous language projected from .es"
printf '%s' "$H3" | grep -q 'tab_glossary' && pass "has glossary tab" || fail "no glossary tab"
printf '%s' "$H3" | grep -q 'view_glossary' && pass "has glossary view" || fail "no glossary view"
printf '%s' "$H3" | grep -q 'buildGlossary' && pass "has glossary projector" || fail "no buildGlossary"

echo "property 2a4: dictionary cards — verbs unfold the implicit state partition (from transitions=)"
printf '%s' "$H3" | grep -q 'function dictCards' && pass "has dictCards projector" || fail "no dictCards"
printf '%s' "$H3" | grep -q '受け付ける' && pass "renders acceptance panel (✓)" || fail "no acceptance panel"
printf '%s' "$H3" | grep -q '二重' && pass "derives double-execution guard (✗ reason)" || fail "no ✗ reason"
printf '%s' "$H3" | grep -q '前提「' && pass "shows capability supply chain" || fail "no supply chain"
printf '%s' "$H3" | grep -qF '文書を読める状態にする' && pass "embeds verb domain meaning" || fail "verb meaning missing"
printf '%s' "$H3" | grep -qF '文書を読めない待機の局面' && pass "embeds state domain meaning" || fail "state meaning missing"
printf '%s' "$H3" | grep -q 'ドメイン上の意味' && pass "renders meaning block" || fail "no meaning block"

echo "property 2a3: AS-IS→TO-BE change mapping (becomes=) with cross-tab jump"
printf '%s' "$H3" | grep -q '"becomes":"c | R4' && pass "embeds becomes mapping" || fail "no becomes in model"
printf '%s' "$H3" | grep -q 'gotoCross' && pass "has cross-tab jump" || fail "no gotoCross"
printf '%s' "$H3" | grep -q 'changeBlock' && pass "has change block renderer" || fail "no changeBlock"
printf '%s' "$H3" | grep -q 'TO-BEでの変化' && pass "renders change heading" || fail "no change heading"

echo "property 2b: business analysis tab — classification (biz=) and measure are embedded"
printf '%s' "$H3" | grep -q 'tab_biz' && pass "has business tab" || fail "no biz tab"
printf '%s' "$H3" | grep -q 'view_biz' && pass "has business view" || fail "no biz view"
printf '%s' "$H3" | grep -q 'buildBizReport' && pass "has biz report builder" || fail "no buildBizReport"
printf '%s' "$H3" | grep -q '"biz":"value;revenue"' && pass "embeds biz classification" || fail "no biz class in model"
printf '%s' "$H3" | grep -q 'upstreamEvents' && pass "has systems-thinking funnel tracer" || fail "no funnel tracer"

echo "property 2c: observability — capture(取得)/compute(計算) and obs table builder"
printf '%s' "$H3" | grep -q '"capture":"開封イベント' && pass "embeds capture(取得方法)" || fail "no capture in model"
printf '%s' "$H3" | grep -q 'table class=\\"obs\\"' && pass "has observability table builder" || fail "no obs table"

echo "property 2d: systems-thinking causal loop diagram (.cld) — reinforcing/balancing loops"
H4="$(sh "$SCRIPT" "$D/asis.es" "$D/tobe.es" "$D/m.cmap" "$D/m.cld")"
printf '%s' "$H4" | grep -q 'CLD_LOOPS=\[' && pass "embeds CLD_LOOPS" || fail "no CLD_LOOPS"
printf '%s' "$H4" | grep -q '"kind":"R"' && pass "has reinforcing loop (R)" || fail "no R loop"
printf '%s' "$H4" | grep -q '"kind":"B"' && pass "has balancing loop (B)" || fail "no B loop"
printf '%s' "$H4" | grep -q 'classDef v fill' && pass "renders CLD diagram" || fail "no CLD diagram"
printf '%s' "$H4" | grep -q 'cldwrap' && pass "has CLD wrapper" || fail "no cldwrap"

echo "property 2e: analysis report tab (.md) — deterministic markdown→HTML projection"
H5="$(sh "$SCRIPT" "$D/asis.es" "$D/tobe.es" "$D/m.cmap" "$D/m.cld" "$D/analysis.md")"
printf '%s' "$H5" | grep -q 'tab_analysis' && pass "has analysis tab" || fail "no analysis tab"
printf '%s' "$H5" | grep -q 'id="view_analysis"' && pass "has analysis view" || fail "no analysis view"
printf '%s' "$H5" | grep -q '<h1>設計分析レポート</h1>' && pass "renders md headers" || fail "no md header"
printf '%s' "$H5" | grep -q '<b>強整合</b>' && pass "renders md bold" || fail "no md bold"
printf '%s' "$H5" | grep -q '<table>' && pass "renders md table" || fail "no md table"
T="$(printf '%s' "$H5" | awk '/id="view_analysis"/{f=1} f&&/var MODELS/{exit} f' | grep -c '<table>')"
TC="$(printf '%s' "$H5" | awk '/id="view_analysis"/{f=1} f&&/var MODELS/{exit} f' | grep -c '</table>')"
[ "$T" = "$TC" ] && pass "md tables are balanced ($T)" || fail "table tags unbalanced: $T vs $TC"

echo "property 3: generated plain JS is syntactically valid (node があればチェック)"
if command -v node >/dev/null 2>&1; then
  printf '%s' "$H4" | awk 'BEGIN{p=0} /<script>/{p=1;next} /<\/script>/{p=0} p' > "$D/js.js"
  node --check "$D/js.js" && pass "plain JS parses (node --check)" || fail "JS syntax error"
else
  pass "node not present -> skipped JS check"
fi

echo "---- es-render-html: PASS=$PASS FAIL=$FAIL ----"
[ "$FAIL" -eq 0 ]
