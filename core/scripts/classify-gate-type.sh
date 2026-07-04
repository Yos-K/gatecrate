#!/bin/sh
# [汎用core] ゲート型分類 — スタック非依存
#
# WHY (ROADMAP P4 / docs/probe-scope-and-gate-classification-decision.md §3): ROI 剪定は発火履歴を読むが、
# 「予防型で発火0(=正常・liveness で価値証明)」と「検出型で発火0(=削除候補)」は発火履歴だけでは区別できない。
# これは probe が解いた「沈黙の死角」が ROI 判定側に再来したもの。型を知らないと剪定は最重要の(沈黙する)予防
# ゲートを消すか、何も剪定できないかのどちらかになる。だから各ゲートの型が要る。
#
# 型は「手貼りラベル」ではなく「構造から導出」する（手貼りは腐る＝testless gate と同じ失敗）:
#   prevention  probe の reject-type レジストリ在籍（probe-gate-liveness.sh --list-reject-gates が単一ソース）。
#               合成違反を注入できる予防ゲート＝発火0が正常で、価値は liveness(生存証明)で証明される。
#   detection   人間の `# gatecrate-type: detection` マーカー。発火履歴で価値を証明する層（消費者のテスト/
#               mutation/build 等）。構造だけからは導出できないため人間が宣言する。
#   advisory    人間の `# gatecrate-type: advisory` マーカー。merge をブロックしない層（measure-* の既定モード・
#               required でない check 等）。ブロックしないので発火ベースの ROI 剪定は適用しない——価値の問いは
#               「その信号が読まれ・行動に使われているか」で、CI履歴からは機械判定できず人間判断（決して自動剪定しない）。
#   prevention  人間の `# gatecrate-type: prevention` マーカー（注入器がまだ無い reject ゲート等の上書き）。
#   untyped     導出も人間上書きも無い「ブロックするのに未分類」のゲート＝真の穴（メタゲートが拾う対象）。
#   not-a-gate  ハーネスのツール/ユーティリティ（gate でない）。分類 universe の外（NON_GATE 参照）。
#
# 判定順（構造一次→人間上書き→untyped）: not-a-gate → prevention(レジストリ) → マーカー(advisory/detection/
# prevention) → untyped。advisory/detection は「ブロックするか」がモード(`--strict`)とCI配線(required か)に依存し
# スクリプト単体では導出できないため、step2 では人間マーカーで宣言する（CI配線からの導出は後続改良）。
#
# できないこと（意図的・docs §1）: 「意味的に誤分類されたラベルの検出」は称さない。レジストリ在籍は構造的事実
# として一次で、マーカーより優先する（検出型を予防型と偽装しても在籍していなければ偽装は効かない）。逆に在籍
# ゲートに detection マーカーを貼る誤分類は **検出しない** —— それは「空虚テストの検出」と同じく機械では不能で、
# 是正は人間の escalation に委ねる。存在は機械化できるが意味的正しさは人間信頼に着地する、という原則の実装。
#
# Usage:
#   classify-gate-type.sh --one <gate_path>
#       1ゲートを分類: "<verdict> <base> — <reason>" を stdout に出し exit 0
#       （verdict=prevention|detection|advisory|untyped|not-a-gate）。
#   classify-gate-type.sh --explain <gate_path>
#       分類の判断材料（派生証拠＋推論のはしご・未検証の段は [UNVERIFIED]）を人間向けに提示。
set -eu

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PROBE="$HERE/probe-gate-liveness.sh"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || (CDPATH= cd -- "$HERE/../.." && pwd))"

# Harness tooling / utilities that are NOT gates (they never block a consumer's merge) and so fall
# outside ROI classification entirely. Kept aligned with the "計測 advisory / ユーティリティ" enumeration
# check-gate-tests.sh already carries. measure-* are deliberately NOT here: they DO emit a gateable
# signal (--strict), so they are advisory gates, classified via a human marker, not excluded.
NON_GATE="collect-gate-history.sh gate-roi-verdict.sh mutation-scope.sh render-harness-dashboard.sh
probe-gate-liveness.sh classify-gate-type.sh setup-branch-protection.sh start-work.sh pr-preflight.sh
prepare-play-store-screenshot.sh version-check.sh version-env.sh version-show.sh es-render.sh es-render-html.sh
es-render-cmap-html.sh probe-semantic-liveness.sh"

