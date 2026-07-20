//! 相互作用コマンドのトレーサビリティゲート（sh 版 check-interaction-command-traceability.sh の移植）。
//!
//! 層の対応:
//!   意図   = モデルが緑でも実装を守っていない状態を止める
//!   母集団 = 契約台帳の各行
//!   基準   = 行が完全 / 遷移がモデル化済み / 実装と挙動テストの証拠が生きている
//!   整合   = 契約の重複が無い / 実装側マーカーに契約がある
//!   証拠   = 作業ツリーと設定

use gatecrate_harness::evidence::Evidence;
use gatecrate_harness::{
    Coherence, Finding, Gate, GateKind, Intent, Population, Subject, Unverifiable, WhenNoSubjects,
};
use std::cell::OnceCell;
use std::collections::BTreeMap;

pub const INTENT: Intent = Intent {
    name: "interaction-traceability",
    kind: GateKind::Prevention,
    detects: "every contracted interaction reaches implementation and a behavior test",
    because: "a modeled command with no test lets a green model coexist with a broken interaction",
    does_not_detect: &[
        "whether the behavior test actually exercises the interaction it names",
        "interactions that were never contracted (adoption is deliberately incremental)",
    ],
};

const PLACEHOLDER: &str = "-";
const MARKER: &str = "interaction-command:";
const COLUMNS: usize = 6;

pub struct Paths {
    pub contracts: String,
    pub transitions: String,
    pub source_root: String,
}

impl Paths {
    pub fn from(evidence: &Evidence) -> Self {
        let s = evidence.settings;
        Self {
            contracts: s
                .or_default(
                    "INTERACTION_CONTRACTS",
                    "docs/harness/interaction-command-contracts.psv",
                )
                .to_string(),
            transitions: s
                .or_default(
                    "INTERACTION_TRANSITIONS",
                    "docs/harness/interaction-model-transitions.psv",
                )
                .to_string(),
            source_root: s.or_default("INTERACTION_SOURCE_ROOT", "src").to_string(),
        }
    }
}

/// 台帳の1行。読めた列だけを持ち、欠けは基準側が違反として報告する。
pub struct ContractRow {
    pub file: String,
    pub line: usize,
    cells: Vec<String>,
}

impl ContractRow {
    fn cell(&self, index: usize) -> Option<&str> {
        self.cells
            .get(index)
            .map(String::as_str)
            .filter(|v| !v.is_empty() && *v != PLACEHOLDER)
    }

    pub fn state(&self) -> Option<&str> {
        self.cell(0)
    }
    pub fn command(&self) -> Option<&str> {
        self.cell(1)
    }
    fn implementation(&self) -> Option<Trace<'_>> {
        Some(Trace {
            role: "implementation",
            path: self.cell(2)?,
            locator: self.cell(3)?,
        })
    }
    fn behavior_test(&self) -> Option<Trace<'_>> {
        Some(Trace {
            role: "behavior test",
            path: self.cell(4)?,
            locator: self.cell(5)?,
        })
    }

    /// state|command。両方揃った行だけが同一性を持つ。
    pub fn identity(&self) -> Option<String> {
        Some(format!("{}|{}", self.state()?, self.command()?))
    }
}

struct Trace<'a> {
    role: &'static str,
    path: &'a str,
    locator: &'a str,
}

impl Subject for ContractRow {
    fn location(&self) -> String {
        match self.identity() {
            Some(id) => format!("{}:{} ({id})", self.file, self.line),
            None => format!("{}:{}", self.file, self.line),
        }
    }
}

/// 母集団 — 契約台帳の全行。台帳が無いことは合格ではなく検査不成立。
pub struct ContractLedger;

impl Population for ContractLedger {
    type Item = ContractRow;

