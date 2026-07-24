//! ADR レビュー宣言ゲートの検査。証拠層を差し替えるので実 git を起動しない。

use gatecrate_harness::evidence::{Commit, CommitId, History, Lookup, LookupError, Workspace};
use gatecrate_harness::{report, Evidence, Settings, Verdict};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

#[derive(Default)]
struct FakeHistory {
    resolvable: Vec<String>,
    commits: Vec<Commit>,
    /// (コミット, パス) → 内容。コミット時点の見え方を表現する。
    contents: BTreeMap<(String, String), String>,
}

impl FakeHistory {
    fn with_base(mut self, revision: &str) -> Self {
        self.resolvable.push(revision.to_string());
        self
    }

    fn commit(mut self, id: &str, subject: &str, trailer: Option<&str>) -> Self {
        let message = match trailer {
            Some(t) => format!("{subject}\n\n{t}\n"),
            None => format!("{subject}\n"),
        };
        self.commits.push(Commit {
            id: CommitId(id.to_string()),
            subject: subject.to_string(),
            message,
        });
        self
    }

    fn document(mut self, commit: &str, path: &str, body: &str) -> Self {
        self.contents
            .insert((commit.to_string(), path.to_string()), body.to_string());
        self
    }
}

impl History for FakeHistory {
    fn resolve(&self, revision: &str) -> Lookup<CommitId> {
        if self.resolvable.iter().any(|r| r == revision) {
            Ok(CommitId(format!("resolved:{revision}")))
        } else {
            Err(LookupError::NotFound(revision.to_string()))
        }
    }

    fn commits_between(&self, _base: &CommitId, _head: &str) -> Lookup<Vec<Commit>> {
        Ok(self.commits.clone())
    }

    fn read_at(&self, commit: &CommitId, path: &str) -> Lookup<String> {
        self.contents
            .get(&(commit.0.clone(), path.to_string()))
            .cloned()
            .ok_or_else(|| LookupError::NotFound(path.to_string()))
    }

    fn exists_at(&self, commit: &CommitId, path: &str) -> bool {
        self.contents
            .contains_key(&(commit.0.clone(), path.to_string()))
    }
}

struct NoWorkspace;

impl Workspace for NoWorkspace {
    fn root(&self) -> &Path {
        Path::new(".")
    }
    fn exists(&self, _path: &str) -> bool {
        false
    }
    fn read(&self, path: &str) -> Lookup<String> {
        Err(LookupError::NotFound(path.to_string()))
    }
    fn walk(&self, dir: &str) -> Lookup<Vec<PathBuf>> {
        Err(LookupError::NotFound(dir.to_string()))
    }
}

fn canonical_record() -> String {
    ["Decision", "Alternatives Considered", "Why This Decision", "Why Alternatives Were Rejected", "Reconsider When"]
        .iter()
        .map(|s| format!("## {s}\nbody\n"))
        .collect()
}

fn companion_record() -> String {
    ["決定事項", "検討した選択肢", "選択理由", "選択しなかった理由", "決定を見直す契機"]
        .iter()
        .map(|s| format!("## {s}\nbody\n"))
        .collect()
}

fn inspect(history: &FakeHistory, settings: Settings) -> Verdict {
    let workspace = NoWorkspace;
    let evidence = Evidence {
        workspace: &workspace,
        history,
        settings: &settings,
    };
    gatecrate_gates::adr_review::gate().inspect(&evidence)
}

fn exit_code(verdict: Verdict) -> u8 {
    report(gatecrate_gates::adr_review::INTENT, verdict).exit_code
}

fn default_settings() -> Settings {
    Settings::from_pairs([("ADR_REVIEW_BASE", "origin/main")])
}

fn with_record(history: FakeHistory, commit: &str) -> FakeHistory {
    history
        .document(commit, "docs/adr/0001-example.md", &canonical_record())
        .document(commit, "docs/adr/0001-example.ja.md", &companion_record())
}

#[test]
fn a_commit_citing_a_valid_record_passes() {
    let history = with_record(
        FakeHistory::default()
            .with_base("origin/main")
            .commit("c1", "feat: add x", Some("ADR-Review: docs/adr/0001-example.md")),
        "c1",
    );
    assert_eq!(exit_code(inspect(&history, default_settings())), report::PASS);
}

