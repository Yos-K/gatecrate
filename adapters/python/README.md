# Python adapter (uv)

The second stack adapter, added to prove the kit's core/adapter boundary is genuinely
stack-agnostic. It reuses the **same core hygiene scripts unchanged** (conventional PR title,
per-file line limit, committed-secret scan) and adds two Python-specific gates run via `uv`:

| Script | Gate |
|---|---|
| `scripts/run-tests.sh` | `pytest` with a coverage floor (`--cov-fail-under`) |
| `scripts/run-mutation.sh` | `mutmut` mutation score against a floor |

Validated end to end: a Python consumer wired with this adapter ran all three jobs green on a
real pull_request (`fitness` + `test` + `mutation`), with the core scripts byte-identical to the
android-jvm consumer's.

## Required config (`harness.config.sh`)

```sh
FILE_LINE_NAMES="*.py *.sh"   # so the core line-limit gate scans Python
COVERAGE_SOURCE=src
COVERAGE_THRESHOLD=80
MUTATION_THRESHOLD=85         # set at/just-below the achieved score; never lower it
```

`pyproject.toml` carries the mutation target (and excludes low-value modules — the analog of
EXCLUDED_CLASSES):

```toml
[tool.mutmut]
source_paths = ["src/probe/discount.py"]

[tool.pytest.ini_options]
testpaths = ["tests"]
norecursedirs = ["mutants", ".venv", "build"]
```

## Porting frictions found (and how they are handled)

Building the Python mutation gate surfaced real differences from the JVM/PITest gate — useful
data on what "portable" actually costs:

1. **No clean threshold-exit.** PITest has `--mutationThreshold`; `mutmut run` exits 0 even with
   survivors. So `run-mutation.sh` reads `mutmut export-cicd-stats` (a JSON of killed/survived/
   total) and enforces the floor itself.
2. **`mutants/` pollutes pytest collection.** mutmut writes a working copy of the project under
   `mutants/`, so pytest sees duplicate test modules and errors on collection. Fixed with
   `testpaths`/`norecursedirs` in `pyproject.toml` (so the test gate is order-independent).
3. **Consumer must be a git repo.** Like every consumable script, the root is resolved with
   `git rev-parse`; the non-git fallback assumes the kit's layout depth. Run inside a git repo.

## Prerequisites

`uv` on PATH (the CI installs it via `astral-sh/setup-uv`). uv fetches its own Python, so no
separate `setup-python` is needed.
