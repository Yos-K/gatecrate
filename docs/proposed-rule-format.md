# Proposed-Rule Record Format

## What this document is for

The domain-knowledge loop turns behaviour an agent observes (during exploratory
testing, fuzzing, or property-based testing) into durable, machine-enforced rules.
Two artifact formats carry that work:

1. **proposed-rule** — one record per observed behaviour, classified and then put
   through a human gate that decides whether the behaviour is *intended* or a
   *defect*.
2. **traceability table** — tracks that every approved rule lands in *both* the
   design layer (a formal-spec assertion) and the implementation layer (a test),
   so a half-landed rule cannot be silently lost.

Follow these formats and each step's output can be checked mechanically: a record
is either complete or it is not; a rule is either fully landed or it is flagged.

The core invariant is the **human intent/defect gate**: an agent may *observe* and
*propose*, but only a human decides whether an observed behaviour is the intended
specification or a defect to fix. The machinery never makes that call.

---

## Format 1: proposed-rule

A proposed-rule is the record an agent creates the moment it observes a behaviour
worth deciding on. It states the observation as a fact (no speculation), cites the
evidence to reproduce it, flags any conflict with existing knowledge, and waits in
`proposed` status until a human moves it through the gate.

### Field definitions

| Field | Required | Meaning |
|-------|----------|---------|
| `rule_id` | yes | `DR-{YYYY}-{NNN}` (e.g. `DR-2026-001`). Stable identifier. |
| `scenario_id` | yes | The exploration scenario that surfaced it (links to the scenario log). |
| `observed_behavior` | yes | The behaviour stated as an observed fact. No speculation. |
| `evidence` | yes | What reproduces it: seed, action sequence, logs, repro command. |
| `glossary_conflict` | yes | Conflict with a glossary term: `yes` / `no` / `unverified` (state what verification needs). |
| `spec_conflict` | yes | Conflict with an existing formal-spec assertion: `yes` / `no` / `unverified`. |
| `status` | yes | `proposed` / `approved-intent` / `approved-defect` / `rejected`. |
| `approver` | on decision | The human who decided. Non-delegable. |
| `approved_at` | on decision | ISO 8601 date. |
| `spec` | after approval | The rule written in the specification mini-language (see below). |
| `reject_reason` | on rejection | Why it was rejected. |

`glossary_conflict` and `spec_conflict` exist so a proposed rule cannot quietly
contradict knowledge the project already committed to. An `unverified` value is
allowed but must say what checking it requires — never leave it blank or guessed.

### status — the human intent/defect gate

```
proposed ──► approved-intent   (human: "this IS the intended spec" → encode as a rule)
         ──► approved-defect   (human: "this is a DEFECT" → fix it; rule guards the fix)
         ──► rejected          (human: "not a rule" → record reject_reason)
```

- An agent may only ever set `status: proposed`. It cannot self-approve.
- `approved-intent`: the behaviour is correct and becomes part of the spec.
- `approved-defect`: the behaviour is wrong; the rule pins the *intended* behaviour
  so the fix is regression-guarded.
- Both approved kinds land in the traceability table (Format 2); `rejected` does not.

### Specification mini-language (notations used here)

```
invariant "..."          — an invariant (a condition that must always hold)
policy "..." when Event   — a policy (automatic handling triggered by an event)
value Name { ... }        — a value-object definition
error Name "..."          — an error definition
```

These four notations are self-contained here. For the full grammar see the
project's specification-language reference.

### Example — `proposed` state

```yaml
rule_id: DR-2026-001
scenario_id: SC-roundtrip-001
observed_behavior: >
  Persisting an unrecognised code 'abc' and restoring it yields the
  UNKNOWN state (fail-closed): the persist→restore round trip degrades
  an invalid code to UNKNOWN rather than throwing.
evidence:
  seed: "pbt seed=-3141592"
  action_sequence: [persistRoundTrip(code='abc'), restore]
  repro_command: "sh run-property-tests.sh  # seed fixed in the harness"
glossary_conflict: no
spec_conflict: no
status: proposed
```

### Example — `approved-intent` state

```yaml
rule_id: DR-2026-001
# ... (fields above, plus:)
status: approved-intent
approver: <human approver>
approved_at: "2026-06-08"
spec: |
  invariant "only the PURCHASED state grants the privileged capability"
  invariant "a persist→restore round trip preserves state (incl. UNKNOWN→UNKNOWN)"
  # Quality L2: invariants are stated, so tests are derivable.
```

---

## Format 2: traceability table

### Purpose

One rule must land twice: as a **design-layer assertion** and as an
**implementation-layer test**. The table makes both landings checkable. If either
is missing, the row is "not landed" and is surfaced for action — a rule that lives
only in a test (or only in an assertion) is easy to lose during refactors.

### Table structure

```
scenario_id  →  rule_id  →  assertion name  →  test name
```

### Column definitions

| Column | Meaning |
|--------|---------|
| Scenario ID | Assigned during exploration (`SC-{cluster}-{NNN}`). |
| Rule ID | The proposed-rule's `rule_id`. |
| Approval kind | `intent` / `defect`. |
| Assertion name | Name of the assertion in the formal-spec file. Not landed: `—`. |
| Spec file | Path to the file the assertion lives in. |
| Test name | The test method name. Not landed: `—`. |
| Test file | Path to the file the test lives in. |
| Status | `both landed` / `assertion only` / `test only` / `test only (no design layer needed)` / `not landed`. |
| Comment | Optional. For `test only (no design layer needed)`, the reason is required. |

### Example

| Scenario ID | Rule ID | Kind | Assertion name | Spec file | Test name | Test file | Status | Comment |
|-------------|---------|------|----------------|-----------|-----------|-----------|--------|---------|
| SC-roundtrip-001 | DR-2026-001 | intent | RoundTripPreservesState | round-trip.spec | `roundTripPreservesState` | RoundTripTest | both landed | |
| SC-roundtrip-002 | DR-2026-002 | defect | — | — | `ackGrantsCapability` | RoundTripTest | test only (no design layer needed) | simple value check; no assertion needed |
| SC-roundtrip-003 | DR-2026-003 | intent | OnlyPurchasedGrants | round-trip.spec | — | — | assertion only | |

### Management rules

1. **Definition of done**: no row is `not landed` or `assertion only`.
2. **Not-landed handling**: surface it as action-required (it is a known gap).
3. **When to add a row**: when a proposed-rule becomes approved, add the row
   immediately with status `not landed` as a placeholder.
4. **Comment column**: when no assertion is needed by design (a simple rule covered
   by an example test), use `test only (no design layer needed)` and record why.

---

## Storage and update timing

| Artifact | Location | Updated when |
|----------|----------|--------------|
| proposed-rule | `docs/exploration-sessions/{YYYY-MM-DD}/proposed-rules.yaml` | At the classification gate; again on approval. |
| traceability table | `docs/exploration-sessions/{YYYY-MM-DD}/traceability.md` | As each landing (assertion / test) is made. |

Keeping one directory per session means each pilot run's discovery count and
approval outcomes double as measurement data for deciding whether to make the loop
a permanent part of the workflow.
