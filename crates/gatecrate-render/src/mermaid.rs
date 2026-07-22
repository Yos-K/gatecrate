//! モデル → Mermaid フローチャート。
//!
//! 座標は書かない（レイアウトは Mermaid に委ね、モデル更新で図が歪まないようにする）。

use gatecrate_model::cld::{CausalLoopDiagram, Polarity};
use gatecrate_model::cmap::{ContextKind, ContextMap};
use gatecrate_model::es::{CardKind, EventModel, Relation};
use std::fmt::Write as _;

/// Mermaid のラベルに入れられない二重引用符を除く。
fn label(text: &str) -> String {
    text.replace('"', "")
}

impl CardShape for CardKind {
    /// 付箋の種別 → Mermaid の箱の形。
    fn shape(self) -> (&'static str, &'static str) {
        match self {
            CardKind::Actor => ("([", "])"),
            CardKind::Command => ("[/", "/]"),
            CardKind::Aggregate => ("{{", "}}"),
            CardKind::Policy => ("[[", "]]"),
            CardKind::ReadModel => ("(", ")"),
            CardKind::External => (">", "]"),
            CardKind::Event | CardKind::ErrorEvent | CardKind::Hotspot => ("[", "]"),
        }
    }
}

trait CardShape {
    fn shape(self) -> (&'static str, &'static str);
}

const ES_CLASSES: &str = "    classDef actor fill:#FFE8CC,stroke:#D9480F,color:#000
    classDef command fill:#4DABF7,stroke:#1971C2,color:#000
    classDef aggregate fill:#FFE066,stroke:#F08C00,color:#000
    classDef event fill:#FFA94D,stroke:#E8590C,color:#000
    classDef errorevent fill:#FFA8A8,stroke:#E03131,color:#000
    classDef policy fill:#DA77F2,stroke:#9C36B5,color:#fff
    classDef readmodel fill:#B2F2BB,stroke:#2F9E44,color:#000
    classDef external fill:#FFD8A8,stroke:#D9480F,color:#000
    classDef hotspot fill:#FF6B6B,stroke:#C92A2A,color:#fff
";

pub fn event_model(model: &EventModel) -> String {
    let mut out = String::from("flowchart LR\n");
    out.push_str(ES_CLASSES);
    for card in &model.cards {
        let (open, close) = card.kind.shape();
        let _ = writeln!(
            out,
            "    {}{open}\"{}\"{close}:::{}",
            card.id,
            label(&card.label),
            card.kind.name()
        );
    }
    for c in &model.connections {
        let arrow = match c.relation {
            // 論点マーク・参照供給は点線で「本流でない」ことを示す
            Relation::Marks => "-.->|?|".to_string(),
            Relation::Feeds => "-.->|feeds|".to_string(),
            _ => format!("-->|\"{}\"|", edge_label(c.relation, c.when.as_deref())),
        };
        let _ = writeln!(out, "    {} {arrow} {}", c.from, c.to);
    }
    for card in &model.cards {
        let _ = writeln!(out, "    click {} esNode", card.id);
    }
    out
}

/// 矢印のラベル。発火条件があれば「〜のとき」、なければ関係動詞。
fn edge_label(relation: Relation, when: Option<&str>) -> String {
    match when {
        Some(guard) if !guard.is_empty() => {
            format!("{}のとき", guard.replace(['"', '[', ']'], ""))
        }
        _ => relation.name().to_string(),
    }
}

const CMAP_CLASSES: &str = "    classDef bc fill:#D0EBFF,stroke:#1971C2,color:#0d47a1
    classDef ext fill:#F1F3F5,stroke:#868E96,color:#343a40,stroke-dasharray:4 3
";

pub fn context_map(map: &ContextMap) -> String {
    let mut out = String::from("flowchart LR\n");
    out.push_str(CMAP_CLASSES);
    for ctx in &map.contexts {
        let (open, close) = match ctx.kind {
            ContextKind::Bounded => ("[", "]"),
            ContextKind::External => (">", "]"),
        };
        let _ = writeln!(
            out,
            "    {}{open}\"{}\"{close}:::{}",
            ctx.id,
            label(&ctx.label),
            ctx.kind.name()
        );
    }
    for rel in &map.relations {
        let text = if rel.key.is_empty() {
            rel.pattern.clone()
        } else {
            format!("{} 〔{}〕", rel.pattern, rel.key)
        };
        let _ = writeln!(out, "    {} -->|\"{}\"| {}", rel.from, label(&text), rel.to);
    }
    for ctx in &map.contexts {
        let _ = writeln!(out, "    click {} esNode", ctx.id);
    }
    out
}

pub fn causal_loops(diagram: &CausalLoopDiagram) -> String {
    let mut out = String::from("flowchart LR\n");
    out.push_str("    classDef v fill:#E7F5FF,stroke:#1971C2,color:#0d3b66\n");
    for v in &diagram.variables {
        let _ = writeln!(out, "    {}((\"{}\")):::v", v.id, label(&v.label));
    }
    for link in &diagram.links {
        let arrow = match link.polarity {
            Polarity::Same => "-->|\"＋\"|",
            Polarity::Opposite => "-.->|\"－\"|",
        };
        let _ = writeln!(out, "    {} {arrow} {}", link.from, link.to);
    }
    out
}
