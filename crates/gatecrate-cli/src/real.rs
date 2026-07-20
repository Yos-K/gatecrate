//! 第3層の実装 — 実ファイルシステムと実 git。プロセス起動はここだけに閉じる。

use gatecrate_harness::evidence::{Commit, CommitId, History, Lookup, LookupError, Workspace};
use std::path::{Path, PathBuf};
use std::process::Command;

fn git(root: &Path, args: &[&str]) -> Lookup<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(args)
        .output()
        .map_err(|e| LookupError::Failed(format!("cannot run git: {e}")))?;
    if !output.status.success() {
        return Err(LookupError::NotFound(format!("git {}", args.join(" "))));
    }
    String::from_utf8(output.stdout)
        .map_err(|e| LookupError::Failed(format!("git produced non-UTF-8 output: {e}")))
}

pub struct GitWorkspace {
    root: PathBuf,
}

impl GitWorkspace {
    pub fn discover() -> Result<Self, String> {
        let cwd = std::env::current_dir().map_err(|e| format!("cannot read cwd: {e}"))?;
        let root = git(&cwd, &["rev-parse", "--show-toplevel"])
            .map_err(|_| "not inside a git repository".to_string())?;
        Ok(Self {
            root: PathBuf::from(root.trim_end()),
        })
    }
}

impl Workspace for GitWorkspace {
    fn root(&self) -> &Path {
        &self.root
    }

    fn exists(&self, path: &str) -> bool {
        self.root.join(path).is_file()
    }

    fn read(&self, path: &str) -> Lookup<String> {
        std::fs::read_to_string(self.root.join(path))
            .map_err(|e| LookupError::NotFound(format!("{path}: {e}")))
    }

    fn walk(&self, dir: &str) -> Lookup<Vec<PathBuf>> {
        let base = self.root.join(dir);
        let mut found = Vec::new();
        collect(&base, &mut found)
            .map_err(|e| LookupError::NotFound(format!("{dir}: {e}")))?;
        found.sort();
        Ok(found)
    }
}

fn collect(dir: &Path, out: &mut Vec<PathBuf>) -> std::io::Result<()> {
    for entry in std::fs::read_dir(dir)? {
        let path = entry?.path();
        if path.is_dir() {
            collect(&path, out)?;
        } else {
            out.push(path);
        }
    }
    Ok(())
}

pub struct GitHistory {
    root: PathBuf,
}

impl GitHistory {
    pub fn new(root: PathBuf) -> Self {
        Self { root }
    }
}

impl History for GitHistory {
    fn resolve(&self, revision: &str) -> Lookup<CommitId> {
        let id = git(&self.root, &["rev-parse", "--verify", &format!("{revision}^{{commit}}")])?;
        Ok(CommitId(id.trim_end().to_string()))
    }

    fn commits_between(&self, base: &CommitId, head: &str) -> Lookup<Vec<Commit>> {
        let range = format!("{}..{head}", base.0);
        let ids = git(&self.root, &["rev-list", "--reverse", &range])?;
        let mut commits = Vec::new();
        for id in ids.split_whitespace() {
            let message = git(&self.root, &["show", "-s", "--format=%B", id])?;
            let subject = message.lines().next().unwrap_or("").to_string();
            commits.push(Commit {
                id: CommitId(id.to_string()),
                subject,
                message,
            });
        }
        Ok(commits)
    }

    fn read_at(&self, commit: &CommitId, path: &str) -> Lookup<String> {
        git(&self.root, &["show", &format!("{}:{path}", commit.0)])
    }

    fn exists_at(&self, commit: &CommitId, path: &str) -> bool {
        git(&self.root, &["cat-file", "-e", &format!("{}:{path}", commit.0)]).is_ok()
    }
}
