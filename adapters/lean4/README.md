# Lean4 adapter (lake)

Stack adapter for Lean 4. Reuses the core hygiene scripts unchanged and adds a build gate:

| Script | Gate |
|---|---|
| `scripts/run-tests.sh` | `lake build` — typecheck + proof check |

Validated end to end: a Lean4 consumer ran `fitness` + `build` green on a real pull_request, core
scripts byte-identical to every other stack's.

## Why build is the gate (not coverage/mutation)

Lean 4 is a proof assistant: `lake build` checks every definition and **every proof**. The probe's
`example : apply 100 20 = some 80 := by decide` lines are proofs verified at build time — if one
were false, the build fails. So for a theorem-prover stack the meaningful gate is the build itself;
coverage and mutation (which assume example-based tests over runtime behaviour) do not apply.

## Config

`harness.config.sh` sets `FILE_LINE_NAMES="*.lean *.sh"`. CI installs `elan` (the Lean toolchain
manager); the pinned version comes from the project's `lean-toolchain` file.
