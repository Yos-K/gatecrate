//! ADR レビュー宣言ゲート（sh 版 check-adr-review.sh の移植）。
//!
//! 層の対応:
//!   意図   = 設計判断を知らずに覆す変更を止める
//!   母集団 = base..HEAD のうち設定されたタイプのコミット
//!   基準   = 宣言がちょうど1つ / 参照先が宣言コミット時点で構造的に妥当
//!   証拠   = 履歴（コミット時点の内容）と設定

use gatecrate_harness::evidence::{Commit, Evidence};
use gatecrate_harness::{
    Criterion, Finding, Gate, GateKind, Intent, Population, Subject, Unverifiable,
};

const TRAILER: &str = "ADR-Review";

pub const INTENT: Intent = Intent {
    name: "adr-review",
    kind: GateKind::Prevention,
    detects: "every change declares which architectural decisions it reviewed",
    because: "a decision that lives only in old code or a closed PR gets reversed by accident",
    does_not_detect: &[
        "whether a declared `none` reason is honest",
        "whether the implementation actually complies with the decision it cites",
    ],
};

pub struct Conventions {
    pub commit_types: Vec<String>,
    pub directory: String,
    pub canonical_suffix: String,
    pub companion_suffixes: Vec<String>,
    pub allow_reasoned_none: bool,
    pub required_sections: Vec<String>,
    pub required_companion_sections: Vec<String>,
    pub base: String,
}

impl Conventions {
    pub fn from(evidence: &Evidence) -> Self {
        let s = evidence.settings;
        Self {
            commit_types: s.list("ADR_REVIEW_COMMIT_TYPES", "feat fix"),
            directory: s.or_default("ADR_DIRECTORY", "docs/adr").to_string(),
            canonical_suffix: s.or_default("ADR_CANONICAL_SUFFIX", ".md").to_string(),
            companion_suffixes: s
                .get_allowing_empty("ADR_COMPANION_SUFFIXES")
                .unwrap_or(".ja.md")
                .split_ascii_whitespace()
                .map(str::to_string)
                .collect(),
            allow_reasoned_none: s.flag("ADR_ALLOW_REASONED_NONE", true),
            required_sections: split_sections(s.or_default(
                "ADR_REQUIRED_SECTIONS",
                "Decision|Alternatives Considered|Why This Decision|Why Alternatives Were Rejected|Reconsider When",
            )),
            required_companion_sections: split_sections(s.or_default(
                "ADR_REQUIRED_COMPANION_SECTIONS",
                "決定事項|検討した選択肢|選択理由|選択しなかった理由|決定を見直す契機",
            )),
            base: s.or_default("ADR_REVIEW_BASE", "origin/main").to_string(),
        }
    }

    fn governs(&self, subject: &str) -> bool {
        let head = subject.split(['(', '!', ':']).next().unwrap_or("");
        self.commit_types.iter().any(|t| t == head)
    }

    fn companions_of(&self, path: &str) -> Vec<String> {
        let stem = path.strip_suffix(&self.canonical_suffix).unwrap_or(path);
        self.companion_suffixes
            .iter()
            .map(|suffix| format!("{stem}{suffix}"))
            .collect()
    }

    fn is_companion_path(&self, path: &str) -> bool {
        self.companion_suffixes.iter().any(|s| path.ends_with(s))
    }

    fn is_canonical_path(&self, path: &str) -> bool {
        let Some(rest) = path.strip_prefix(&format!("{}/", self.directory)) else {
            return false;
        };
        let digits = rest.chars().take(4).filter(char::is_ascii_digit).count();
        digits == 4 && rest[4..].starts_with('-') && rest.ends_with(&self.canonical_suffix)
    }
}

fn split_sections(spec: &str) -> Vec<String> {
    spec.split('|').map(str::to_string).collect()
}

/// 検査対象のコミット。
pub struct GovernedCommit(pub Commit);

impl Subject for GovernedCommit {
    fn location(&self) -> String {
        format!("{} {}", short(&self.0.id.0), self.0.subject)
    }
}

fn short(id: &str) -> &str {
    &id[..id.len().min(8)]
}

/// 母集団 — base..HEAD のうち、宣言を義務づけられたタイプのコミット。
pub struct ChangedCommits;

impl Population for ChangedCommits {
    type Item = GovernedCommit;

    fn collect(&self, evidence: &Evidence) -> Result<Vec<Self::Item>, Unverifiable> {
        let conventions = Conventions::from(evidence);
        let base = evidence
            .history
            .resolve(&conventions.base)
            .map_err(|e| {
                Unverifiable::new(format!("base '{}' is not resolvable ({e})", conventions.base))
                    .remedy("fetch the base branch, or set ADR_REVIEW_BASE to a reachable ref")
            })?;
        let commits = evidence
            .history
            .commits_between(&base, "HEAD")
            .map_err(|e| Unverifiable::new(format!("cannot list commits: {e}")))?;
        Ok(commits
            .into_iter()
            .filter(|c| conventions.governs(&c.subject))
            .map(GovernedCommit)
            .collect())
    }
}

