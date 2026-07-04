# Go adapter

Stack adapter for Go. Reuses the core hygiene scripts unchanged and adds a test gate:

| Script | Gate |
|---|---|
| `scripts/run-tests.sh` | `go test` with a line-coverage floor (`go tool cover`) |

Validated end to end: a Go consumer wired with this adapter ran `fitness` + `test` green on a
real pull_request, with the core scripts byte-identical to every other stack's.

## Config (`harness.config.sh`)

```sh
FILE_LINE_NAMES="*.go *.sh"
COVERAGE_THRESHOLD=90   # go test total line coverage floor
```

## Mutation (shipped)

`scripts/run-mutation.sh` runs [gremlins](https://github.com/go-gremlins/gremlins)
(`gremlins unleash --threshold-efficacy $MUTATION_THRESHOLD`), which exits non-zero below the
efficacy floor. Validated green on a real pull_request. CI installs gremlins via
`go install github.com/go-gremlins/gremlins/cmd/gremlins@latest`. Set `MUTATION_THRESHOLD` in
`harness.config.sh`.
