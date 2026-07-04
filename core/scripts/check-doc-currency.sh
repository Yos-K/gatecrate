#!/bin/sh
# [汎用core] EN/JA ドキュメント同期チェック（言語非依存の doc-currency ゲート）
# Bilingual docs are kept as pairs: a canonical `X.md` and its translation `X.ja.md`. Their
# correctness depends on a MANUAL discipline — "edit X.md, also edit X.ja.md" — which silently
# drifts when a human forgets. This gate makes that discipline mechanical: in a change set, if
# exactly ONE side of a pair was touched, the other is now stale → fail with which sibling to update.
#
# Surfaced by the 2026-06-14 ROI self-evaluation (docs/evaluations/2026-06-14.md) as the one
# axis-2 consolidate-candidate: bilingual sync was the harness's only manual-discipline drift risk.
#
# Scope: only pairs where BOTH X.md and X.ja.md are tracked. A lone single-language doc (no .ja.md
# sibling) is never flagged. Touching both sides — or neither — passes.
#
# Config (optional, from harness.config.sh in the consumer repo root, or env):
#   DOC_CURRENCY_BASE — git ref to diff against (default: origin/main). The change set is
#                       `git diff --name-only <base> HEAD`.
#   DOC_CURRENCY_SKIP — set to 1 to skip (escape hatch for a deliberate single-side edit, e.g. a
#                       JA-only typo fix; record why in the PR).
#
# Consumption model: repo root via `git rev-parse`, so the SAME file works in this kit
# (core/scripts/) or installed into a consumer (scripts/).
set -eu

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
cd "$ROOT"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"

if [ "${DOC_CURRENCY_SKIP:-0}" = "1" ]; then
  echo "doc-currency: skipped (DOC_CURRENCY_SKIP=1)"
  exit 0
fi

BASE="${DOC_CURRENCY_BASE:-origin/main}"

# Resolve the base ref; if it is unavailable (fresh repo, shallow clone without the base, or a
# local checkout that never fetched origin) we cannot compute a change set — pass with a notice
# rather than fail spuriously. The gate only protects against drift it can actually see.
if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1; then
  echo "doc-currency: base ref '$BASE' not resolvable — skipping (set DOC_CURRENCY_BASE)."
  exit 0
fi

# Change set WITH status (A/M/D), two-dot (base tip vs HEAD): robust under a shallow clone that
# only has the base tip, and --no-renames so a rename shows as delete+add (each side judged).
changed_status="$(git diff --name-status --no-renames "$BASE" HEAD)"

# status_of <path>: the change-set status letter (A/M/D) for a path, empty if untouched.
status_of() {
  printf '%s\n' "$changed_status" | awk -F '\t' -v p="$1" '$2==p { print substr($1,1,1); exit }'
}

# Pairs implicated by this change: every touched *.md (EN or JA) maps to its EN-canonical key.
# Driving off the change SET (not HEAD's file list) is what catches a one-sided DELETE/rename — a
# side removed from HEAD is still in the diff with status D.
pairs="$(printf '%s\n' "$changed_status" \
  | awk -F '\t' '$2 ~ /\.md$/ { p=$2; sub(/\.ja\.md$/, ".md", p); print p }' \
  | sort -u)"

violations=0
checked=0
for en in $pairs; do
  [ -n "$en" ] || continue
  ja="${en%.md}.ja.md"
  se="$(status_of "$en")"   # A / M / D / "" (untouched)
  sj="$(status_of "$ja")"
  # A managed bilingual pair = both sides real (present at HEAD, or deleted=present at base).
  # A lone single-language doc (no real sibling) is never a drift case.
  { [ -f "$en" ] || [ "$se" = D ]; } || continue
  { [ -f "$ja" ] || [ "$sj" = D ]; } || continue
  checked=$((checked + 1))
  te=0; [ -n "$se" ] && te=1
  tj=0; [ -n "$sj" ] && tj=1
  if [ "$te" = 1 ] && [ "$tj" = 1 ]; then
    continue                       # both sides touched -> consistent (edit-both / delete-both)
  elif [ "$te" = 1 ]; then
    echo "STALE  $en changed but $ja was not — update/remove the JA sibling (or DOC_CURRENCY_SKIP=1 with a reason)." >&2
    violations=$((violations + 1))
  elif [ "$sj" = A ]; then
    continue                       # adding a translation to an unchanged EN canonical -> in sync
  else
    echo "STALE  $ja changed but $en was not — update the EN canonical (or DOC_CURRENCY_SKIP=1 with a reason)." >&2
    violations=$((violations + 1))
  fi
done

echo ""
if [ "$violations" -gt 0 ]; then
  echo "doc-currency FAILED: $violations bilingual pair(s) out of sync (base: $BASE)." >&2
  echo "Edit both sides of each pair so the translation does not drift from the canonical doc." >&2
  exit 1
fi
echo "doc-currency passed: $checked bilingual pair(s) checked, all in sync (base: $BASE)."
