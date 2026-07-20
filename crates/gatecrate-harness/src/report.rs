//! 第5層 — 検出したあとどうするか。消費者から見える契約はここに一度だけ書く。
//!
//! exit code の意味は全ゲート共通:
//!   0 = 合格 / 1 = 違反 / 2 = 検査不成立（設定・依存の欠落。黙って合格にしない）

use crate::gate::Verdict;
use crate::intent::{GateKind, Intent};
use std::io::Write;

pub const PASS: u8 = 0;
pub const VIOLATION: u8 = 1;
pub const UNVERIFIABLE: u8 = 2;

pub struct Report {
    pub exit_code: u8,
    pub stdout: String,
    pub stderr: String,
}

impl Report {
    pub fn emit(&self, out: &mut impl Write, err: &mut impl Write) -> std::io::Result<u8> {
        if !self.stdout.is_empty() {
            write!(out, "{}", self.stdout)?;
        }
        if !self.stderr.is_empty() {
            write!(err, "{}", self.stderr)?;
        }
        Ok(self.exit_code)
    }
}

/// 判定を消費者向けの報告に翻訳する。advisory は違反を報告しつつ合格で返す
/// （マージを止めないが信号は出す、という型の意味をここで一度だけ実装する）。
pub fn report(intent: Intent, verdict: Verdict) -> Report {
    match verdict {
        Verdict::Unverifiable(u) => {
            let mut stderr = format!("{}: cannot verify — {}\n", intent.name, u.reason);
            if let Some(r) = &u.remedy {
                stderr.push_str(&format!("{}: {}\n", intent.name, r));
            }
            stderr.push_str(&format!(
                "{}: refusing to report a pass without inspecting.\n",
                intent.name
            ));
            Report {
                exit_code: UNVERIFIABLE,
                stdout: String::new(),
                stderr,
            }
        }
        Verdict::Inspected { examined, findings } if findings.is_empty() => Report {
            exit_code: PASS,
            stdout: format!(
                "{}: {} ({} subject{} inspected).\n",
                intent.name,
                intent.detects,
                examined,
                plural(examined)
            ),
            stderr: String::new(),
        },
        Verdict::Inspected { examined, findings } => {
            let mut body = format!(
                "{}: {} — {} finding{} in {} subject{}.\n",
                intent.name,
                intent.detects,
                findings.len(),
                plural(findings.len()),
                examined,
                plural(examined)
            );
            body.push_str(&format!("why this matters: {}\n", intent.because));
            for f in &findings {
                body.push_str(&format!("\n  {}\n", f.location));
                body.push_str(&format!("    expected: {}\n", f.expected));
                body.push_str(&format!("    observed: {}\n", f.observed));
                if let Some(r) = &f.remedy {
                    body.push_str(&format!("    fix:      {r}\n"));
                }
            }
            if !intent.does_not_detect.is_empty() {
                body.push_str("\nout of scope for this gate (do not expect it to catch these):\n");
                for limit in intent.does_not_detect {
                    body.push_str(&format!("  - {limit}\n"));
                }
            }
            if intent.kind == GateKind::Advisory {
                body.push_str("\nadvisory: reported, not blocking.\n");
                return Report {
                    exit_code: PASS,
                    stdout: body,
                    stderr: String::new(),
                };
            }
            Report {
                exit_code: VIOLATION,
                stdout: String::new(),
                stderr: body,
            }
        }
    }
}

fn plural(n: usize) -> &'static str {
    if n == 1 {
        ""
    } else {
        "s"
    }
}
