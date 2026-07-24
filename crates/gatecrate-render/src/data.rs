//! モデル → ビューア内蔵データ（JS オブジェクトリテラル）。
//!
//! ビューア（assets/tail.html の JS）が読むデータ契約。キーの語彙と並びはビューア側の
//! 参照コードで決まっているので、ここが唯一の生成箇所として契約を持つ。

use gatecrate_model::cld::CausalLoopDiagram;
use gatecrate_model::cmap::{ContextMap, ContextRelation};
use gatecrate_model::es::{Card, Connection, EventModel};
use gatecrate_model::spec::CommandSpecs;
use std::fmt::Write as _;

/// JS 文字列リテラル用。バックスラッシュは落とし、二重引用符をエスケープする。
fn js(text: &str) -> String {
    text.replace('\\', "").replace('"', "\\\"")
}

/// カード属性 → ビューアのデータキー（この並びが契約）。
const VIEWER_KEYS: [(&str, &str); 21] = [
    ("invariant", "invariant"),
    ("evidence", "evidence"),
    ("fields", "fields"),
    ("states", "states"),
    ("transitions", "transitions"),
    ("in", "bin"),
    ("out", "bout"),
    ("decide", "decide"),
    ("behaviors", "behaviors"),
    ("note", "note"),
    ("role", "role"),
    ("discuss", "discuss"),
    ("biz", "biz"),
    ("measure", "measure"),
    ("capture", "capture"),
    ("compute", "compute"),
    ("becomes", "becomes"),
    ("is", "is"),
    ("kind-of", "kindof"),
    ("role-of", "roleof"),
    ("alias", "alias"),
];

pub fn event_model(model: &EventModel, specs: &CommandSpecs) -> String {
    let mut out = String::from("{\n");
    let last = model.cards.len().saturating_sub(1);
    for (index, card) in model.cards.iter().enumerate() {
        write_card(&mut out, card, model, specs);
        if index != last {
            out.push(',');
        }
        out.push('\n');
    }
    out.push_str("}\n");
    out
}

fn write_card(out: &mut String, card: &Card, model: &EventModel, specs: &CommandSpecs) {
    let _ = write!(
        out,
        "  \"{}\":{{\"type\":\"{}\",\"label\":\"{}\"",
        card.id,
        card.kind.name(),
        js(&card.label)
    );
    for (attribute, key) in VIEWER_KEYS {
        let _ = write!(out, ",\"{key}\":\"{}\"", js(card.attribute(attribute)));
    }

    out.push_str(",\"out\":[");
    write_connections(out, model.outgoing(&card.id), ConnectionEnd::To);
    out.push_str("],\"in\":[");
    write_connections(out, model.incoming(&card.id), ConnectionEnd::From);

    out.push_str("],\"spec\":{\"in\":[");
    let spec = specs.of(&card.id);
    let empty: &[String] = &[];
    for (i, input) in spec.map_or(empty, |s| &s.inputs).iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let _ = write!(out, "\"{}\"", js(input));
    }
    out.push_str("],\"steps\":[");
    for (i, step) in spec.map_or(&[][..], |s| &s.steps).iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let _ = write!(
            out,
            "{{\"label\":\"{}\",\"rule\":\"{}\"}}",
            js(&step.label),
            js(&step.rule)
        );
    }
    out.push_str("],\"out\":[");
    for (i, output) in spec.map_or(empty, |s| &s.outputs).iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let _ = write!(out, "\"{}\"", js(output));
    }
    out.push_str("]}}");
}

enum ConnectionEnd {
    To,
    From,
}

fn write_connections<'a>(
    out: &mut String,
    connections: impl Iterator<Item = &'a Connection>,
    end: ConnectionEnd,
) {
    for (i, c) in connections.enumerate() {
        if i > 0 {
            out.push(',');
        }
        let (key, id) = match end {
            ConnectionEnd::To => ("to", &c.to),
            ConnectionEnd::From => ("from", &c.from),
        };
        let _ = write!(
            out,
            "{{\"rel\":\"{}\",\"{key}\":\"{id}\",\"when\":\"{}\"}}",
            c.relation.name(),
            js(c.when.as_deref().unwrap_or(""))
        );
    }
}

pub fn context_map(map: &ContextMap) -> String {
    let mut out = String::from("{\n");
    let last = map.contexts.len().saturating_sub(1);
    for (index, ctx) in map.contexts.iter().enumerate() {
        let _ = write!(
            out,
            "  \"{}\":{{\"type\":\"{}\",\"label\":\"{}\",\"summary\":\"{}\",\"repos\":\"{}\",\"discuss\":\"{}\",\"aggregates\":\"{}\",\"kind\":\"{}\",\"out\":[",
            ctx.id,
            ctx.kind.name(),
            js(&ctx.label),
            js(&ctx.summary),
            js(&ctx.repos),
            js(&ctx.discuss),
            js(&ctx.aggregates),
            js(&ctx.domain_kind),
        );
        write_relations(&mut out, map.supplying(&ctx.id), RelationEnd::To);
        out.push_str("],\"in\":[");
        write_relations(&mut out, map.supplied(&ctx.id), RelationEnd::From);
        out.push_str("]}");
        if index != last {
            out.push(',');
        }
        out.push('\n');
    }
    out.push_str("}\n");
    out
}

enum RelationEnd {
    To,
    From,
}

fn write_relations<'a>(
    out: &mut String,
    relations: impl Iterator<Item = &'a ContextRelation>,
    end: RelationEnd,
) {
    for (i, r) in relations.enumerate() {
        if i > 0 {
            out.push(',');
        }
        let (key, id) = match end {
            RelationEnd::To => ("to", &r.to),
            RelationEnd::From => ("from", &r.from),
        };
        let _ = write!(
            out,
            "{{\"rel\":\"{}\",\"{key}\":\"{id}\",\"key\":\"{}\",\"reason\":\"{}\"}}",
            r.pattern,
            js(&r.key),
            js(&r.reason)
        );
    }
}

/// ループ凡例。1行の JS 配列（`var CLD_LOOPS=` の右辺）。
pub fn causal_loops(diagram: &CausalLoopDiagram) -> String {
    let mut out = String::from("[");
    for (i, l) in diagram.loops.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let _ = write!(
            out,
            "{{\"id\":\"{}\",\"kind\":\"{}\",\"vars\":\"{}\",\"desc\":\"{}\"}}",
            l.id,
            l.kind.name(),
            js(&l.variables),
            js(&l.description)
        );
    }
    out.push(']');
    out
}
