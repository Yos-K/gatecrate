//! 第3層 — どうやって調査するか。副作用を持つのはこの層だけ。
//!
//! 母集団と判定基準がこの trait 越しにしか事実を得られないことで、ゲートの検査は
//! 実ファイルシステム・実 git なしに書ける（差し替えたテスト実装で全経路を通せる）。

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

#[derive(Debug)]
pub enum LookupError {
    NotFound(String),
    Failed(String),
}

impl std::fmt::Display for LookupError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LookupError::NotFound(w) => write!(f, "not found: {w}"),
            LookupError::Failed(w) => write!(f, "{w}"),
        }
    }
}

pub type Lookup<T> = Result<T, LookupError>;

/// リポジトリの作業ツリー。
pub trait Workspace {
    fn root(&self) -> &Path;
    fn exists(&self, path: &str) -> bool;
    fn read(&self, path: &str) -> Lookup<String>;
    /// 指定ディレクトリ配下のファイルを、リポジトリ相対パスの辞書順で列挙する。
    /// 相対に揃えるのは、報告に出る位置が実行環境で変わらないようにするため。
    fn walk(&self, dir: &str) -> Lookup<Vec<PathBuf>>;
}

/// バージョン履歴。ゲートは「宣言コミット時点の内容」を要求できる必要がある。
pub trait History {
    fn resolve(&self, revision: &str) -> Lookup<CommitId>;
    fn commits_between(&self, base: &CommitId, head: &str) -> Lookup<Vec<Commit>>;
    fn read_at(&self, commit: &CommitId, path: &str) -> Lookup<String>;
    fn exists_at(&self, commit: &CommitId, path: &str) -> bool;
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub struct CommitId(pub String);

#[derive(Clone, Debug)]
pub struct Commit {
    pub id: CommitId,
    pub subject: String,
    pub message: String,
}

impl Commit {
    /// トレーラ行（`Key: value`）を出現順に返す。
    pub fn trailers(&self, key: &str) -> Vec<&str> {
        let prefix = format!("{key}:");
        self.message
            .lines()
            .filter_map(|l| l.strip_prefix(&prefix))
            .map(|v| v.trim())
            .collect()
    }
}

/// 消費者固有の設定（harness.config.sh 由来の環境変数）。
/// 既定値をここで解決することで「未設定なら黙って skip」を構造的に防ぐ。
pub struct Settings(BTreeMap<String, String>);

impl Settings {
    pub fn from_env() -> Self {
        Self(std::env::vars().collect())
    }

    pub fn from_pairs<K: Into<String>, V: Into<String>>(
        pairs: impl IntoIterator<Item = (K, V)>,
    ) -> Self {
        Self(
            pairs
                .into_iter()
                .map(|(k, v)| (k.into(), v.into()))
                .collect(),
        )
    }

    pub fn get(&self, key: &str) -> Option<&str> {
        self.0.get(key).map(String::as_str).filter(|v| !v.is_empty())
    }

    pub fn or_default<'a>(&'a self, key: &str, fallback: &'a str) -> &'a str {
        self.get(key).unwrap_or(fallback)
    }

    /// 空文字を「明示的な無効化」として扱う設定項目のための取得。
    pub fn get_allowing_empty(&self, key: &str) -> Option<&str> {
        self.0.get(key).map(String::as_str)
    }

    /// 引数など、環境より強い指定で1項目だけ上書きする。
    pub fn overriding(mut self, key: &str, value: impl Into<String>) -> Self {
        self.0.insert(key.to_string(), value.into());
        self
    }

    pub fn flag(&self, key: &str, fallback: bool) -> bool {
        match self.get(key) {
            Some("true" | "1" | "yes") => true,
            Some("false" | "0" | "no") => false,
            _ => fallback,
        }
    }

    pub fn list(&self, key: &str, fallback: &str) -> Vec<String> {
        self.or_default(key, fallback)
            .split_ascii_whitespace()
            .map(str::to_string)
            .collect()
    }
}

/// ゲートが事実に触れるための唯一の窓口。
pub struct Evidence<'a> {
    pub workspace: &'a dyn Workspace,
    pub history: &'a dyn History,
    pub settings: &'a Settings,
}