# is_non_gate <base>: true if base is harness tooling/utility rather than a gate.
is_non_gate() {
  for n in $NON_GATE; do [ "$n" = "$1" ] && return 0; done
  return 1
}

# is_prevention_base <base>: true if base is in the probe's reject-type (prevention) registry.
# Single source of truth: the registry lives only in probe-gate-liveness.sh; we never re-declare it.
is_prevention_base() {
  sh "$PROBE" --list-reject-gates 2>/dev/null | grep -qx "$1"
}

# gate_type_marker <gate_file>: echo the lowercase type a human asserted on a `# gatecrate-type: <t>`
# line (mirrors the `# gatecrate-scope: escalation-only` marker), or empty if none. grep-only, like
# is_escalation_only — we read the human's declaration, we do not verify it is semantically right.
gate_type_marker() {
  [ -f "$1" ] || return 0
  sed -n 's/^[[:space:]]*#[[:space:]]*gatecrate-type:[[:space:]]*\([a-z][a-z]*\).*/\1/p' "$1" | head -n1
}

# classify_one <gate_path>: print "<verdict> <base> — <reason>". Derivation order (structure first,
# human override second, untyped last) is what keeps the hand-asserted surface minimal.
classify_one() {
  base="$(basename "$1")"
  if is_non_gate "$base"; then
    echo "not-a-gate $base — harness tooling/utility, not a CI gate; outside ROI classification"
    return 0
  fi
  if is_prevention_base "$base"; then
    echo "prevention $base — in the reject-type registry (probe --list-reject-gates); firing=0 is healthy, value proven by liveness"
    return 0
  fi
  marker="$(gate_type_marker "$1")"
  case "$marker" in
    detection)  echo "detection $base — human override (# gatecrate-type: detection); value proven by firing history" ;;
    advisory)   echo "advisory $base — human override (# gatecrate-type: advisory); does not block a merge, so firing-based ROI pruning does not apply; value = is the signal consumed?" ;;
    prevention) echo "prevention $base — human override (# gatecrate-type: prevention)" ;;
    "")         echo "untyped $base — not in the reject-type registry and no # gatecrate-type marker; classify it (add an injector+register, or a # gatecrate-type marker)" ;;
    *)          echo "untyped $base — unrecognized '# gatecrate-type: $marker' (expected prevention|detection|advisory); treat as unclassified" ;;
  esac
}

