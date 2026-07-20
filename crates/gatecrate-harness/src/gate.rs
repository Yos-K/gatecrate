//! ゲートの原型 — 第1〜4層の合成。
//!
//! 第2層を「母集団の決定」と「判定基準」に分けているのは、両者が独立に増えるため。
//! 基準を1つ足すたびに母集団の決定を書き直す構造にしない。

use crate::evidence::Evidence;
use crate::finding::{Finding, Unverifiable, WhenNoSubjects};
use crate::intent::Intent;

/// 検査単位。1件ずつ独立に判定できる粒度で切る（報告が「どこが」を持てる粒度）。
pub trait Subject {
    fn location(&self) -> String;
}

/// 母集団の決定（第2層a）。設定・履歴から「今回何を見るか」を確定する。
pub trait Population {
    type Item: Subject;

    fn collect(&self, evidence: &Evidence) -> Result<Vec<Self::Item>, Unverifiable>;

    /// 対象が0件だったときの意味。既定は合格（変更が無ければ検査対象も無い、が多数派）。
    fn when_empty(&self) -> WhenNoSubjects {
        WhenNoSubjects::Pass
    }
}

/// 判定基準（第2層b）。1つの対象を見て違反を挙げる。
pub trait Criterion<S: Subject> {
    fn judge(&self, subject: &S, evidence: &Evidence) -> Result<Vec<Finding>, Unverifiable>;
}

/// 関数をそのまま基準として使えるようにする（基準の大半は状態を持たない）。
impl<S, F> Criterion<S> for F
where
    S: Subject,
    F: Fn(&S, &Evidence) -> Result<Vec<Finding>, Unverifiable>,
{
    fn judge(&self, subject: &S, evidence: &Evidence) -> Result<Vec<Finding>, Unverifiable> {
        self(subject, evidence)
    }
}

/// 完成したゲート＝意図＋母集団＋基準群。
pub struct Gate<P: Population> {
    intent: Intent,
    population: P,
    criteria: Vec<Box<dyn Criterion<P::Item>>>,
}

impl<P: Population> Gate<P> {
    pub fn new(intent: Intent, population: P) -> Self {
        Self {
            intent,
            population,
            criteria: Vec::new(),
        }
    }

    pub fn checking(mut self, criterion: impl Criterion<P::Item> + 'static) -> Self {
        self.criteria.push(Box::new(criterion));
        self
    }

    pub fn intent(&self) -> Intent {
        self.intent
    }

    /// 全対象 × 全基準を評価する。基準が判定不能を返したら検査全体を不成立にする
    /// （1つでも評価できない基準があるのに「違反なし」と報告してはならない）。
    pub fn inspect(&self, evidence: &Evidence) -> Verdict {
        let subjects = match self.population.collect(evidence) {
            Ok(s) => s,
            Err(u) => return Verdict::Unverifiable(u),
        };

        if subjects.is_empty() && self.population.when_empty() == WhenNoSubjects::Unverifiable {
            return Verdict::Unverifiable(Unverifiable::new(format!(
                "{}: no subjects to inspect",
                self.intent.name
            )));
        }

        let mut findings = Vec::new();
        for subject in &subjects {
            for criterion in &self.criteria {
                match criterion.judge(subject, evidence) {
                    Ok(mut f) => findings.append(&mut f),
                    Err(u) => return Verdict::Unverifiable(u),
                }
            }
        }

        Verdict::Inspected {
            examined: subjects.len(),
            findings,
        }
    }
}

/// 検査の結末。「違反0」と「検査不成立」を型で分ける。
pub enum Verdict {
    Inspected {
        examined: usize,
        findings: Vec<Finding>,
    },
    Unverifiable(Unverifiable),
}
