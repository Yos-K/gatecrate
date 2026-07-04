# Haskell adapter (cabal)

Stack adapter for Haskell. Reuses the core hygiene scripts unchanged and adds a test gate:

| Script | Gate |
|---|---|
| `scripts/run-tests.sh` | `cabal test` (build + an exitcode-stdio test-suite) |

Validated end to end: a Haskell consumer ran `fitness` + `test` green on a real pull_request, core
scripts byte-identical to every other stack's. The test-suite is a plain `exitcode-stdio` Main with
no extra framework dependency, so it builds fast and reliably in CI.

## Config

`harness.config.sh` sets `FILE_LINE_NAMES="*.hs *.sh"`. The test-suite is declared in the `.cabal`.

## Coverage / mutation (extension)

Coverage via HPC (`cabal test --enable-coverage`, then parse the hpc summary and gate on a floor).
Mutation testing in Haskell is uncommon (MuCheck); coverage is the recommended extension.