# explain_one <gate_path>: print the decidability evidence + a SUGGESTED type (a hypothesis with its
# basis shown), so a human can verify-not-derive. Evidence we cannot derive (required-check status,
# firing history) is marked needs-gh, never guessed (docs §3.2). NEVER auto-applies a marker.
explain_one() {
  gate="$1"; base="$(basename "$gate")"
  current="$(classify_one "$gate" | awk '{print $1}')"

  if grep -Eq 'exit[[:space:]]+[1-9]' "$gate" 2>/dev/null; then
    blocks=yes; bnote="found a non-zero 'exit N' path"
  else
    blocks=unclear; bnote="no explicit 'exit N>0' — may exit via a command's status; verify"
  fi
  is_prevention_base "$base" && reg=yes || reg=no
  grep -qF -- '--strict' "$gate" 2>/dev/null && strict=yes || strict=no
  grep -qi 'advisory' "$gate" 2>/dev/null && adv=yes || adv=no
  if [ -f "$ROOT/tests/test-$base" ] || [ -f "$ROOT/tests/test-${base#check-}" ]; then bt=yes; else bt=no; fi
  wf="$(grep -rlF -- "$base" "$ROOT/.github/workflows" 2>/dev/null | sed "s#^$ROOT/##" | tr '\n' ' ')"
  [ -n "$wf" ] || wf=no

  # Build the suggestion as an inference ladder (Ladder of Inference: observe -> select -> assume
  # -> conclude) so the human can climb DOWN and check each rung, not just trust a verdict. The
  # load-bearing ASSUMPTION is flagged UNVERIFIED when it rests on data this view cannot see
  # (needs-gh), so the human is told exactly which rung to check first. The ladder COLLAPSES to
  # observe->conclude when there is no inferential leap (a structural fact / a human's own marker)
  # — we never invent rungs where no inference happened.
  obs="exit-path=$blocks, registry=$reg, --strict=$strict, self-advisory=$adv"
  sel=""; asm=""; chk=""
  case "$current" in
    not-a-gate)
      sug=not-a-gate
      concl="on the NON_GATE tooling/utility list ⇒ not a gate, no type needed (no inferential leap)" ;;
    prevention|detection|advisory)
      sug="$current"
      concl="already declared by registry/marker ⇒ $current (no machine inference; no inferential leap)" ;;
    *)
      if [ "$reg" = yes ]; then
        sug=prevention
        concl="registry membership is a structural fact ⇒ prevention (no inferential leap)"
      elif [ "$adv" = yes ] || [ "$strict" = yes ]; then
        sug=advisory
        sel="the self-advisory/--strict signal is load-bearing"
        asm="a self-declared-advisory / opt-in --strict gate does not block by default  [UNVERIFIED — needs CI wiring: required-check status (needs-gh)]"
        concl="non-blocking ⇒ advisory (firing-based ROI pruning does not apply)"
        chk="the [UNVERIFIED] assume rung — does it actually block as wired?"
      elif [ "$blocks" = yes ]; then
        sug=detection
        sel="the non-zero exit path is load-bearing"
        asm="a non-zero exit on a violation blocks the merge as wired  [UNVERIFIED — needs CI wiring: required-check status (needs-gh)]"
        concl="blocks + not-in-prevention-registry ⇒ detection (fires on a real condition)"
        chk="the [UNVERIFIED] assume rung — does it actually block as wired?"
      else
        sug=detection-or-advisory
        sel="the exit semantics are load-bearing but unclear from the script"
        asm="cannot tell from the script whether it blocks  [UNVERIFIED — read the gate's WHY + CI wiring]"
        concl="undecidable from structure ⇒ read the WHY to choose detection vs advisory"
        chk="the [UNVERIFIED] assume rung — read the gate's WHY"
      fi ;;
  esac

  echo "gate: $base"
  echo "current: $current"
  echo "evidence:"
  echo "  blocks-merge:    $blocks ($bnote)"
  echo "  reject-registry: $reg"
  echo "  strict-mode:     $strict"
  echo "  self-advisory:   $adv"
  echo "  behavior-test:   $bt"
  echo "  in-workflows:    $wf"
  echo "  required-check:  needs-gh (branch protection)"
  echo "  firing-history:  needs-gh (collect-gate-history)"
  echo "suggested: $sug"
  echo "  inference ladder (climb down where a rung feels wrong):"
  echo "    observe:  $obs"
  [ -n "$sel" ] && echo "    select:   $sel"
  [ -n "$asm" ] && echo "    assume:   $asm"
  echo "    conclude: $concl"
  [ -n "$chk" ] && echo "  check first: $chk"
  echo "note: suggestion only — verify against the gate's WHY, then add a '# gatecrate-type:' marker by hand. Never auto-applied (docs §3.2)."
}

# ---- single-gate mode ----
if [ "${1:-}" = "--one" ]; then
  [ -n "${2:-}" ] || { echo "classify-gate-type: --one needs a gate path" >&2; exit 2; }
  classify_one "$2"
  exit 0
fi

# ---- explain mode: present the decidability evidence for a human (suggest, never auto-apply) ----
if [ "${1:-}" = "--explain" ]; then
  [ -n "${2:-}" ] || { echo "classify-gate-type: --explain needs a gate path" >&2; exit 2; }
  explain_one "$2"
  exit 0
fi

echo "classify-gate-type: usage: classify-gate-type.sh --one <gate_path> | --explain <gate_path>" >&2
exit 2
