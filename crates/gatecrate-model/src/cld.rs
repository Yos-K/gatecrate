//! `.cld` — 因果ループ図。システム思考の「変数」「符号付き因果」「ループ」。

use crate::record::{parse, records};

pub struct Variable {
    pub id: String,
    pub label: String,
}

/// 因果の向き。＋=同方向（増えれば増える）、－=逆方向（増えれば減る）。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Polarity {
    Same,
    Opposite,
}

pub struct CausalLink {
    pub from: String,
    pub to: String,
    pub polarity: Polarity,
}

/// ループの型。R=強化（増幅・成長・暴走）、B=バランス（抑制・安定）。
#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum LoopKind {
    Reinforcing,
    Balancing,
}

impl LoopKind {
    pub fn parse(word: &str) -> Option<Self> {
        match word {
            "R" => Some(Self::Reinforcing),
            "B" => Some(Self::Balancing),
            _ => None,
        }
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::Reinforcing => "R",
            Self::Balancing => "B",
        }
    }
}

pub struct FeedbackLoop {
    pub id: String,
    pub kind: LoopKind,
    /// 関与変数（カンマ区切りのまま保持。表示側が分解する）。
    pub variables: String,
    pub description: String,
}

#[derive(Default)]
pub struct CausalLoopDiagram {
    pub variables: Vec<Variable>,
    pub links: Vec<CausalLink>,
    pub loops: Vec<FeedbackLoop>,
}

impl CausalLoopDiagram {
    pub fn parse(source: &str) -> Self {
        let mut diagram = Self::default();
        for line in records(source) {
            if let Some(r) = parse(line, "V", 1) {
                diagram.variables.push(Variable {
                    id: r.words[0].to_string(),
                    label: r.label.to_string(),
                });
            } else if let Some(r) = parse(line, "L", 3) {
                diagram.links.push(CausalLink {
                    from: r.words[0].to_string(),
                    to: r.words[1].to_string(),
                    polarity: if r.words[2] == "-" {
                        Polarity::Opposite
                    } else {
                        Polarity::Same
                    },
                });
            } else if let Some(r) = parse(line, "LOOP", 3) {
                if let Some(kind) = LoopKind::parse(r.words[1]) {
                    diagram.loops.push(FeedbackLoop {
                        id: r.words[0].to_string(),
                        kind,
                        variables: r.words[2].to_string(),
                        description: r.label.to_string(),
                    });
                }
            }
        }
        diagram
    }
}