    fn collect(&self, evidence: &Evidence) -> Result<Vec<Self::Item>, Unverifiable> {
        let paths = Paths::from(evidence);
        let contracts = evidence.workspace.read(&paths.contracts).map_err(|e| {
            Unverifiable::new(format!("contracts ledger is unreadable: {e}")).remedy(format!(
                "create {} or point INTERACTION_CONTRACTS at the ledger",
                paths.contracts
            ))
        })?;
        // 遷移表も検査の前提。ここで確かめないと「遷移が無い」が全行の違反に化ける。
        evidence.workspace.read(&paths.transitions).map_err(|e| {
            Unverifiable::new(format!("transitions model is unreadable: {e}")).remedy(format!(
                "create {} or point INTERACTION_TRANSITIONS at the model",
                paths.transitions
            ))
        })?;

        Ok(rows_of(&contracts, &paths.contracts))
    }

    fn when_empty(&self) -> WhenNoSubjects {
        WhenNoSubjects::Pass
    }
}

fn rows_of(source: &str, file: &str) -> Vec<ContractRow> {
    source
        .lines()
        .enumerate()
        .filter(|(_, line)| is_record(line))
        .map(|(index, line)| ContractRow {
            file: file.to_string(),
            line: index + 1,
            cells: line.split('|').map(|c| c.trim().to_string()).collect(),
        })
        .collect()
}

fn is_record(line: &str) -> bool {
    let trimmed = line.trim();
    !(trimmed.is_empty() || trimmed.starts_with('#') || trimmed.starts_with("state_id|"))
}

/// 基準 — 行が6列そろっていること。
pub fn row_is_complete(
    row: &ContractRow,
    _evidence: &Evidence,
) -> Result<Vec<Finding>, Unverifiable> {
    if row.cells.len() != COLUMNS {
        return Ok(vec![Finding::new(
            row.location(),
            format!("{COLUMNS} columns: state|command|implementation|locator|test|locator"),
            format!("{} columns", row.cells.len()),
        )
        .remedy("one contract per row, every column filled")]);
    }
    if (0..COLUMNS).any(|i| row.cell(i).is_none()) {
        return Ok(vec![Finding::new(
            row.location(),
            "every column to carry a value",
            "an empty or placeholder column".to_string(),
        )
        .remedy("a contract with a hole traces nothing; fill it or delete the row")]);
    }
    Ok(Vec::new())
}

/// 基準 — 契約された state+command が遷移表に存在すること。
#[derive(Default)]
pub struct TransitionIsModeled {
    cache: OnceCell<BTreeMap<String, ()>>,
}

impl TransitionIsModeled {
    fn modeled(&self, evidence: &Evidence) -> Result<&BTreeMap<String, ()>, Unverifiable> {
        if let Some(cached) = self.cache.get() {
            return Ok(cached);
        }
        let paths = Paths::from(evidence);
        let source = evidence
            .workspace
            .read(&paths.transitions)
            .map_err(|e| Unverifiable::new(format!("transitions model is unreadable: {e}")))?;
        let mut index = BTreeMap::new();
        for line in source.lines().filter(|l| is_record(l)) {
            let cells: Vec<&str> = line.split('|').map(str::trim).collect();
            if let (Some(from), Some(command)) = (cells.first(), cells.get(1)) {
                index.insert(format!("{from}|{command}"), ());
            }
        }
        Ok(self.cache.get_or_init(|| index))
    }
}

impl gatecrate_harness::Criterion<ContractRow> for TransitionIsModeled {
    fn judge(&self, row: &ContractRow, evidence: &Evidence) -> Result<Vec<Finding>, Unverifiable> {
        let Some(identity) = row.identity() else {
            return Ok(Vec::new());
        };
        if self.modeled(evidence)?.contains_key(&identity) {
            return Ok(Vec::new());
        }
        Ok(vec![Finding::new(
            row.location(),
            "a transition in the interaction model for this state and command",
            "no modeled transition".to_string(),
        )
        .remedy("model the transition first, or drop the contract if the command is gone")])
    }
}

