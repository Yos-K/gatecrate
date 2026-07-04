# Harness dashboard — see your gates' state on GitHub

## What this doc is for

You added gatecrate's gates; this shows their **state on GitHub** without leaving the Actions UI.
Two native surfaces, no GitHub Pages required:

- **README badge** — green when every gate passes on `main`. At-a-glance "is it healthy?".
- **Run Summary dashboard** — a per-gate table on every CI run's **Summary** page: each gate's
  **type** (prevention / detection / advisory), **liveness** (is the prevention gate actually
  enforcing?), and **ROI verdict** (keep / removal-candidate / human-judgment).

The dashboard is just a renderer (`core/scripts/render-harness-dashboard.sh`, a not-a-gate tool)
over data gatecrate already produces — `classify-gate-type` (type), `probe-gate-liveness`
(liveness), `gate-roi-verdict` (verdict). It never fails the build; it only reports.

---

## 1. Add the badge (README)

```markdown
[![CI](https://github.com/<owner>/<repo>/actions/workflows/ci.yml/badge.svg)](https://github.com/<owner>/<repo>/actions/workflows/ci.yml)
```

Replace `<owner>/<repo>` and `ci.yml` with your workflow file. Add a `Mutation` badge the same way
if you run `mutation.yml`.

---

## 2. Add the Run Summary dashboard (CI step)

Add this as the **last step** of the job that runs your gates (`if: always()` so it renders even
when a gate above fails — that is exactly when you want to see the board):

```yaml
      - name: Harness dashboard (job summary)
        if: always()
        run: sh scripts/render-harness-dashboard.sh >> "$GITHUB_STEP_SUMMARY"
```

`install.sh` ships `render-harness-dashboard.sh` (plus its data sources `classify-gate-type.sh` and
`gate-roi-verdict.sh`) into `scripts/`, so the step works with no extra setup.

### Filling the ROI verdict column + the CI-cost / fires bar charts (optional)

Liveness and type need no network. The **verdict** column and the **CI-cost / fires bar charts**
need firing history, which comes from `collect-gate-history.sh` (needs `gh`). Point the renderer at
its output (`DASHBOARD_FIRING_TSV`):

```yaml
      - name: Harness dashboard (job summary)
        if: always()
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          sh scripts/collect-gate-history.sh --limit 50 > /tmp/firing.tsv || true
          DASHBOARD_FIRING_TSV=/tmp/firing.tsv sh scripts/render-harness-dashboard.sh >> "$GITHUB_STEP_SUMMARY"
```

Without it, the verdict column shows `—` (honest: not guessed). Type and liveness still render.

---

## 3. What each column means (and how to act)

| Column | Source | What to do |
|---|---|---|
| Type | `classify-gate-type` | If a gate is `⚠️ untyped`, classify it (a `# gatecrate-type:` marker) — see [`probe-scope-and-gate-classification-decision.md`](./probe-scope-and-gate-classification-decision.md). |
| Liveness | `probe-gate-liveness` | `❌ DEAD` = a prevention gate stopped enforcing (silently). Fix it first — it is the highest-signal failure. `—` = not a probe-able prevention gate. |
| ROI verdict | `gate-roi-verdict` | `removal-candidate` / `human-judgment` are **proposals**; a human decides (never auto-removed). See [`harness-roi-evaluation.md`](./harness-roi-evaluation.md). |

The dashboard surfaces state; the *decisions* (classify, prune, fix a DEAD gate) stay human — the
board just makes them cheap to see.
