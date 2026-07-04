# shellcheck shell=sh  # sourced, not executed — declare target shell for shellcheck (SC2148)
# harness.config.sh — gatecrate as its OWN consumer #0 (core-only / minimal profile).
#
# gatecrate is a shell-only repo (no Gradle/Maven/Android), so the gatecrate-setup skill
# classifies it as the minimal/core-only path: no mutation, no BuildConfig, no TARGET_CLASSES.
# The only project-specific values are for the language-agnostic file-line-limit gate.
#
# This file exists so the kit exercises the SAME config -> script wiring a real consumer uses
# (the self-harness CI invokes core/scripts/check-file-line-limit.sh with no env; it sources
# these values from here), rather than passing them inline. Configs are never synced.

FILE_LINE_LIMIT=300
# *.md（ドキュメント）だけを 300 行ルールの対象にする。シェルスクリプトは対象外:
# es-render-html.sh のような決定論ジェネレータは heredoc(HTML/CSS/JS)と awk が連続して初めて読める塊で、
# 300 行で機械分割すると「どの heredoc がどの awk と対か」が散り、かえって可読性が落ちる（分割の害＞長さの害）。
# 可読性は本ルールの WHY そのものなので、シェルは行数でなくレビューで担保する。*.md は分割が自然なので維持。
FILE_LINE_NAMES="*.md"
# FILE_LINE_PATHS defaults to "." (whole repo); the script prunes .git itself.
