//! `.es` — イベントストーミングの生きたモデル。
//!
//! カード（N 行）と接続（E 行）の集まり。カードは種別と属性を持ち、接続は関係動詞と
//! 発火条件（when=）を持つ。文法検証は es-lint の仕事で、ここでは読める行だけを読む。

use crate::record::{parse, records, Record};

/// カードの種別。付箋の色に相当する。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum CardKind {
    Actor,
    Command,
    Aggregate,
    Event,
    ErrorEvent,
    Policy,
    ReadModel,
    External,
    Hotspot,
}

impl CardKind {
    pub fn parse(word: &str) -> Option<Self> {
        Some(match word {
            "actor" => Self::Actor,
            "command" => Self::Command,
            "aggregate" => Self::Aggregate,
            "event" => Self::Event,
            "errorevent" => Self::ErrorEvent,
            "policy" => Self::Policy,
            "readmodel" => Self::ReadModel,
            "external" => Self::External,
            "hotspot" => Self::Hotspot,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Actor => "actor",
            Self::Command => "command",
            Self::Aggregate => "aggregate",
            Self::Event => "event",
            Self::ErrorEvent => "errorevent",
            Self::Policy => "policy",
            Self::ReadModel => "readmodel",
            Self::External => "external",
            Self::Hotspot => "hotspot",
        }
    }
}

/// カードが持てる属性の語彙。ビューアの詳細パネルはこの順で値を運ぶ。
pub const CARD_ATTRIBUTES: [&str; 21] = [
    "invariant",
    "evidence",
    "fields",
    "states",
    "transitions",
    "in",
    "out",
    "decide",
    "behaviors",
    "note",
    "role",
    "discuss",
    "biz",
    "measure",
    "capture",
    "compute",
    "becomes",
    "is",
    "kind-of",
    "role-of",
    "alias",
];

pub struct Card {
    pub id: String,
    pub kind: CardKind,
    pub label: String,
    attributes: Vec<(String, String)>,
}

impl Card {
    pub fn attribute(&self, key: &str) -> &str {
        self.attributes
            .iter()
            .rev()
            .find(|(k, _)| k == key)
            .map(|(_, v)| v.as_str())
            .unwrap_or("")
    }
}

/// 接続の関係動詞。矢印の意味。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Relation {
    /// アクター/ポリシーがコマンドを発行する。
    Issues,
    /// 集約がコマンドを処理する。
    Handles,
    /// 集約がイベントを発する。
    Emits,
    /// イベントがポリシー等を起動する。
    Triggers,
    /// イベントがリードモデルへ供給される。
    Feeds,
    /// ホットスポットが論点を指す。
    Marks,
}

impl Relation {
    pub fn parse(word: &str) -> Option<Self> {
        Some(match word {
            "issues" => Self::Issues,
            "handles" => Self::Handles,
            "emits" => Self::Emits,
            "triggers" => Self::Triggers,
            "feeds" => Self::Feeds,
            "marks" => Self::Marks,
            _ => return None,
        })
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Issues => "issues",
            Self::Handles => "handles",
            Self::Emits => "emits",
            Self::Triggers => "triggers",
            Self::Feeds => "feeds",
            Self::Marks => "marks",
        }
    }
}

pub struct Connection {
    pub from: String,
    pub relation: Relation,
    pub to: String,
    /// 発火条件（`when=`）。ポリシー→コマンドの矢印ラベルになる。
    pub when: Option<String>,
}

#[derive(Default)]
pub struct EventModel {
    pub cards: Vec<Card>,
    pub connections: Vec<Connection>,
}

impl EventModel {
    pub fn parse(source: &str) -> Self {
        let mut model = Self::default();
        for line in records(source) {
            if let Some(r) = parse(line, "N", 2) {
                if let Some(card) = card_of(&r) {
                    model.cards.push(card);
                }
            } else if let Some(r) = parse(line, "E", 3) {
                if let Some(connection) = connection_of(&r) {
                    model.connections.push(connection);
                }
            }
        }
        model
    }

    pub fn outgoing<'a>(&'a self, id: &'a str) -> impl Iterator<Item = &'a Connection> + 'a {
        self.connections.iter().filter(move |c| c.from == id)
    }

    pub fn incoming<'a>(&'a self, id: &'a str) -> impl Iterator<Item = &'a Connection> + 'a {
        self.connections.iter().filter(move |c| c.to == id)
    }
}

fn card_of(r: &Record) -> Option<Card> {
    Some(Card {
        id: r.words[0].to_string(),
        kind: CardKind::parse(r.words[1])?,
        label: r.label.to_string(),
        attributes: CARD_ATTRIBUTES
            .iter()
            .filter_map(|key| r.attribute(key).map(|v| (key.to_string(), v.to_string())))
            .collect(),
    })
}

fn connection_of(r: &Record) -> Option<Connection> {
    Some(Connection {
        from: r.words[0].to_string(),
        relation: Relation::parse(r.words[1])?,
        to: r.words[2].to_string(),
        when: r.attribute("when").map(str::to_string),
    })
}
