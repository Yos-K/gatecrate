//! 自己完結ビューア（1枚 HTML）の組み立て。
//!
//! 入力の有無でタブとビューが増減する。静的な CSS/ヘルプ/JS は assets/ に置き、
//! ここは「どの部品をどの順で並べるか」だけを持つ。

use crate::{data, markdown, mermaid};
use gatecrate_model::cld::CausalLoopDiagram;
use gatecrate_model::cmap::ContextMap;
use gatecrate_model::es::EventModel;
use gatecrate_model::spec::CommandSpecs;

const HEAD: &str = include_str!("../assets/head.html");
const HELP: &str = include_str!("../assets/help.html");
const MID: &str = include_str!("../assets/mid.html");
const TAIL: &str = include_str!("../assets/tail.html");

/// ビューア1枚に載せる素材一式。
#[derive(Default)]
pub struct Materials {
    pub asis: EventModel,
    pub asis_spec: CommandSpecs,
    pub tobe: Option<EventModel>,
    pub tobe_spec: CommandSpecs,
    pub context_map: Option<ContextMap>,
    pub causal_loops: Option<CausalLoopDiagram>,
    /// 分析レポート（Markdown 原文・表示順）。
    pub analyses: Vec<String>,
}

impl Materials {
    fn has_tabs(&self) -> bool {
        self.tobe.is_some() || self.context_map.is_some() || !self.analyses.is_empty()
    }
}

pub fn render(m: &Materials) -> String {
    let mut page = String::with_capacity(96 * 1024);
    page.push_str(HEAD);
    push_toolbar(&mut page, m);
    page.push_str(HELP);
    push_views(&mut page, m);
    push_embedded_data(&mut page, m);
    page.push_str(TAIL);
    page
}

fn push_toolbar(page: &mut String, m: &Materials) {
    if m.has_tabs() {
        page.push_str(r#"    <button id="tab_asis" class="tab on" onclick="setView('asis')">AS-IS（現状＝コードの流れ）</button>"#);
        if m.tobe.is_some() {
            page.push_str(r#"<button id="tab_tobe" class="tab" onclick="setView('tobe')">TO-BE（あるべき）</button>"#);
        }
        if m.context_map.is_some() {
            page.push_str(r#"<button id="tab_cmap" class="tab" onclick="setView('cmap')">コンテキストマップ</button>"#);
        }
        page.push_str(r#"<button id="tab_glossary" class="tab" onclick="setView('glossary')">用語集</button>"#);
        if m.tobe.is_some() {
            page.push_str(r#"<button id="tab_biz" class="tab" onclick="setView('biz')">ビジネス分析</button>"#);
        }
        if !m.analyses.is_empty() {
            page.push_str(r#"<button id="tab_analysis" class="tab" onclick="setView('analysis')">分析レポート</button>"#);
        }
        page.push_str("<span class=\"sep\"></span>\n");
    }
    page.push_str("    <button class=\"help-btn\" onclick=\"toggleHelp(1)\">❓ このページの見方</button><button onclick=\"esZoom(1.2)\">＋ 拡大</button><button onclick=\"esZoom(1/1.2)\">－ 縮小</button><button onclick=\"esFit()\">全体表示</button><span class=\"muted\">Ctrl+ホイール / ピンチ=拡大縮小 ・ ホイール / スワイプ / ドラッグ=移動</span>\n");
    page.push_str("  </div>\n");
}

fn push_views(page: &mut String, m: &Materials) {
    push_diagram_view(page, "asis", &mermaid::event_model(&m.asis));
    if let Some(tobe) = &m.tobe {
        push_diagram_view(page, "tobe", &mermaid::event_model(tobe));
    }
    if let Some(map) = &m.context_map {
        push_diagram_view(page, "cmap", &mermaid::context_map(map));
    }
    // 用語集はモデルから JS が射影する（常設）
    page.push_str("  <div class=\"view\" id=\"view_glossary\"><div class=\"report\" id=\"glossary_report\"></div></div>\n");
    if m.tobe.is_some() {
        push_business_view(page, m.causal_loops.as_ref());
    }
    if !m.analyses.is_empty() {
        page.push_str("  <div class=\"view\" id=\"view_analysis\"><div class=\"report analysis\">\n");
        for doc in &m.analyses {
            page.push_str("<article class=\"doc\">\n");
            page.push_str(&markdown::to_html(doc));
            page.push_str("</article>\n");
        }
        page.push_str("  </div></div>\n");
    }
}

fn push_diagram_view(page: &mut String, name: &str, diagram: &str) {
    page.push_str(&format!(
        "  <div class=\"view\" id=\"view_{name}\"><div class=\"vp\" id=\"vp_{name}\"><div class=\"stage\" id=\"st_{name}\"><pre class=\"mermaid\">\n"
    ));
    page.push_str(diagram);
    page.push_str("</pre></div></div></div>\n");
}

fn push_business_view(page: &mut String, loops: Option<&CausalLoopDiagram>) {
    page.push_str("  <div class=\"view\" id=\"view_biz\"><div class=\"report\">\n");
    page.push_str("    <div id=\"biz_top\"></div>\n");
    if let Some(diagram) = loops {
        page.push_str("    <h3>システム思考：因果ループ図（＋=同方向 / －=逆方向、強化ループ R とバランスループ B）</h3>\n");
        page.push_str("    <div class=\"cldwrap\"><pre class=\"mermaid\">\n");
        page.push_str(&mermaid::causal_loops(diagram));
        page.push_str("</pre></div>\n");
    }
    page.push_str("    <div id=\"biz_loops\"></div>\n");
    page.push_str("  </div></div>\n");
}

fn push_embedded_data(page: &mut String, m: &Materials) {
    page.push_str(MID); // ここまでで `MODELS.asis=` の行が開いている
    page.push_str(&data::event_model(&m.asis, &m.asis_spec));
    page.push_str(";\n");
    if let Some(tobe) = &m.tobe {
        page.push_str("MODELS.tobe=\n");
        page.push_str(&data::event_model(tobe, &m.tobe_spec));
        page.push_str(";\n");
    }
    if let Some(map) = &m.context_map {
        page.push_str("MODELS.cmap=\n");
        page.push_str(&data::context_map(map));
        page.push_str(";\n");
    }
    page.push_str("var CLD_LOOPS=");
    match &m.causal_loops {
        Some(diagram) => page.push_str(&data::causal_loops(diagram)),
        None => page.push_str("[]"),
    }
    page.push_str(";\n");
}
