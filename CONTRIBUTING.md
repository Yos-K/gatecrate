# Contributing to gatecrate

> AI エージェント（Claude Code / Codex 等）で変更する場合は、まず [AGENTS.md](./AGENTS.md)
> （運用規則・ペアリング規則・vendoring 規則・PR 前のローカルゲート）を読むこと。

## Versioning (SemVer)

This repository follows **Semantic Versioning** managed via release tags.
The sync-manifest mechanism detects updates by comparing tags, so versioning is central to the sync pipeline.

| Version | Change type | Example |
|---|---|---|
| **PATCH** (x.y.**Z**) | Bug fix, minor script correction (no behavior change) | Fix shell syntax error, fix comment |
| **MINOR** (x.**Y**.0) | New harness added, new adapter added | Add `adapters/python/`, add new script |
| **MAJOR** (**X**.0.0) | Ratchet threshold reduction, breaking interface change | Lower `FITNESS_MAX_LINES` default from 300 to 200 |

### Important: MAJOR changes

**Ratchet threshold reductions** (tightening quality gates) are always **MAJOR** releases.
This prevents sync PRs from silently lowering thresholds and causing unexpected CI failures in consumer projects.

## Upstreaming from a consumer (consumer → kit)

Harness improvements are usually made in a consumer project first (that is where the harness
runs), then returned here. When upstreaming:

- **Port the improvement onto the kit's generic form, not the consumer's form.** Keep the
  parameterization (`$BUILDCONFIG_PACKAGE`, `$APP_THEMES`, env-var defaults, `#!/bin/sh`, and
  the git-resolved repo root used by consumable scripts). Do **not** copy consumer-specific
  drift (hardcoded package IDs, host-specific shebangs/paths, hardcoded value lists) — that
  regresses portability. See [docs/structure.md](./docs/structure.md) for the consumption model.
- **Skip what the kit already has.** A consumer often diverges by re-hardcoding things the kit
  already generalized; that is not an improvement to return.
- Bump the version and add a `CHANGELOG.md` entry (see Versioning below).

The reverse direction (kit → consumers) is automated via `sync-propose.yml`.

## PR Rules

- **Harness PRs must not change application behavior**
  - Including `src/**` in `managed_files` is prohibited (manifest schema constraint)
  - Confirm that script changes do not affect the consumer project's build, test, or release pipelines before opening a PR

### managed_files Whitelist Rules

**Never include `src/**`, `harness.config.sh` (the consumer's shell config — not YAML), or `profiles/` in `managed_files`.**
Including these would risk overwriting the consumer project's own settings.
The whitelist should contain only files under `core/` and `adapters/`.
(Schema-level validation of the manifest is not implemented; CI's "sync-manifest
integrity" step verifies that every listed path exists.)

- **Never commit secrets, keystores, or service account keys**
  - `check-no-committed-secrets.sh` is self-applied in CI
  - Run `sh core/scripts/check-no-committed-secrets.sh` locally before opening a PR

- **Use `#!/bin/sh` as the shebang for all scripts**
  - Scripts must run with `sh script.sh` on Termux (Android), macOS, and Linux
  - `#!/bin/bash` and `#!/usr/bin/env zsh` are prohibited

## File Size Constraint

- 300 lines maximum per file (`check-file-line-limit.sh` is self-applied in CI)
- Split into multiple files by category if a file exceeds this limit

## Branch Strategy

- `main`: release branch — direct push is prohibited
- Feature branch → PR → CI fully green → merge to main → release tag

## Japanese/English Documentation Sync

README.md is the primary document (English). README.ja.md is the Japanese supplement.
When updating README.md, update README.ja.md simultaneously to keep them in sync.
