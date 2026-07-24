//! `.cmap` — 横断コンテキストマップ。
//!
//! 境界づけられたコンテキスト（BC）・外部システム（EXT）と、両者の関係（REL）。

use crate::record::{parse, records};

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ContextKind {
    /// 自分たちのモデルが通用する境界。
    Bounded,
    /// 境界の外の権威。順応するか、腐敗防止層で隔てる相手。
    External,
}

impl ContextKind {
    pub fn name(self) -> &'static str {
        match self {
            Self::Bounded => "bc",
            Self::External => "ext",
        }
    }
}

pub struct Context {
    pub id: String,
    pub kind: ContextKind,
    pub label: String,
    pub summary: String,
    pub repos: String,
    pub discuss: String,
    pub aggregates: String,
    /// core / supporting / generic のドメイン種別。
    pub domain_kind: String,
}

pub struct ContextRelation {
    pub from: String,
    /// CS / Conformist / ACL / SharedKernel / PL などの統合パターン名。
    pub pattern: String,
    pub to: String,
    /// 2つの文脈を突き合わせる連結キー。
    pub key: String,
    pub reason: String,
}

#[derive(Default)]
pub struct ContextMap {
    pub contexts: Vec<Context>,
    pub relations: Vec<ContextRelation>,
}

impl ContextMap {
    pub fn parse(source: &str) -> Self {
        let mut map = Self::default();
        for line in records(source) {
            if let Some(r) = parse(line, "BC", 1) {
                map.contexts.push(context_of(&r, ContextKind::Bounded));
            } else if let Some(r) = parse(line, "EXT", 1) {
                map.contexts.push(context_of(&r, ContextKind::External));
            } else if let Some(r) = parse(line, "REL", 3) {
                map.relations.push(ContextRelation {
                    from: r.words[0].to_string(),
                    pattern: r.words[1].to_string(),
                    to: r.words[2].to_string(),
                    key: r.attribute_or_empty("key").to_string(),
                    reason: r.attribute_or_empty("reason").to_string(),
                });
            }
        }
        map
    }

    pub fn supplying<'a>(&'a self, id: &'a str) -> impl Iterator<Item = &'a ContextRelation> + 'a {
        self.relations.iter().filter(move |r| r.from == id)
    }

    pub fn supplied<'a>(&'a self, id: &'a str) -> impl Iterator<Item = &'a ContextRelation> + 'a {
        self.relations.iter().filter(move |r| r.to == id)
    }
}

fn context_of(r: &crate::record::Record, kind: ContextKind) -> Context {
    Context {
        id: r.words[0].to_string(),
        kind,
        label: r.label.to_string(),
        summary: r.attribute_or_empty("summary").to_string(),
        repos: r.attribute_or_empty("repos").to_string(),
        discuss: r.attribute_or_empty("discuss").to_string(),
        aggregates: r.attribute_or_empty("aggregates").to_string(),
        domain_kind: r.attribute_or_empty("kind").to_string(),
    }
}
