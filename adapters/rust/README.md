# Rust adapter

Stack adapter for Rust (cargo). Reuses the core hygiene scripts unchanged and adds a test gate:

| Script | Gate |
|---|---|
| `scripts/run-tests.sh` | `cargo llvm-cov --fail-under-lines` (tests + coverage floor) |

Validated end to end: a Rust consumer ran `fitness` + `test` green on a real pull_request, core
scripts byte-identical to every other stack's. `cargo-llvm-cov` has a clean threshold-exit
(`--fail-under-lines`), so no parsing wrapper is needed (unlike the Python mutmut gate).

## Config (`harness.config.sh`)

```sh
FILE_LINE_NAMES="*.rs *.sh"
COVERAGE_THRESHOLD=90
```

CI installs `cargo-llvm-cov` (taiki-e/install-action) and the `llvm-tools-preview` component.

## Mutation (shipped)

`scripts/run-mutation.sh` runs [cargo-mutants](https://github.com/sourcefrog/cargo-mutants), which
exits non-zero if any mutant survives — a clean gate, no threshold parsing. Validated green on a
real pull_request (all mutants caught). CI installs `cargo-mutants` via taiki-e/install-action.
Exclude low-value mutants in `Cargo.toml` `[package.metadata.mutants]`.
