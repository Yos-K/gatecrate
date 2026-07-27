# ADR-0001: Distribute the Rust implementation as source, prebuilt binaries deferred

Status: Proposed (one input still open: Termux on-device verification)

## Decision

Consumers obtain the Rust implementation by **building from source** (`cargo build --release`
in the kit checkout, or the same step in their CI). The version pin is the kit's git tag —
the same pin `sync-manifest.yaml` already carries. Shimmed scripts locate the binary via
`GATECRATE_BIN`, then the kit's own `target/`, then `PATH`, and fail with an explicit exit 2
when it is absent.

Prebuilt binaries (cargo-dist releases, cargo-binstall) are **deferred, not rejected**: the
crate layout is lib-first, so switching or adding a distribution shape later changes only the
thin bin layer and this record.

## Alternatives Considered

1. **Single prebuilt binary per platform** (cargo-dist → GitHub Releases, subcommand CLI).
2. **One prebuilt binary per tool** (per-gate artifacts mirroring `consumed_scripts` opt-in).
3. **Source-first** (this decision): consumers build; prebuilts added only when a real
   consumer cannot build.

## Why This Decision

Measured on the pilot (es-render-html, zero-dependency workspace except clap):

- Cold `cargo build --release` is **12.7 s on the CI runner** (no cache; lint job grew
  30 s → 43 s total) and **9.3 s locally**. The cost prebuilts exist to remove is currently
  smaller than one behavior-test suite run.
- **No consumer consumes a shimmed script yet** (es-render-html.sh is in no
  `consumed_scripts`). Building release infrastructure before a consumer exists is the
  "unproven generality" AGENTS.md warns against.
- Source distribution keeps the kit's audit property: what a consumer runs is exactly the
  text they can read at the pinned tag, and `check-kit-drift` needs no second version axis.

## Why Alternatives Were Rejected

- **Single prebuilt binary**: couples every gate's release cadence, adds a version axis to
  drift checking, and its one real benefit (no toolchain requirement) solves a problem no
  current consumer has. Revisit via "Reconsider When".
- **Per-tool binaries**: ~95 tools × 5 platforms of artifacts and a version matrix; the
  opt-in granularity it preserves is already preserved by shims + lib-first features.

## Reconsider When

- Termux on-device verification fails (a consumer environment that cannot `cargo build`),
  or any real consumer adopts a shimmed script and cannot build from source.
- Cold build time exceeds ~60 s (dependency growth) or a consumer's CI cannot cache it.
- A third consumer adopts shimmed scripts (economies of scale shift toward prebuilts).
