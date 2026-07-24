//! `.spec` — コマンドの箱の内側（入力 → 処理手順 → 出力）。
//!
//! 1行 = `カードid 種別 テキスト`。種別は in / step / out。
//! step のテキストは `手順名 | 規則` の形を取れる。

use std::collections::BTreeMap;

pub struct Step {
    pub label: String,
    pub rule: String,
}

#[derive(Default)]
pub struct BoxSpec {
    pub inputs: Vec<String>,
    pub steps: Vec<Step>,
    pub outputs: Vec<String>,
}

/// カードid → 箱の内側。
#[derive(Default)]
pub struct CommandSpecs(BTreeMap<String, BoxSpec>);

impl CommandSpecs {
    pub fn parse(source: &str) -> Self {
        let mut specs: BTreeMap<String, BoxSpec> = BTreeMap::new();
        for line in source.lines() {
            let trimmed = line.trim_start();
            if trimmed.is_empty() || trimmed.starts_with('#') {
                continue;
            }
            let mut parts = trimmed.splitn(3, |c: char| c.is_ascii_whitespace());
            let (Some(id), Some(kind)) = (parts.next(), parts.next()) else {
                continue;
            };
            let text = parts.next().unwrap_or("").trim_start().to_string();
            let spec = specs.entry(id.to_string()).or_default();
            match kind {
                "in" => spec.inputs.push(text),
                "out" => spec.outputs.push(text),
                "step" => spec.steps.push(step_of(&text)),
                _ => {}
            }
        }
        Self(specs)
    }

    pub fn of(&self, card_id: &str) -> Option<&BoxSpec> {
        self.0.get(card_id)
    }
}

fn step_of(text: &str) -> Step {
    match text.split_once('|') {
        Some((label, rule)) => Step {
            label: label.trim().to_string(),
            rule: rule.trim().to_string(),
        },
        None => Step {
            label: text.trim().to_string(),
            rule: String::new(),
        },
    }
}
