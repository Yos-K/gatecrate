# Code quality metrics harness

## Purpose

Lower the cost of changing code — especially for AI agents — by **measuring complexity and
coupling as numbers**, so refactoring can be prioritized by evidence rather than gut feel. This
page tells you what each metric measures, why it drives change cost, and which values should
trigger action.

The measure commands are **advisory** (not gates) and need no SDK or build step; the modularity
ratchet is the opt-in **prevention gate** built on top of them:

```sh
sh core/scripts/measure-complexity.sh        # cyclomatic / cognitive complexity, accidental-complexity proxy, duplication
sh core/scripts/measure-coupling.sh          # Ca/Ce/instability, SDP violations, Balanced Coupling, co-change
sh core/scripts/measure-modularity.sh        # Balanced Coupling 3D: strength x distance x volatility, RED/YELLOW verdicts
sh core/scripts/check-modularity-ratchet.sh  # GATE: rejects NEW balance violations not in modularity-baseline.tsv

## Why measure these (mapping to change cost)

| Metric | How it drives change cost |
|--------|---------------------------|
| Cyclomatic complexity (CC) | branch count = paths to test = reasoning combinations. Higher = more expensive to safely change |
| Cognitive complexity | nesting / flow-breaks = comprehension load. Higher = costlier to "read and correctly fix" |
| Accidental complexity (proxy) | complexity not essential to the domain. **Removable without changing behavior** = pure cost |
| Coupling (Balanced Coupling) | blast radius of a change. "Strongly depending on something that changes often" = more rework per change |

## Metric definitions

### Cyclomatic & cognitive complexity (measured directly by PMD)

`measure-complexity.sh` applies PMD's `CyclomaticComplexity` and `CognitiveComplexity`
(SonarSource definition) rules at `reportLevel=1` to every method to obtain a full distribution
(see `core/scripts/quality/complexity-ruleset.xml`).

| Band | CC (fitness S-01) | Cognitive (Sonar default 15) |
|------|-------------------|------------------------------|
| GREEN | ≤10 | ≤15 |
| YELLOW | 11–20 | 16–25 |
| RED | >20 | >25 |

Bands are configurable via `COMPLEXITY_CC_YELLOW/RED` and `COMPLEXITY_COG_YELLOW/RED`.

### Accidental complexity (no direct measurement — approximated by two proxies)

Accidental complexity (Brooks: complexity from the solution, not the problem) cannot be measured
mechanically. **So** it is approximated by two proxies, with their limits stated explicitly:

1. **Cognitive − cyclomatic difference (per method).**
   - Why it is a proxy: genuine domain branching shows up in both metrics roughly equally, but
     deep nesting, flow-breaks, and structural noise inflate only cognitive complexity. A method
     with a large difference is **likely reducible by behavior-preserving refactors (Extract
     Method etc.)** = accidental.
   - Limit: intrinsically complex algorithms (state machines) can also show a difference. The
     difference ranks *removal candidates*; it does not *prove* accidental complexity.
2. **Duplication (PMD CPD, ≥100 tokens by default).**
   - Duplication is pure accidental complexity the domain never asked for (multi-site edit cost =
     an agent's shotgun surgery). Threshold via `COMPLEXITY_CPD_MIN_TOKENS`.

### Coupling (a reduced implementation of vladikk's Balanced Coupling)

vladikk/modularity's "coupling load = strength × distance × volatility", reduced to something
measurable with no external tooling (git + awk only, no compile):

| Component | How this implementation measures it |
|-----------|-------------------------------------|
| Strength | import count between packages (`edges.tsv`) |
| Distance | package boundary in/out (reduced to a 2-value "different package = has distance") |
| Volatility | git change count over the last N days (default 90) on the depended-on side |

Four outputs:
- **Ca / Ce / instability I** (fitness D-01..D-03). Note: in a layered architecture, domain I≈0
  and presentation I≈1 are **healthy** (the D-03 "both ends = RED" band applies only to middle
  layers).
- **SDP violations**: depending on a more unstable package (Stable Dependencies Principle break).
  This is the concrete harm signal.
- **Balanced Coupling top edges**: strength × volatility, ordered by expected rework cost.
- **Co-change pairs**: files in different packages changed together frequently in one commit —
  hidden temporal coupling not visible in imports (default threshold 5 in the window).

### Modularity (full 3D Balanced Coupling — measure-modularity.sh + ratchet gate)

`measure-modularity.sh` evaluates every internal edge against vladikk's balance formula
`BALANCE = (STRENGTH XOR DISTANCE) OR NOT VOLATILITY` — strong coupling belongs close, distant
coupling must be weak, and either imbalance is tolerable if the depended-on side does not change:

| Dimension | How it is obtained | Why |
|-----------|--------------------|-----|
| Strength (qualitative) | **judgment layer**: the `modularity-review` skill (or a human) classifies each edge in `modularity-strength.tsv`, with evidence | how much knowledge two modules share is a semantic fact a script cannot measure |
| Distance | package-tree distance between src and dst (steps via the lowest common ancestor) | the further apart, the higher the socio-technical cost of co-evolving them |
| Volatility | git change count of the depended-on package (measure-coupling's window) | a stable dependency never exercises the coupling |

Strength levels are `contract(1) < model(2) < functional(3) < intrusive(4)` — ordered by how much
knowledge is shared. Edges with no classification yet are evaluated at the default level (`model`)
and reported as a work queue, so nothing is silently passed or silently blocked.

Verdicts: **RED** = strong × distant × volatile (the worst shape: every change of the dependee
ripples far and hard); **YELLOW** = weak × near × volatile (a boundary right next to a
frequently-changing neighbor — the split may not be worth its upkeep; merge candidate, never
blocks).

`check-modularity-ratchet.sh` (prevention gate) freezes existing REDs in a committed
`modularity-baseline.tsv` (bootstrap: `--emit-baseline`) and **rejects only NEW RED edges** — the
boy-scout rule applied to architecture, following the diff-coverage precedent (an absolute RED=0
floor on a legacy codebase fails day one and gets the gate removed). On rejection the gate offers
a fix menu: weaken the coupling to a contract, move the modules closer, re-classify the strength
with evidence, or consciously accept the debt into the baseline under review.

## Fitness thresholds (source: fitness-metrics)

| ID | Metric | GREEN | YELLOW | RED |
|----|--------|-------|--------|-----|
| S-01 | Cyclomatic complexity (method) | ≤10 | 11–20 | >20 |
| S-02 | Method length (lines) | ≤30 | 31–60 | >60 |
| S-03 | Class length (lines) | ≤300 | 301–500 | >500 |
| S-04 | Parameter count | ≤4 | 5–6 | >6 |
| D-01 | Afferent coupling (Ca) | ≤10 | 11–20 | >20 |
| D-02 | Efferent coupling (Ce) | ≤10 | 11–20 | >20 |
| D-03 | Instability (I = Ce/(Ca+Ce)) | 0.3–0.7 | 0.1–0.3 / 0.7–0.9 | <0.1 / >0.9 |

`measure-complexity.sh` feeds S-01 (and the cognitive companion band). `measure-coupling.sh`
feeds D-01–D-03. S-02/S-03/S-04 (method/class length, parameter count) are structural limits;
class length overlaps with the line-count gate (`check-file-line-limit.sh`).

## Stack assumptions and limits

- **measure-complexity.sh requires PMD** (it fetches PMD to `build/quality/lib` if not on PATH),
  so it targets Java by default. Set `COMPLEXITY_LANG` / `COMPLEXITY_PATHS` for other PMD-supported
  layouts; for non-PMD stacks use a language-native complexity tool instead.
- **measure-coupling.sh import analysis is language-parametric** (`COUPLING_LANG`):
  `java`（既定・`package`+`import <PKG_PREFIX>`、prefix 必須）/ `go`（`import "<go.mod module>/x/y"`、
  prefix=モジュールパス必須）/ `python`・`typescript`・`rust`（prefix 不要——モジュール=COUPLING_SRC 相対の
  ディレクトリをドット結合。ts は相対 import をファイル位置から解決、rust は `use crate::…` の小文字
  セグメント）。これにより measure-modularity（distance・Balanced Coupling）も非JVMで動く。The
  **co-change analysis is language-agnostic** and runs even without a prefix, so the tool
  still produces a portable temporal-coupling signal on any stack.
- The accidental-complexity proxies rank candidates; their absolute values are not meaningful.
- In `measure-coupling.sh`, "distance" is reduced to two values; the full package-tree distance is
  implemented in `measure-modularity.sh` (a code-structure proxy — team/runtime boundaries, which
  vladikk's distance also covers, are not seen mechanically).
- Strength **classification** (contract/model/functional/intrusive) is a semantic judgment: the
  scripts only consume `modularity-strength.tsv`; producing it is the `modularity-review` skill's
  job. A wrong classification yields a wrong verdict — evidence links are mandatory.
- Import-based strength does not see reflection / string-built dependencies.
- Co-change uses a per-commit basis, so it is sensitive to commit granularity.

## Operation

- **Triggers**: (1) before/after a sizable refactor or feature (effect measurement); (2) during a
  harness ROI evaluation cycle; (3) at boy-scout-rule decision time (if a touched file's method is
  YELLOW/RED, consider a one-step improvement).
- **Gating**: complexity stays advisory for now — per the meta-harness principle "do not install a
  standing gate without firing history and measured cost", run 2–3 cycles first
  (`measure-complexity.sh --strict` is the future hook). Modularity IS gateable today via
  `check-modularity-ratchet.sh`, because the ratchet form does not need firing history to be safe:
  the baseline freezes all existing debt, so the gate demands nothing of the legacy body and fires
  only on new regressions (the same reasoning that shipped diff-coverage as a day-one gate).
- **Validating a refactor**: run the same command before/after a refactor PR and record the change
  in the target method's cognitive complexity, the difference, and co-change pair count in the PR.

## Configuration reference

Set these in `harness.config.sh` (consumer repo root) or as environment variables:

| Variable | Default | Used by |
|----------|---------|---------|
| `COMPLEXITY_PATHS` | `src/main/java` | complexity (source roots) |
| `COMPLEXITY_LANG` | `java` | complexity (CPD language) |
| `COMPLEXITY_RULESET` | auto-resolved | complexity (PMD ruleset) |
| `COMPLEXITY_CC_YELLOW` / `COMPLEXITY_CC_RED` | 10 / 20 | complexity (CC bands) |
| `COMPLEXITY_COG_YELLOW` / `COMPLEXITY_COG_RED` | 15 / 25 | complexity (cognitive bands) |
| `COMPLEXITY_CPD_MIN_TOKENS` | 100 | complexity (duplication) |
| `PMD_VERSION` | 7.20.0 | complexity (PMD fetch) |
| `COUPLING_SRC` | `src/main/java` | coupling (source root) |
| `COUPLING_PKG_PREFIX` | (unset) | coupling (import half — required) |
| `COUPLING_FILE_GLOB` | `*.java` | coupling (source file glob) |
| `COUPLING_SINCE_DAYS` | 90 | coupling (volatility / co-change window) |
| `COUPLING_COCHANGE_MIN` | 5 | coupling (co-change threshold) |
| `MODULARITY_STRENGTH_FILE` | `<root>/modularity-strength.tsv` | modularity (judgment-layer classification) |
| `MODULARITY_DEFAULT_LEVEL` | `model` | modularity (level for unclassified edges) |
| `MODULARITY_STRENGTH_HIGH` | 3 (= functional) | modularity ("strong" floor) |
| `MODULARITY_DISTANCE_HIGH` | 4 | modularity ("distant" floor; siblings = 2 = near) |
| `MODULARITY_VOL_HIGH` | 5 | modularity ("volatile" floor, changes per window) |
| `MODULARITY_BASELINE_FILE` | `<root>/modularity-baseline.tsv` | ratchet gate (known-debt ledger) |

## Related

- Threshold source: fitness-metrics (S-01 / D-01–D-03) and SonarSource Cognitive Complexity
- Coupling concept: [vladikk/modularity](https://github.com/vladikk/modularity) (Balanced Coupling)
- Logical-gate grouping for ROI evaluation: `templates/gate-groups.tsv.example`
