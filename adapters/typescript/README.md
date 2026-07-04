# TypeScript adapter

Stack adapter for TypeScript (npm + vitest). Reuses the core hygiene scripts unchanged and adds a
test gate:

| Script | Gate |
|---|---|
| `scripts/run-tests.sh` | `vitest run --coverage` with a line-coverage floor |

Validated end to end: a TypeScript consumer ran `fitness` + `test` green on a real pull_request,
core scripts byte-identical to every other stack's.

## Config (`harness.config.sh`)

```sh
FILE_LINE_NAMES="*.ts *.sh"
COVERAGE_THRESHOLD=90
```

The gate runs `vitest run --coverage` (json-summary reporter) and enforces the floor from
`coverage/coverage-summary.json`. Configure vitest's coverage `include`/`exclude` in
`vitest.config.ts` (the analog of EXCLUDED_CLASSES).

## Mutation (shipped)

`scripts/run-mutation.sh` runs [Stryker](https://stryker-mutator.io/) (`npx stryker run`), which
exits non-zero below the `break` threshold. Validated green on a real pull_request. The consumer
adds `@stryker-mutator/core` + `@stryker-mutator/vitest-runner` to devDependencies and a
`stryker.config.json` (`testRunner: vitest`, `thresholds.break`, `mutate` globs = the analog of
EXCLUDED_CLASSES).

Start from the shipped template — it bakes in the `break` threshold and the test-support
exclusions, so you do not re-derive them per project:

```sh
cp adapters/typescript/stryker.config.json.example <consumer>/stryker.config.json
```

> **Version compatibility (verify at setup, do not assume):** the Stryker vitest-runner must match
> your Vitest major. **Vitest 3 / 4 require `@stryker-mutator/*` ≥ 9** — the 8.x runner crashes on
> Vitest 4 (`Cannot destructure property 'moduleGraph' of 'project.server'`) and the gate then
> *silently never runs*. After install, **run `sh scripts/run-mutation.sh` once and confirm it
> prints a mutation score** (not a crash). A gate that exists but never executes gives false
> assurance — treat "the mutation gate actually runs" as part of setup, not a given.
>
> Exclude test-support files (`*fixtures.ts`, `*test-helpers.ts`) from the `mutate` globs so the
> score reflects production code, not test scaffolding.