/// 宣言そのものの形。
enum Declaration {
    Missing(usize),
    ReasonedNone,
    BareNone,
    References(Vec<String>),
}

fn declaration_of(commit: &Commit) -> Declaration {
    let trailers = commit.trailers(TRAILER);
    if trailers.len() != 1 {
        return Declaration::Missing(trailers.len());
    }
    let value = trailers[0];
    if value == "none" {
        return Declaration::BareNone;
    }
    if value.starts_with("none (") && value.ends_with(')') && value.len() > "none ()".len() {
        return Declaration::ReasonedNone;
    }
    Declaration::References(value.split(',').map(|p| p.trim().to_string()).collect())
}

/// 基準1 — 宣言がちょうど1つあり、理由なき `none` でないこと。
pub fn declares_review(
    subject: &GovernedCommit,
    evidence: &Evidence,
) -> Result<Vec<Finding>, Unverifiable> {
    let conventions = Conventions::from(evidence);
    let location = subject.location();
    Ok(match declaration_of(&subject.0) {
        Declaration::Missing(found) => vec![Finding::new(
            location,
            format!("exactly one `{TRAILER}:` trailer"),
            format!("{found} trailers"),
        )
        .remedy(format!(
            "add `{TRAILER}: {}/0001-example{}` or `{TRAILER}: none (<reason>)`",
            conventions.directory, conventions.canonical_suffix
        ))],
        Declaration::BareNone => vec![Finding::new(
            location,
            "a reason explaining why no decision applies",
            format!("bare `{TRAILER}: none`"),
        )
        .remedy(format!("write `{TRAILER}: none (<reason>)`"))],
        Declaration::ReasonedNone if !conventions.allow_reasoned_none => vec![Finding::new(
            location,
            "a reference to an architectural decision record",
            "`none` with a reason (disabled by ADR_ALLOW_REASONED_NONE=false)",
        )
        .remedy("cite the decision this change was reviewed against")],
        _ => Vec::new(),
    })
}

/// 基準2 — 参照先が「宣言コミット時点で」実在し、必須の節を備えること。
/// HEAD でなく宣言コミット時点を見るのは、後から足した ADR で辻褄を合わせられないようにするため。
pub fn references_resolve_at_declaring_commit(
    subject: &GovernedCommit,
    evidence: &Evidence,
) -> Result<Vec<Finding>, Unverifiable> {
    let conventions = Conventions::from(evidence);
    let Declaration::References(paths) = declaration_of(&subject.0) else {
        return Ok(Vec::new());
    };
    let commit = &subject.0.id;
    let location = subject.location();
    let mut findings = Vec::new();

    for path in paths {
        if conventions.is_companion_path(&path) {
            findings.push(
                Finding::new(
                    &location,
                    format!("the canonical record (*{})", conventions.canonical_suffix),
                    format!("a companion document: {path}"),
                )
                .remedy("reference the canonical record; companions are checked automatically"),
            );
            continue;
        }
        if !conventions.is_canonical_path(&path) {
            findings.push(
                Finding::new(
                    &location,
                    format!(
                        "a path like {}/NNNN-*{}",
                        conventions.directory, conventions.canonical_suffix
                    ),
                    path.clone(),
                )
                .remedy("cite a numbered record inside the configured ADR directory"),
            );
            continue;
        }
        for document in std::iter::once(path.clone()).chain(conventions.companions_of(&path)) {
            let sections = if document == path {
                &conventions.required_sections
            } else {
                &conventions.required_companion_sections
            };
            match evidence.history.read_at(commit, &document) {
                Err(_) => findings.push(
                    Finding::new(
                        &location,
                        format!("{document} to exist in this commit"),
                        "absent at the declaring commit".to_string(),
                    )
                    .remedy("add the record in the same commit that cites it"),
                ),
                Ok(content) => {
                    for section in sections {
                        if !content.lines().any(|l| l == format!("## {section}")) {
                            findings.push(
                                Finding::new(
                                    &location,
                                    format!("{document} to contain `## {section}`"),
                                    "section missing".to_string(),
                                )
                                .remedy("a decision record must state the decision, the alternatives, and when to reconsider"),
                            );
                        }
                    }
                }
            }
        }
    }
    Ok(findings)
}

pub fn gate() -> Gate<ChangedCommits> {
    Gate::new(INTENT, ChangedCommits)
        .checking(declares_review as fn(&GovernedCommit, &Evidence) -> _)
        .checking(references_resolve_at_declaring_commit as fn(&GovernedCommit, &Evidence) -> _)
}

/// 型が基準として使えることをコンパイル時に確かめる。
const _: fn() = || {
    fn assert_criterion<C: Criterion<GovernedCommit>>() {}
    assert_criterion::<fn(&GovernedCommit, &Evidence) -> Result<Vec<Finding>, Unverifiable>>();
};
