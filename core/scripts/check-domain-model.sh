#!/bin/sh
# [汎用core] ドメインモデル形式検査（Alloy spec の CI ゲート）— スタック非依存
# gatecrate-type: advisory  (ADVISORY by design：jar 不在は SKIP・既定 non-required・DOMAIN_MODEL_STRICT で gate)
#
# WHY: 仕様(glossary/ルール)の L2/L3 制約は相互作用する。あるルール変更が既存の保証を壊しても、
# コードが書かれるまでレビューにもコードレベルテストにも見えない。各 .als は規則 + `check ... expect N`
# を符号化し、Alloy が(小さな)状態空間を網羅探索して、保証が予期せず反例を得る/失う時に非0で落ちる。
# = fitness/test ゲートより一段「左」の篩——実装より手前でルール退行を止める。
#
# LOOP（これが本スクリプトの存在意義）: gatecrate のドメイン学習ループの「実行可能な出口」。
# alloy-spec-model-generator スキルと harness-rule-reflect が「ドメイン学習 → .als assert」を生み、
# 本ゲートが CI で回して、エージェントがフィードバック(既定 advisory)を受けて仕様を改善する。出口が
# 無ければループは検査の手前で切れる(モデルは生成されるが CI で効かない)。これを閉じるためのゲート。
#
# ADVISORY by design: java/Alloy jar が無い(取得もできない)時は SKIP(exit 0) で偽陽性ブロックしない。
#   反例による FAIL(=ルール退行)だけが非0。DOMAIN_MODEL_STRICT=1 でツールチェーン不在も失敗にできる
#   (opt-in の hard ゲート: モデルが必ず回る前提を強制したいリポ向け)。
#
# Config (harness.config.sh または env):
#   DOMAIN_MODEL_PATHS  — .als を探すディレクトリ/グロブ(空白区切り)。既定: docs/domain/models
#   DOMAIN_MODEL_STRICT — 1 で java/Alloy 不在を失敗に(既定 0 = advisory skip)
#   DOMAIN_MODEL_JAVA   — java 実行ファイル(既定: java)。テスト/特定 JDK 指定用の seam
#   ALLOY_HOME          — Alloy jar のキャッシュ先(既定: $HOME/.local/share/alloy)
#
# Modes:
#   check-domain-model.sh [model.als ...]  検査を実行(引数なしは DOMAIN_MODEL_PATHS から探索)。終了コードが結果。
#   check-domain-model.sh --print          探索した .als とツールチェーン判定を表示し exit 0(テスト用・java 不要)。
#
# Consumption model: repo root を git で解決するので、本ファイルは kit(core/scripts/)でも
# 消費者(scripts/)でも同じく動く。
set -u

ROOT="$(git -C "$(dirname -- "$0")" rev-parse --show-toplevel 2>/dev/null \
  || (CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd))"
# shellcheck source=/dev/null
[ -f "$ROOT/harness.config.sh" ] && . "$ROOT/harness.config.sh"
cd "$ROOT"

ALLOY_VERSION="6.2.0"
ALLOY_SHA256="6b8c1cb5bc93bedfc7c61435c4e1ab6e688a242dc702a394628d9a9801edb78d"
ALLOY_URL="https://github.com/AlloyTools/org.alloytools.alloy/releases/download/v${ALLOY_VERSION}/org.alloytools.alloy.dist.jar"
ALLOY_DIR="${ALLOY_HOME:-$HOME/.local/share/alloy}"
ALLOY_JAR="$ALLOY_DIR/alloy-${ALLOY_VERSION}.jar"
MODEL_PATHS="${DOMAIN_MODEL_PATHS:-docs/domain/models}"
STRICT="${DOMAIN_MODEL_STRICT:-0}"
JAVA_BIN="${DOMAIN_MODEL_JAVA:-java}"

MODE="run"
[ "${1:-}" = "--print" ] && { MODE="print"; shift; }

# --- resolve the model list (deterministic: explicit args override, else scan MODEL_PATHS) ----
# A consumer keeps specs under docs/domain/models by default; override with DOMAIN_MODEL_PATHS
# (space-separated dirs or globs). Output is one .als path per line, de-duplicated and sorted.
resolve_models() {
  if [ "$#" -gt 0 ]; then
    for m in "$@"; do [ -n "$m" ] && printf '%s\n' "$m"; done
    return
  fi
  for p in $MODEL_PATHS; do
    if [ -d "$p" ]; then
      find "$p" -name '*.als' 2>/dev/null
    else
      for g in $p; do [ -f "$g" ] && printf '%s\n' "$g"; done
    fi
  done | sort -u
}

MODELS="$(resolve_models "$@")"

# Toolchain decision is a testable seam: DOMAIN_MODEL_JAVA lets a test force "java missing"
# deterministically (and lets a consumer pin a specific JDK) without touching PATH.
have_java=0
command -v "$JAVA_BIN" >/dev/null 2>&1 && have_java=1

if [ "$MODE" = "print" ]; then
  echo "domain-model: paths=$MODEL_PATHS strict=$STRICT java=$have_java"
  if [ -z "$MODELS" ]; then
    echo "domain-model: (no .als models found)"
  else
    printf '%s\n' "$MODELS" | sed 's/^/model: /'
  fi
  exit 0
fi

if [ -z "$MODELS" ]; then
  echo "domain-model: no .als models found under: $MODEL_PATHS; nothing to check." >&2
  exit 0
fi

if [ "$have_java" -eq 0 ]; then
  if [ "$STRICT" = "1" ]; then
    echo "domain-model: java ('$JAVA_BIN') not found; DOMAIN_MODEL_STRICT=1 -> failing." >&2
    exit 1
  fi
  echo "domain-model: java ('$JAVA_BIN') not found; skipping (advisory check)." >&2
  exit 0
fi

# --- ensure the Alloy jar (pinned version + sha256-verified before we ever run it) ----
sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
if [ ! -f "$ALLOY_JAR" ]; then
  mkdir -p "$ALLOY_DIR"
  echo "domain-model: fetching Alloy ${ALLOY_VERSION}..." >&2
  if ! curl -fsSL -o "$ALLOY_JAR.tmp" "$ALLOY_URL"; then
    rm -f "$ALLOY_JAR.tmp"
    if [ "$STRICT" = "1" ]; then
      echo "domain-model: could not fetch Alloy; DOMAIN_MODEL_STRICT=1 -> failing." >&2
      exit 1
    fi
    echo "domain-model: could not fetch Alloy; skipping (advisory check)." >&2
    exit 0
  fi
  if [ "$(sha_of "$ALLOY_JAR.tmp")" != "$ALLOY_SHA256" ]; then
    echo "domain-model: Alloy jar checksum mismatch; refusing to run it." >&2
    rm -f "$ALLOY_JAR.tmp"
    exit 1
  fi
  mv "$ALLOY_JAR.tmp" "$ALLOY_JAR"
fi

# --- run every check/run command in each model; `expect N` -> non-zero on a surprise ----
STATUS=0
OUT_DIR="${TMPDIR:-/tmp}/domain-model-check.$$"
for model in $MODELS; do
  echo "domain-model: checking $model"
  if ! "$JAVA_BIN" -jar "$ALLOY_JAR" exec -f -o "$OUT_DIR" -c '*' "$model"; then
    echo "domain-model: FAIL $model (counterexample trace in $OUT_DIR)" >&2
    STATUS=1
  else
    rm -rf "$OUT_DIR"
  fi
done

[ "$STATUS" -eq 0 ] && echo "domain-model: all spec guarantees hold as expected."
exit "$STATUS"
