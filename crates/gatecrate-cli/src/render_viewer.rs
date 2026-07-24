//! `gatecrate es render-html` — 素材ファイルの解決と読み込みだけを担う。
//!
//! 参照実装（es-render-html.sh）と同じ呼び出し契約:
//! 引数は拡張子で役割が決まり、`.es` の1つ目が AS-IS・2つ目が TO-BE。
//! `<モデル>.spec` が隣にあれば自動で読む。exit 1 = 引数不足、2 = ファイル欠落。

use gatecrate_model::cld::CausalLoopDiagram;
use gatecrate_model::cmap::ContextMap;
use gatecrate_model::es::EventModel;
use gatecrate_model::spec::CommandSpecs;
use gatecrate_render::{render, Materials};
use std::io::Write;
use std::path::Path;
use std::process::ExitCode;

const USAGE: &str =
    "usage: es-render-html.sh <asis.es> [tobe.es] [map.cmap] [loops.cld] [analysis.md ...]";

struct Sources {
    asis: String,
    tobe: Option<String>,
    cmap: Option<String>,
    cld: Option<String>,
    analyses: Vec<String>,
}

fn classify(files: &[String]) -> Option<Sources> {
    let mut asis = None;
    let mut tobe = None;
    let mut cmap = None;
    let mut cld = None;
    let mut analyses = Vec::new();
    for f in files {
        if f.ends_with(".cmap") {
            cmap = Some(f.clone());
        } else if f.ends_with(".cld") {
            cld = Some(f.clone());
        } else if f.ends_with(".md") {
            analyses.push(f.clone());
        } else if f.ends_with(".es") {
            if asis.is_none() {
                asis = Some(f.clone());
            } else if tobe.is_none() {
                tobe = Some(f.clone());
            }
        }
    }
    Some(Sources {
        asis: asis?,
        tobe,
        cmap,
        cld,
        analyses,
    })
}

fn fail(code: u8, message: &str) -> ExitCode {
    eprintln!("{message}");
    ExitCode::from(code)
}

fn read(path: &str, role: &str) -> Result<String, ExitCode> {
    if !Path::new(path).is_file() {
        return Err(fail(2, &format!("es-render-html: {role} not found: {path}")));
    }
    std::fs::read_to_string(path)
        .map_err(|e| fail(2, &format!("es-render-html: cannot read {path}: {e}")))
}

/// `<name>.es` の隣の `<name>.spec`（あれば）。
fn sibling_spec(es_path: &str) -> Option<String> {
    let path = format!("{}.spec", es_path.strip_suffix(".es").unwrap_or(es_path));
    Path::new(&path)
        .is_file()
        .then(|| std::fs::read_to_string(&path).ok())
        .flatten()
}

pub fn run(files: &[String]) -> ExitCode {
    let Some(sources) = classify(files) else {
        return fail(1, USAGE);
    };

    // 参照実装と同じ順で欠落を報告する（analysis → model → tobe → cmap → cld）
    for doc in &sources.analyses {
        if !Path::new(doc).is_file() {
            return fail(2, &format!("es-render-html: analysis md not found: {doc}"));
        }
    }
    let asis_source = match read(&sources.asis, "model") {
        Ok(s) => s,
        Err(code) => return code,
    };
    let mut materials = Materials {
        asis: EventModel::parse(&asis_source),
        asis_spec: sibling_spec(&sources.asis)
            .map(|s| CommandSpecs::parse(&s))
            .unwrap_or_default(),
        ..Materials::default()
    };
    if let Some(path) = &sources.tobe {
        match read(path, "tobe") {
            Ok(s) => {
                materials.tobe = Some(EventModel::parse(&s));
                materials.tobe_spec = sibling_spec(path)
                    .map(|s| CommandSpecs::parse(&s))
                    .unwrap_or_default();
            }
            Err(code) => return code,
        }
    }
    if let Some(path) = &sources.cmap {
        match read(path, "cmap") {
            Ok(s) => materials.context_map = Some(ContextMap::parse(&s)),
            Err(code) => return code,
        }
    }
    if let Some(path) = &sources.cld {
        match read(path, "cld") {
            Ok(s) => materials.causal_loops = Some(CausalLoopDiagram::parse(&s)),
            Err(code) => return code,
        }
    }
    for doc in &sources.analyses {
        match read(doc, "analysis md") {
            Ok(s) => materials.analyses.push(s),
            Err(code) => return code,
        }
    }

    let page = render(&materials);
    if std::io::stdout().write_all(page.as_bytes()).is_err() {
        return ExitCode::from(2);
    }
    ExitCode::SUCCESS
}