#[test]
fn a_reasoned_none_passes_but_a_bare_none_does_not() {
    let reasoned = FakeHistory::default()
        .with_base("origin/main")
        .commit("c1", "fix: y", Some("ADR-Review: none (pure refactor, no decision touched)"));
    assert_eq!(exit_code(inspect(&reasoned, default_settings())), report::PASS);

    let bare = FakeHistory::default()
        .with_base("origin/main")
        .commit("c1", "fix: y", Some("ADR-Review: none"));
    assert_eq!(exit_code(inspect(&bare, default_settings())), report::VIOLATION);
}

#[test]
fn a_missing_declaration_is_a_violation() {
    let history = FakeHistory::default()
        .with_base("origin/main")
        .commit("c1", "feat: add x", None);
    assert_eq!(exit_code(inspect(&history, default_settings())), report::VIOLATION);
}

#[test]
fn commit_types_outside_the_configured_set_need_no_declaration() {
    let history = FakeHistory::default()
        .with_base("origin/main")
        .commit("c1", "chore: tidy", None)
        .commit("c2", "docs: note", None);
    assert_eq!(exit_code(inspect(&history, default_settings())), report::PASS);
}

#[test]
fn a_record_added_only_after_the_declaring_commit_is_a_violation() {
    // 宣言コミット c1 には無く、後続 c2 にだけ存在する＝辻褄合わせを弾く
    let history = FakeHistory::default()
        .with_base("origin/main")
        .commit("c1", "feat: add x", Some("ADR-Review: docs/adr/0001-example.md"));
    let history = with_record(history, "c2");
    assert_eq!(exit_code(inspect(&history, default_settings())), report::VIOLATION);
}

#[test]
fn a_record_missing_a_required_section_is_a_violation() {
    let history = FakeHistory::default()
        .with_base("origin/main")
        .commit("c1", "feat: add x", Some("ADR-Review: docs/adr/0001-example.md"))
        .document("c1", "docs/adr/0001-example.md", "## Decision\nbody\n")
        .document("c1", "docs/adr/0001-example.ja.md", &companion_record());
    assert_eq!(exit_code(inspect(&history, default_settings())), report::VIOLATION);
}

#[test]
fn citing_a_companion_instead_of_the_canonical_record_is_a_violation() {
    let history = with_record(
        FakeHistory::default()
            .with_base("origin/main")
            .commit("c1", "feat: add x", Some("ADR-Review: docs/adr/0001-example.ja.md")),
        "c1",
    );
    assert_eq!(exit_code(inspect(&history, default_settings())), report::VIOLATION);
}

#[test]
fn an_unresolvable_base_is_unverifiable_not_a_pass() {
    let history = FakeHistory::default().commit("c1", "feat: add x", None);
    assert_eq!(
        exit_code(inspect(&history, default_settings())),
        report::UNVERIFIABLE
    );
}

#[test]
fn disabling_reasoned_none_demands_a_record() {
    let settings = default_settings().overriding("ADR_ALLOW_REASONED_NONE", "false");
    let history = FakeHistory::default()
        .with_base("origin/main")
        .commit("c1", "feat: x", Some("ADR-Review: none (still refused)"));
    assert_eq!(exit_code(inspect(&history, settings)), report::VIOLATION);
}

#[test]
fn clearing_companion_suffixes_stops_requiring_a_companion() {
    let settings = default_settings().overriding("ADR_COMPANION_SUFFIXES", "");
    let history = FakeHistory::default()
        .with_base("origin/main")
        .commit("c1", "feat: x", Some("ADR-Review: docs/adr/0001-example.md"))
        .document("c1", "docs/adr/0001-example.md", &canonical_record());
    assert_eq!(exit_code(inspect(&history, settings)), report::PASS);
}

#[test]
fn a_violation_report_states_where_what_was_expected_and_how_to_fix_it() {
    let history = FakeHistory::default()
        .with_base("origin/main")
        .commit("c1", "feat: add x", None);
    let rendered = report(
        gatecrate_gates::adr_review::INTENT,
        inspect(&history, default_settings()),
    );
    let text = rendered.stderr;
    assert!(text.contains("feat: add x"), "names the subject: {text}");
    assert!(text.contains("expected:"), "states the expectation: {text}");
    assert!(text.contains("observed:"), "states the observation: {text}");
    assert!(text.contains("fix:"), "offers a remedy: {text}");
    assert!(
        text.contains("out of scope"),
        "declares what it does not detect: {text}"
    );
}