/// 基準 — 実装と挙動テストの証拠が実在し、目印が生きていること。
pub fn evidence_is_alive(
    row: &ContractRow,
    evidence: &Evidence,
) -> Result<Vec<Finding>, Unverifiable> {
    let mut findings = Vec::new();
    for trace in [row.implementation(), row.behavior_test()].into_iter().flatten() {
        match evidence.workspace.read(trace.path) {
            Err(_) => findings.push(
                Finding::new(
                    row.location(),
                    format!("{} file {} to exist", trace.role, trace.path),
                    "file is absent".to_string(),
                )
                .remedy("point the contract at the file that carries the behavior now"),
            ),
            Ok(content) if !content.contains(trace.locator) => findings.push(
                Finding::new(
                    row.location(),
                    format!("`{}` to be present in {}", trace.locator, trace.path),
                    format!("{} locator has drifted or disappeared", trace.role),
                )
                .remedy("rename the contract's locator to match the code, or restore the behavior"),
            ),
            Ok(_) => {}
        }
    }
    Ok(findings)
}

/// 整合 — 同じ state+command の契約が重複しないこと。
pub struct ContractsAreUnique;

impl Coherence<ContractRow> for ContractsAreUnique {
    fn judge_together(
        &self,
        rows: &[ContractRow],
        _evidence: &Evidence,
    ) -> Result<Vec<Finding>, Unverifiable> {
        let mut seen: BTreeMap<String, usize> = BTreeMap::new();
        let mut findings = Vec::new();
        for row in rows {
            let Some(identity) = row.identity() else {
                continue;
            };
            match seen.get(&identity) {
                Some(first) => findings.push(
                    Finding::new(
                        row.location(),
                        "one contract per state and command",
                        format!("already contracted at line {first}"),
                    )
                    .remedy("merge the rows; two contracts for one command hide which test guards it"),
                ),
                None => {
                    seen.insert(identity, row.line);
                }
            }
        }
        Ok(findings)
    }
}

/// 整合 — 実装に置かれたマーカーが必ず契約を持つこと（台帳の取りこぼしを逆から突く）。
pub struct MarkedCommandsAreContracted;

impl Coherence<ContractRow> for MarkedCommandsAreContracted {
    fn judge_together(
        &self,
        rows: &[ContractRow],
        evidence: &Evidence,
    ) -> Result<Vec<Finding>, Unverifiable> {
        let paths = Paths::from(evidence);
        let files = evidence.workspace.walk(&paths.source_root).map_err(|e| {
            Unverifiable::new(format!("source root is unreadable: {e}")).remedy(format!(
                "set INTERACTION_SOURCE_ROOT to the directory holding implementation sources (now: {})",
                paths.source_root
            ))
        })?;

        let contracted: Vec<&str> = rows.iter().filter_map(ContractRow::command).collect();
        let mut findings = Vec::new();
        let mut reported: Vec<String> = Vec::new();

        for file in files {
            let name = file.to_string_lossy().to_string();
            let Ok(content) = evidence.workspace.read(&name) else {
                continue;
            };
            for command in markers_in(&content) {
                if contracted.contains(&command.as_str()) || reported.contains(&command) {
                    continue;
                }
                reported.push(command.clone());
                findings.push(
                    Finding::new(
                        format!("{name} (marker `{command}`)"),
                        "a contract for every command marked in the implementation",
                        "the marker has no contract".to_string(),
                    )
                    .remedy("add the contract row, or remove the marker if the command is gone"),
                );
            }
        }
        Ok(findings)
    }
}

fn markers_in(content: &str) -> Vec<String> {
    content
        .lines()
        .filter_map(|line| line.split_once(MARKER))
        .map(|(_, rest)| {
            rest.trim_start()
                .chars()
                .take_while(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || *c == '_' || *c == '-')
                .collect()
        })
        .filter(|command: &String| !command.is_empty())
        .collect()
}

pub fn gate() -> Gate<ContractLedger> {
    Gate::new(INTENT, ContractLedger)
        .checking(row_is_complete as fn(&ContractRow, &Evidence) -> _)
        .checking(TransitionIsModeled::default())
        .checking(evidence_is_alive as fn(&ContractRow, &Evidence) -> _)
        .ensuring(ContractsAreUnique)
        .ensuring(MarkedCommandsAreContracted)
}
