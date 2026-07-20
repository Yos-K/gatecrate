//! 差し替え可能な証拠層。ゲートの検査が実リポジトリを必要としないことを支える。

use gatecrate_harness::evidence::{Commit, CommitId, History, Lookup, LookupError, Workspace};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};

#[derive(Default)]
pub struct FakeWorkspace {
    files: BTreeMap<String, String>,
}

impl FakeWorkspace {
    pub fn file(mut self, path: &str, content: &str) -> Self {
        self.files.insert(path.to_string(), content.to_string());
        self
    }
}

impl Workspace for FakeWorkspace {
    fn root(&self) -> &Path {
        Path::new(".")
    }

    fn exists(&self, path: &str) -> bool {
        self.files.contains_key(path)
    }

    fn read(&self, path: &str) -> Lookup<String> {
        self.files
            .get(path)
            .cloned()
            .ok_or_else(|| LookupError::NotFound(path.to_string()))
    }

    fn walk(&self, dir: &str) -> Lookup<Vec<PathBuf>> {
        let prefix = format!("{}/", dir.trim_end_matches('/'));
        let found: Vec<PathBuf> = self
            .files
            .keys()
            .filter(|p| p.starts_with(&prefix))
            .map(PathBuf::from)
            .collect();
        if found.is_empty() && !self.files.keys().any(|p| p.starts_with(dir)) {
            return Err(LookupError::NotFound(dir.to_string()));
        }
        Ok(found)
    }
}

/// 履歴を見ないゲートのための証拠。呼ばれたら失敗するので、
/// 「履歴に触れていないこと」がテストで担保される。
pub struct NoHistory;

impl History for NoHistory {
    fn resolve(&self, revision: &str) -> Lookup<CommitId> {
        Err(LookupError::Failed(format!(
            "this gate must not consult history (asked for {revision})"
        )))
    }

    fn commits_between(&self, _base: &CommitId, _head: &str) -> Lookup<Vec<Commit>> {
        Err(LookupError::Failed(
            "this gate must not consult history".to_string(),
        ))
    }

    fn read_at(&self, _commit: &CommitId, path: &str) -> Lookup<String> {
        Err(LookupError::Failed(format!(
            "this gate must not consult history (asked for {path})"
        )))
    }

    fn exists_at(&self, _commit: &CommitId, _path: &str) -> bool {
        false
    }
}
