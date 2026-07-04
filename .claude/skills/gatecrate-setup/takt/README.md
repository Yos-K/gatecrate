# Optional: drive the mutation-config iteration with TAKT

The gatecrate-setup skill's "8->10" mutation-config loop (set EXTRA_MAIN_SOURCES, EXCLUDED_CLASSES,
MUTATION_THRESHOLD by running the gate and reading the result) is regular and terminates on a
machine-checkable gate. [TAKT](https://github.com/nrslib/takt) can orchestrate it so the loop is
reproducible and auditable instead of hand-driven.

## Why this shape (and not a state machine)

TAKT step transitions (`rules`) cannot branch on a shell exit code — only on AI/text conditions.
But a **`type: command` quality gate** is machine-executed by TAKT: it runs a script after the
step and passes only on exit 0; on failure it re-invokes the **same** step with the exit code and
sanitized stdout/stderr. Our loop is exactly that: one `derive` step, guarded by a command gate
running `run-mutation-tests.sh`. The deterministic gate is the loop's exit condition; the persona
supplies the judgment (SURVIVED -> add a test vs NO_COVERAGE -> exclude). See
[design-rationale in the workflow header](./harness-config-derive.yaml).

## Files

| File | Role |
|---|---|
| `harness-config-derive.yaml` | the single-step + command-gate workflow |
| `personas/gatecrate-setup.md` | the deriver persona (the judgment TAKT does not supply) |

## Use it on a consumer

```sh
npm install -g takt                       # TAKT CLI (v0.46+ verified)
```

1. Create `~/.takt/config.yaml` (provider/model/language). `claude` uses the Claude Code CLI;
   `claude-sdk`/`codex` use an API key (`TAKT_ANTHROPIC_API_KEY`) with no CLI:
   ```yaml
   provider: claude
   model: sonnet
   language: ja
   ```
2. In the consumer repo, place this workflow at `.takt/workflows/harness-config-derive.yaml`
   (TAKT resolves a workflow by `<name>.yaml`, NOT `.workflow.yaml`) and the persona at
   `.takt/personas/gatecrate-setup.md`. Enable command gates in the consumer's `.takt/config.yaml`:
   ```yaml
   workflow_command_gates:
     custom_scripts: true
   ```
3. Prerequisites: `scripts/run-mutation-tests.sh` adopted, JDK 17 + curl on PATH, and
   `harness.config.sh` already carrying the mechanically-derived values (grep recipes in
   `../SKILL.md` Phase 4), with the iteration items left empty.
4. Run it non-interactively:
   ```sh
   takt -t "Converge harness.config.sh so the mutation gate exits 0; never lower the floor." \
     -w harness-config-derive --provider claude --model sonnet --pipeline --skip-git
   ```
   The `type: command` gate runs `run-mutation-tests.sh` after the step and re-invokes the agent
   with its exit code + triage until it exits 0; the agent fills EXTRA_MAIN_SOURCES /
   EXCLUDED_CLASSES and ratchets MUTATION_THRESHOLD.

## Status — executed end to end

Run on a pure-JVM consumer (provider `claude`, `--pipeline --skip-git`): TAKT machine-executed the
command gate (`build/mutation/` artifacts + session log confirm `run-mutation-tests.sh` ran),
the persona derived `EXTRA_MAIN_SOURCES=…/PriceFormatter.java` and excluded the i18n catalog with
code-cited reasoning and refused to lower the floor, and an independent re-run confirmed the gate
exits 0 (≈92%, 11/12 killed). Result: Success in one iteration (~3 min).

Two findings folded back in: the workflow file must be `<name>.yaml` (fixed); and the agent left
`MUTATION_THRESHOLD` at the default 79 instead of ratcheting to the achieved ~92, so a real
SURVIVED mutation stayed tolerated — the persona now requires raising the floor to the green score.

## Credits & license

[TAKT](https://github.com/nrslib/takt) is © Masanobu Naruse, **MIT License**. It is an optional
external tool (install via `npm install -g takt`) — gatecrate does not bundle its source. The
files in this directory (`harness-config-derive.yaml`, `personas/gatecrate-setup.md`, this README)
are gatecrate's own work, written to TAKT's workflow schema. See the repo-root
[THIRD_PARTY_NOTICES.md](../../../../THIRD_PARTY_NOTICES.md) for the full attribution.
