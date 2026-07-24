//! gatecrate CLI — 層の外側。引数と実環境をハーネスに渡し、報告を exit code に翻訳する。

use clap::{Parser, Subcommand};
use gatecrate_harness::evidence::{Evidence, Settings, Workspace};
use gatecrate_harness::report;
use std::io;
use std::process::ExitCode;

mod real;
mod render_viewer;

#[derive(Parser)]
#[command(name = "gatecrate", version, about = "Portable CI / quality-gate harness")]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Subcommand)]
enum Command {
    /// Run a quality gate against the repository.
    Check {
        #[command(subcommand)]
        gate: CheckGate,
    },
    /// Project living-model sources (.es/.cmap/.cld) to views.
    Es {
        #[command(subcommand)]
        projection: EsProjection,
    },
}

#[derive(Subcommand)]
enum EsProjection {
    /// Render a self-contained interactive HTML viewer to stdout.
    RenderHtml {
        /// Sources, classified by extension: .es (as-is, then to-be), .cmap, .cld, .md ...
        #[arg(value_name = "FILE")]
        files: Vec<String>,
    },
}

#[derive(Subcommand)]
enum CheckGate {
    /// Every change declares which architectural decisions it reviewed.
    AdrReview {
        /// Revision the change set is measured against.
        #[arg(value_name = "BASE")]
        base: Option<String>,
    },
    /// Every contracted interaction reaches implementation and a behavior test.
    InteractionTraceability {
        /// Contracts ledger (overrides INTERACTION_CONTRACTS).
        #[arg(long, value_name = "PSV")]
        contracts: Option<String>,
        /// Interaction model transitions (overrides INTERACTION_TRANSITIONS).
        #[arg(long, value_name = "PSV")]
        transitions: Option<String>,
        /// Directory scanned for implementation markers (overrides INTERACTION_SOURCE_ROOT).
        #[arg(long, value_name = "DIR")]
        source_root: Option<String>,
    },
}

fn main() -> ExitCode {
    let cli = Cli::parse();
    match cli.command {
        Command::Check { gate } => run_check(gate),
        Command::Es {
            projection: EsProjection::RenderHtml { files },
        } => render_viewer::run(&files),
    }
}

fn run_check(gate: CheckGate) -> ExitCode {
    let workspace = match real::GitWorkspace::discover() {
        Ok(w) => w,
        Err(message) => {
            eprintln!("gatecrate: {message}");
            return ExitCode::from(report::UNVERIFIABLE);
        }
    };
    let history = real::GitHistory::new(workspace.root().to_path_buf());

    match gate {
        CheckGate::AdrReview { base } => {
            let mut settings = Settings::from_env();
            if let Some(base) = base {
                settings = settings.overriding("ADR_REVIEW_BASE", base);
            }
            let evidence = Evidence {
                workspace: &workspace,
                history: &history,
                settings: &settings,
            };
            let gate = gatecrate_gates::adr_review::gate();
            let verdict = gate.inspect(&evidence);
            emit(report::report(gate.intent(), verdict))
        }
        CheckGate::InteractionTraceability {
            contracts,
            transitions,
            source_root,
        } => {
            let mut settings = Settings::from_env();
            for (key, value) in [
                ("INTERACTION_CONTRACTS", contracts),
                ("INTERACTION_TRANSITIONS", transitions),
                ("INTERACTION_SOURCE_ROOT", source_root),
            ] {
                if let Some(value) = value {
                    settings = settings.overriding(key, value);
                }
            }
            let evidence = Evidence {
                workspace: &workspace,
                history: &history,
                settings: &settings,
            };
            let gate = gatecrate_gates::interaction_traceability::gate();
            let verdict = gate.inspect(&evidence);
            emit(report::report(gate.intent(), verdict))
        }
    }
}

fn emit(report: report::Report) -> ExitCode {
    match report.emit(&mut io::stdout(), &mut io::stderr()) {
        Ok(code) => ExitCode::from(code),
        Err(_) => ExitCode::from(report::UNVERIFIABLE),
    }
}
