//! ハーネスの原型。
//!
//! シェルスクリプト群は「何を検出したいのか / 何を調べ何と比べるのか / どう調べるのか」を
//! 各スクリプトが独自に混ぜて書いていた。ここではそれを層として分け、層ごとに交換可能にする。
//!
//! ```text
//!   第1層 intent    何を検出したいのか（型・理由・検出しないことの宣言）
//!   第2層 population 何を調べるのか（母集団の決定）
//!         criterion  各対象が何と比べられるのか（判定基準）
//!         coherence  集合全体が満たすべき条件（重複禁止・逆引き）
//!   第3層 evidence   どうやって調べるのか（作業ツリー・履歴・設定＝唯一の副作用層）
//!   第4層 finding    観測と期待の差
//!   第5層 report     検出したあとどうするか（exit code・報告文の契約）
//! ```
//!
//! ハーネスにはもう1つの原型 Projection（源泉→モデル→ビュー）があり、そちらは検出を
//! 行わないため本 crate ではなく gatecrate-model / gatecrate-render が担う。

pub mod evidence;
pub mod finding;
pub mod gate;
pub mod intent;
pub mod report;

pub use evidence::{Commit, CommitId, Evidence, Settings, Workspace};
pub use finding::{Finding, Unverifiable, WhenNoSubjects};
pub use gate::{Coherence, Criterion, Gate, Population, Subject, Verdict};
pub use intent::{GateKind, Intent};
pub use report::{report, Report};
