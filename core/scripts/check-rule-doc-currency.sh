#!/bin/sh
# [汎用core] ルール→ドキュメント鮮度ゲート（コードのルールを教える文書が古びていないか）— スタック非依存
#
# WHY: ドメイン知識・ハーネス規律・ポリシーは「コード(規則の在処)」と「文書(人とエージェントに規則を
# 教える場所)」の2箇所に住む。規則担持ファイルだけ変えて文書を放置すると、次にそのコードに触る人/AI は
# 古い文書を信じて誤る——ドメイン学習ループの「学んだ知識が腐らない」保証が崩れる。本ゲートは「規則を
# 担うファイルを変えたら、対応する文書も同じ PR で更新する(または影響なしと宣言する)」を機械化する。
#
# 既存の check-doc-currency.sh とは別物: あちらは EN/JA 対訳ペアの相互鮮度。本ゲートは「コードの規則 →
# それを説明する文書」の鮮度。名前が似るのは同じ "doc currency" 一族だから。
#
# 設定駆動（レーン定義ファイル）: 何が「規則担持」で、対応文書はどれかは消費者ごとに違う。レーンを
# TSV で外出しし、スクリプトは汎用エンジンに保つ。各行 = 1レーン:
#   <lane_name>\t<trigger_regex>\t<doc_regex>\t[<exempt_trailer>]
#     trigger_regex : 変更パス(git diff --name-only)に対する ERE。マッチ=このレーンの規則を触った
#     doc_regex     : 同上。マッチ=対応文書を更新した(=鮮度 OK)
#     exempt_trailer: 任意・このレーン専用の旧トレーラ名(例 Glossary-Impact:)。空可
#   `#` 始まりと空行は無視。
# 普遍トレーラ `Docs-Impact:` はビルトイン: いずれかのコミットにあれば、発火した全レーンを免除する
# (純リファクタ/改名/インフラで規則を変えていない時の宣言。例 `Docs-Impact: none (...)`)。
#
# Config (harness.config.sh または env):
#   RULE_DOC_LANES    — レーン定義 TSV のパス。既定: rule-doc-lanes.tsv(repo root)。無ければ skip(exit 0)
#   RULE_DOC_BASE     — 差分の基準 git ref。既定: origin/main。解決不能なら skip(exit 0)
#   RULE_DOC_CHANGED  — (test/上級者 seam) 変更パス一覧を改行区切りで直接渡す。設定時は git diff を使わない
#   RULE_DOC_COMMITS  — (同上) コミットメッセージ塊を直接渡す。RULE_DOC_CHANGED と対で使う
#
# Usage: sh check-rule-doc-currency.sh [base-ref]
# Consumption model: repo root を git で解決するので kit(core/scripts/)でも消費者(scripts/)でも動く。
set -u

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"

LANES_FILE="${RULE_DOC_LANES:-rule-doc-lanes.tsv}"
BASE="${1:-${RULE_DOC_BASE:-origin/main}}"

if [ ! -r "$LANES_FILE" ]; then
  echo "rule-doc-currency: no lane file ($LANES_FILE); nothing configured, skipping (advisory)." >&2
  exit 0
fi

# Change set + commit messages: from the env seam if provided (deterministic/testable),
# else from git. The seam lets a test (or a precomputed diff) drive the engine without a repo.
if [ "${RULE_DOC_CHANGED+set}" = "set" ]; then
  CHANGED="$RULE_DOC_CHANGED"
  COMMITS="${RULE_DOC_COMMITS:-}"
else
  if ! git rev-parse --verify --quiet "$BASE^{commit}" >/dev/null 2>&1; then
    echo "rule-doc-currency: base '$BASE' not resolvable; skipping (advisory)." >&2
    exit 0
  fi
  # two-dot diff (BASE..HEAD endpoints): works under a shallow checkout (only both tips needed,
  # not the merge-base), matching the sibling check-doc-currency.sh gate.
  CHANGED="$(git diff --name-only "$BASE" HEAD)"
  COMMITS="$(git log "$BASE..HEAD" --format='%B' 2>/dev/null || true)"
fi

# match <regex> : true if any changed path matches.   trailer <name> : true if a commit has it at line start.
match()   { printf '%s\n' "$CHANGED" | grep -qE "$1"; }
trailer() { printf '%s\n' "$COMMITS" | grep -qiE "^$1"; }

UNIFIED=0
trailer 'Docs-Impact:' && UNIFIED=1

MISSING=""
RULE_BEARING=""

# Evaluate each configured lane. A lane fires when its trigger matched; it is satisfied when the
# doc was updated, OR the universal Docs-Impact: trailer is present, OR its lane trailer is present.
while IFS="$(printf '\t')" read -r name trig doc exempt; do
  case "$name" in ''|\#*) continue ;; esac
  [ -n "${trig:-}" ] && [ -n "${doc:-}" ] || continue
  match "$trig" || continue
  RULE_BEARING="${RULE_BEARING}$(printf '%s\n' "$CHANGED" | grep -E "$trig")
"
  if match "$doc" || [ "$UNIFIED" -eq 1 ]; then continue; fi
  if [ -n "${exempt:-}" ] && trailer "$exempt"; then continue; fi
  MISSING="${MISSING} $name"
done < "$LANES_FILE"

if [ -z "$MISSING" ]; then
  echo "rule-doc-currency: rule-bearing changes have current documentation (or a declared impact); ok."
  exit 0
fi

echo "rule-doc-currency: FAIL — missing doc updates for:$MISSING" >&2
echo "Rule-bearing files changed without updating the matching documentation:" >&2
printf '%s' "$RULE_BEARING" | sed '/^$/d; s/^/  - /' | sort -u >&2
cat >&2 <<MSG

Update the doc for each lane above (see $LANES_FILE for the trigger->doc mapping), or — if the
change alters no rule (pure refactor, comment, rename, infra) — declare it with ONE commit trailer
that exempts every triggered lane:

  Docs-Impact: none (pure refactor, no rule or workflow behavior change)

(A lane may also define its own legacy trailer in $LANES_FILE column 4.)
MSG
exit 1
