# ADR-0002: Port by structural complexity of the judgment, not by layer

Status: Accepted

## Decision

The boundary between Rust and shell is drawn by **whether the judgment logic has structure**
— a parser, graph traversal, or set operations — not by whether a script is a gate or a
projection:

- **Rust**: scripts whose judgment parses a format, walks a graph, or reasons over sets.
  Working heuristic: **an embedded awk program over ~30 lines is a porting signal**.
- **Shell, as the correct choice (not a freeze)**: checks that are one regex or a file-existence
  test. They keep the kit's copy-one-file consumption model and remain compatible with
  `probe-gate-liveness`, which copies a script standalone into a throwaway repository —
  a shimmed gate cannot be probed that way (a missing binary is an explicit exit 2, so it
  never fakes ALIVE, but it also cannot prove liveness).
- The two Rust gates that already exist (adr-review, interaction-traceability) were ports made
  to validate the harness archetype. They serve **the kit's own CI**; consumers keep the shell
  versions. The dual implementation is managed by this role split and by both sides having
  independent behavior tests.

Migration invariants (unchanged from the port plan): output format and exit contract are
frozen; the existing shell behavior tests are the acceptance tests; one script at a time.

## Alternatives Considered

1. Port everything to Rust.
2. Freeze by layer: keep all gates in shell, port only projections/metrics (the boundary
   originally proposed in the port plan review).
3. Status quo: no further porting.
4. This decision: port by structural complexity of the judgment.

## Why This Decision

- Two agents, on different days and different projects, hit the same defect classes in shell
  — variable-expansion accidents, silently no-op `sed` producing false test verdicts,
  line-oriented parsing accepting structurally wrong input — and **shellcheck -S error caught
  none of them**. All occurred in structured-judgment code, none in one-regex checks.
- The repository inventory agrees: the painful scripts are exactly the awk-dense ones
  (measure-modularity 10 awk calls, es-coverage 8, es-render-html was 800 lines).
- The diagnosis behind the pain is "structured data handled with line-oriented tools", so the
  cure is typed parsing where structure exists — and nothing where it does not.

## Why Alternatives Were Rejected

- **Port everything**: breaks the copy-one-file consumption model and probe compatibility for
  simple gates that gain nothing from types; adds a toolchain requirement consumers never
  asked for.
- **Freeze by layer**: misclassifies both directions — es-lint is a gate but is parser-heavy
  (Rust-worthy), while check-adr-review is a gate with thin structure (shell suffices for
  consumers). An independent consumer-side review surfaced this error.
- **Status quo**: leaves a demonstrated, shellcheck-invisible defect class in the code that
  judges models and metrics.

## Reconsider When

- probe-gate-liveness learns to inject through a shim/binary (removes the probe constraint).
- A consumer explicitly wants the Rust gates (revisits the role split of the two ports).
- A script classified "shell, simple" grows structured judgment (the awk-30-line signal fires).
- The two implementations of the archetype-validation gates drift in observed behavior
  (forces choosing one).
