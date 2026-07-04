# Documenting the rules that drive tests and model checks

Tests and model checks both verify the same thing: a **rule** (an invariant or a policy). When the
rule lives only in someone's head, the test and the model drift apart and a discovered behaviour
gets re-derived (or a bug gets frozen as spec). This doc is the convention for **writing the rule
down once**, as the single source that drives both a test and — where the risk warrants it — a model
check. Japanese: [spec-rules.ja.md](./spec-rules.ja.md).

It is the **specify** step of the domain-knowledge-deepening loop in
[test-selection-roi.md](./test-selection-roi.md): explore → classify (intent/defect) → **specify a
rule** → reflect into a test + a model → fix the code. Broaden
([design/expansion-loop.md](./design/expansion-loop.md)) proposes *which technique*; this doc says
how to record the *rule* that technique verifies.

## Where rules live

One file per area in the consumer repo: `docs/spec/<area>.md`. Each rule has a stable ID (`R-<n>`),
so a test and a model assert can both cite it.

Scaffold from the shipped templates instead of hand-rolling: `templates/spec/` (an index +
`area.md` skeleton, plus `models/example.als.example` for an order/state rule's Alloy assert) and
`rule-doc-lanes.tsv.example` (at the repo root, not under `templates/` — the lane file for the
rule-doc-currency gate that keeps these docs from drifting from the code). The gatecrate-setup skill (Phase 6.5) wires them when the spec-driven loop
is adopted. For the richer "propose → classify intent/defect → approve" workflow (DR-ID records),
see [proposed-rule-format.md](./proposed-rule-format.md); the `spec-author` TAKT persona
(`templates/takt/personas/`) automates the specify→reflect step.

## The mini-language (carry it, don't depend on a tool)

A rule is one short line in a tiny, language-agnostic notation:

| Form | Meaning | Example |
|---|---|---|
| `R-1 invariant "..."` | a condition that must always hold | `R-1 invariant "active is a member of tabs, or none"` |
| `R-2 policy "..." when <Event>` | an automatic consequence of an event | `R-2 policy "close re-activates the last tab" when TabClosed` |
| `R-3 error <Name> "..."` | a named failure / forbidden state | `R-3 error DuplicateTab "a tab id may not be opened twice"` |

Keep the description in domain words, not code. The ID is what the test and the model reference.

## 1 rule = 2 reflections

Each kept rule is reflected into **both** layers, so the model never drifts ahead of the code:

| Reflection | Layer | Role |
|---|---|---|
| an implementation **test** (example / PBT / stateful PBT) | implementation | a rejection signal on the real code, fired every PR in CI |
| a model **assert** (Alloy / TLA+) | design | an exhaustive state-space check: "can any operation order break R-n?" |

**When is the model reflection warranted?** Not for every rule. Follow test-selection-roi: an
**order/state or concurrency** rule earns a model assert (exhaustive ordering is where a model pays);
a pure **input-space invariant** needs only the test (a model adds the model-code gap for no gain).
So: every rule → a test; an ordering/concurrency rule → also a model assert.

## Traceability

Make the chain readable end to end, so a reader can jump rule → test → model:

```
R-1  invariant "active is a member of tabs, or none"
  ├ test:   tabset_active_is_always_a_member   (stateful PBT, src/state.rs)
  └ assert: ActiveIsMember                      (Alloy, spec/tabset.als)
```

Record it next to the rule (`R-1 → test:… / assert:…`). A rule with no reflection is a TODO, not a
spec; a test/assert with no rule ID is unmoored — give it one.

## The intent-vs-defect gate (the one human step)

A rule derived from how the code **currently behaves** must be classified by a human as **intent or
defect** before it is canonized. Writing a test for observed-but-wrong behaviour freezes the bug as
spec (the characterization trap). So a freshly-discovered rule starts as a **candidate** (`R-? (draft,
needs intent/defect classification)`); a human promotes it to a real rule — or files the behaviour as
a defect to fix — before the reflections are locked into CI.

**Pending reflections must be SKIPPED, not just "unmerged".** A scaffolded test under an
auto-discovered path is run by the adapters' broad commands (`cargo test`, `pytest`, `go test ./...`,
`vitest`) regardless of CI wiring — so a stub would turn PRs red, or a green stub would canonize
current behaviour, before the human gate. Scaffold the pending test skipped/ignored (Rust `#[ignore]`,
pytest `@pytest.mark.skip`, Go `t.Skip`, vitest `it.skip`) citing the rule; the human removes the skip
on approval. The Alloy assert runs manually, so it is already out of CI. **The scaffold must also
COMPILE** — an ignored test is still built (`cargo test`/`go test` compile every test file before
skipping), so a non-compiling stub breaks the build red just like a failing one; keep the body minimal
and compiling (a `todo!()`, or assertions confirmed to build).

## How it fits the loop

```
implement code
  → Broaden detects a risk shape and proposes a technique
    → write the RULE here (mini-language, ID, draft until human-classified)
      → 1 rule = 2 reflections: scaffold the test (+ a model assert if order/concurrency)
        → human classifies intent/defect, approves; reflections go green in CI
  → as code grows, rules accumulate, and tests + models grow with them
```

The rule is the single source; the test and the model are its two shadows. This is what lets *both*
grow together as implementation proceeds, instead of a test suite and a model drifting apart.
