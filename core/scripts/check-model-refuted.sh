#!/bin/sh
# [汎用コア] .es 反証記録の存在・鮮度ゲート（prevention） — スタック非依存
# gatecrate-type: prevention
#
# WHY: モデルの意味的正しさ（因果の向き・evidence が主張を「裏付ける」か）は文法・evidence 実在の
# ゲートでは保証されない——実害: 因果が逆流したモデルが全ゲート green のまま存在し、捕まえたのは
# 敵対的レビュー（refute 工程）だった。判断そのものは機械化できないが、**独立した refute 工程を
# 経たこと・その鮮度**は機械化できる。本ゲートは反証記録（<model>.refutation.md）に
# `model-hash:`（git blob hash）を要求し、モデルが変わったのに記録が古ければ reject する
# （rule-doc-currency の「規則が変わったら文書も」を「モデルが変わったら再レビューも」に写した形）。
#
# 意味的正しさ4層の第3層。第1層=主張の実行可能化(check-es-assertions)、第2層=三角測量
# (es-lint-info R11/R12)、第4層=レビュー工程自体への probe(probe-semantic-liveness)。
#
# 反証記録の要件（機械検査するのはここまで。中身の質は第4層の probe が測る）:
#   - `model-hash: <git hash-object の値>` 行（何をレビューしたかの特定）
#   - 指摘（反映済み含む）と「反証を試みたが正しかった項目」の記載
#
# Config (env):
#   MODEL_REFUTATION_FILE — 記録パスの上書き（既定: <model>.refutation.md）
# Usage: sh check-model-refuted.sh <model.es>   （記録なし/鮮度切れなら exit 1）
set -eu

MODEL="${1:?usage: check-model-refuted.sh <model.es>}"
[ -f "$MODEL" ] || { echo "check-model-refuted: model not found: $MODEL" >&2; exit 2; }
REF="${MODEL_REFUTATION_FILE:-${MODEL%.es}.refutation.md}"

echo "=== check-model-refuted: $MODEL ==="
if [ ! -f "$REF" ]; then
  echo "  [ERROR] 反証記録が無い: $REF"
  echo "  意味的正しさは文法ゲートの保証外——独立した refute 工程（敵対的レビュー）を実施し、"
  echo "  model-hash（git hash-object $MODEL の値）・指摘・反証に耐えた項目を記録してから出荷する。"
  exit 1
fi

CUR="$(git hash-object "$MODEL")"
REC="$(sed -n 's/^model-hash:[[:space:]]*//p' "$REF" | head -1)"
if [ -z "$REC" ]; then
  echo "  [ERROR] 反証記録に model-hash: が無い: $REF ← どの内容をレビューしたのか特定できない記録は無効"
  exit 1
fi
if [ "$CUR" != "$REC" ]; then
  echo "  [ERROR] 反証記録が古い: モデルはレビュー後に変更されている"
  echo "    記録された hash: $REC"
  echo "    現在の   hash: $CUR"
  echo "  refute 工程を再実施し、記録の model-hash と指摘を更新すること（機械が守るのは鮮度まで。判断は人/エージェント）。"
  exit 1
fi
echo "  OK: 反証記録が存在し、モデルの現内容（${CUR}）に対するもの"
exit 0
