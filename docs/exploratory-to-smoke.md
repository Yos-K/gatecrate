# Turning exploratory UI findings into stable smoke checks

## Why this doc

Exploration finds weaknesses a fixed smoke test misses; the value is only captured when the finding
becomes a **stable regression check**. This doc gives a reusable pattern for that distillation, so the
resulting smoke does not silently rot when the UI's DOM order, labels, or layout change.

Concrete example (from `localmd-reader`): the L5 render smoke asserted a `Preview` **label was visible**
— but that did not prove the Raw/Preview switch actually **worked**. Exploration strengthened it to *tap*
`Preview` and assert rendered Markdown content; then found that documents with **multiple** previewable
code blocks made "which Preview?" ambiguous, and strengthened it again to target the second occurrence
and assert HTML preview content. Good lifecycle — but the fix was left **order-dependent**.

## The lifecycle (make it explicit)

```
exploratory finding  →  concrete regression check (assert behavior, not label)  →  exploration record updated
```

- **Assert the effect, not the affordance.** "a `Preview` label exists" is presence; "tapping `Preview`
  renders the expected preview content" is behavior. Only the latter proves the feature works and fails
  when it breaks.
- **Record what the exploration learned** (what was too weak, what it now asserts) next to the check, so
  the next explorer does not re-discover it.

## The locator stability ladder (prefer higher rungs)

When the check must locate a UI target, choose the most stable locator the app can offer:

1. **Stable identifier** (test tag / `content-desc` / resource-id) unique to the target — *preferred*.
   If the app cannot expose one, that is itself a finding: propose adding it.
2. **Unique visible text** — acceptable when the label is unambiguous on the screen.
3. **Text-occurrence index** ("tap the 2nd `Preview`") — **interim fallback only.** It works now but is
   fragile to DOM order / layout / label changes. If you use it: (a) comment it as a known fragility,
   (b) file/track a follow-up to expose a stable id, (c) keep the assertion on rendered content so a
   wrong-target tap still fails loudly.
4. **Coordinates** — avoid; last resort, most brittle.

## Contract test

Whatever the smoke does, a **contract test** should assert the smoke *includes* the strengthened
operations (tap-and-assert-content, not just label presence), so the regression check cannot be quietly
watered back down. Treat "the smoke only checks a label" as a defect the contract test rejects.

## Rule of thumb

Interim fragility (occurrence index) is acceptable **if it is visible and tracked**, not silent. Silent
truncation of coverage ("we tap the first match and hope") reads as "covered" when it is not — surface it.

## Interaction-storming completeness guard (`check-interaction-storming.sh`)

**Positioning: exploration itself is NOT a gate — the distilled state table's consistency IS.** UI
exploration finds "the user's flow cannot finish" defects (a dialog with no way to close, no way to
re-choose a folder). Running exploration in CI is heavy and flaky; instead, distill findings into a
machine-readable flow table and gate *that*:

```
# flow_id|state_id|event|available_commands|completion_command|escape_command|recovery_command|evidence
recent|recent-dialog|Recent files shown|open,close,clear|open|close|clear|src/Main.java,docs/session.md
```

The gate checks each state has **completion / escape / recovery** commands, that they are listed in
`available_commands`, and that `evidence` paths exist — reported with line numbers. Configure the table
path via `INTERACTION_FLOWS` in `harness.config.sh` (or pass as the first argument). Proven in a consumer
(localmd-reader) before generalization.
