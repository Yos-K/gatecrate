//! トレーサビリティゲートの検査。作業ツリーを差し替えるのでファイルを一切作らない。

mod support;

use gatecrate_harness::{report, Verdict};
use support::{FakeWorkspace, NoHistory};

const VALID_ROW: &str =
    "menu-open|scroll_menu|src/Menu.java|scrollMenu|tests/MenuTest.java|verticalSwipeReaches";

fn workspace() -> FakeWorkspace {
    FakeWorkspace::default()
        .file(
            "docs/harness/interaction-model-transitions.psv",
            "# from_state|command|to_state|event\nmenu-open|scroll_menu|menu-open|Menu scrolled\n",
        )
        .file(
            "src/Menu.java",
            "// interaction-command: scroll_menu\nvoid scrollMenu() {}\n",
        )
        .file("tests/MenuTest.java", "void verticalSwipeReaches() {}\n")
}

fn with_contracts(workspace: FakeWorkspace, rows: &[&str]) -> FakeWorkspace {
    let mut body = String::from("# state_id|command|implementation|implementation_locator|test|test_locator\n");
    for row in rows {
        body.push_str(row);
        body.push('\n');
    }
    workspace.file("docs/harness/interaction-command-contracts.psv", &body)
}

fn inspect(workspace: &FakeWorkspace) -> Verdict {
    let history = NoHistory;
    let settings = gatecrate_harness::Settings::from_pairs(Vec::<(String, String)>::new());
    let evidence = gatecrate_harness::Evidence {
        workspace,
        history: &history,
        settings: &settings,
    };
    gatecrate_gates::interaction_traceability::gate().inspect(&evidence)
}

fn exit_code(workspace: &FakeWorkspace) -> u8 {
    report(
        gatecrate_gates::interaction_traceability::INTENT,
        inspect(workspace),
    )
    .exit_code
}

fn findings(workspace: &FakeWorkspace) -> String {
    let r = report(
        gatecrate_gates::interaction_traceability::INTENT,
        inspect(workspace),
    );
    format!("{}{}", r.stdout, r.stderr)
}

#[test]
fn a_complete_chain_passes() {
    let ws = with_contracts(workspace(), &[VALID_ROW]);
    assert_eq!(exit_code(&ws), report::PASS);
}

#[test]
fn a_command_with_no_modeled_transition_is_a_violation() {
    let ws = with_contracts(
        workspace(),
        &["menu-open|ghost|src/Menu.java|scrollMenu|tests/MenuTest.java|verticalSwipeReaches"],
    );
    assert_eq!(exit_code(&ws), report::VIOLATION);
    assert!(findings(&ws).contains("no modeled transition"));
}

#[test]
fn a_drifted_implementation_locator_is_a_violation() {
    let ws = with_contracts(
        workspace(),
        &["menu-open|scroll_menu|src/Menu.java|renamedAway|tests/MenuTest.java|verticalSwipeReaches"],
    );
    assert_eq!(exit_code(&ws), report::VIOLATION);
    assert!(findings(&ws).contains("implementation locator has drifted"));
}

#[test]
fn a_drifted_test_locator_is_a_violation() {
    let ws = with_contracts(
        workspace(),
        &["menu-open|scroll_menu|src/Menu.java|scrollMenu|tests/MenuTest.java|renamedAway"],
    );
    assert_eq!(exit_code(&ws), report::VIOLATION);
    assert!(findings(&ws).contains("behavior test locator has drifted"));
}

#[test]
fn a_missing_evidence_file_is_a_violation() {
    let ws = with_contracts(
        workspace(),
        &["menu-open|scroll_menu|src/Gone.java|scrollMenu|tests/MenuTest.java|verticalSwipeReaches"],
    );
    assert_eq!(exit_code(&ws), report::VIOLATION);
    assert!(findings(&ws).contains("file is absent"));
}

#[test]
fn a_placeholder_column_is_a_violation() {
    let ws = with_contracts(
        workspace(),
        &["menu-open|scroll_menu|-|scrollMenu|tests/MenuTest.java|verticalSwipeReaches"],
    );
    assert_eq!(exit_code(&ws), report::VIOLATION);
}

#[test]
fn a_row_with_extra_columns_is_a_violation() {
    let ws = with_contracts(workspace(), &[&format!("{VALID_ROW}|extra")]);
    assert_eq!(exit_code(&ws), report::VIOLATION);
    assert!(findings(&ws).contains("7 columns"));
}

#[test]
fn duplicate_contracts_are_a_violation() {
    let ws = with_contracts(workspace(), &[VALID_ROW, VALID_ROW]);
    assert_eq!(exit_code(&ws), report::VIOLATION);
    assert!(findings(&ws).contains("already contracted"));
}

#[test]
fn a_marked_command_without_a_contract_is_a_violation() {
    let ws = with_contracts(workspace(), &[VALID_ROW]).file(
        "src/Other.java",
        "// interaction-command: unregistered_command\n",
    );
    assert_eq!(exit_code(&ws), report::VIOLATION);
    assert!(findings(&ws).contains("unregistered_command"));
}

#[test]
fn a_missing_ledger_is_unverifiable_not_a_pass() {
    let ws = workspace();
    assert_eq!(exit_code(&ws), report::UNVERIFIABLE);
}

#[test]
fn a_missing_transitions_model_is_unverifiable_not_a_violation_of_every_row() {
    let ws = with_contracts(FakeWorkspace::default(), &[VALID_ROW]);
    assert_eq!(exit_code(&ws), report::UNVERIFIABLE);
    assert!(findings(&ws).contains("transitions model is unreadable"));
}

#[test]
fn comments_and_the_header_row_are_not_contracts() {
    let ws = with_contracts(workspace(), &["# a note", VALID_ROW]);
    assert_eq!(exit_code(&ws), report::PASS);
}
