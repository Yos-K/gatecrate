#!/bin/sh
# install.sh — gatecrate インストーラ（プロファイル選択器）
# 使い方: sh install.sh [--profile auto|minimal|brownfield|standard|full|python|go|typescript|rust|kotlin|haskell|lean4] [--target <dir>]
# --profile auto は対象ディレクトリのファイルからスタックを判定してプロファイルを選ぶ。

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROFILE=""
TARGET_DIR="$(pwd)"
WITH_CCSDD=0
WITH_SKILLS=0
WITH_HEADROOM=0

# ---- 引数解析 ----
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)
      PROFILE="$2"
      shift 2
      ;;
    --target)
      TARGET_DIR="$2"
      shift 2
      ;;
    --with-cc-sdd)
      WITH_CCSDD=1
      shift
      ;;
    --with-skills)
      WITH_SKILLS=1
      shift
      ;;
    --with-headroom)
      WITH_HEADROOM=1
      shift
      ;;
    --help|-h)
      echo "使い方: sh install.sh [--profile auto|minimal|brownfield|standard|full|python|go|typescript|rust|kotlin|haskell|lean4] [--target <dir>] [--with-cc-sdd] [--with-skills] [--with-headroom]"
      echo ""
      echo "  --profile  インストールプロファイル（省略時: 対話選択）"
      echo "             auto     — 対象のファイルからスタックを判定して自動選択"
      echo "             minimal  — 汎用コア衛生のみ（小規模・使い捨てプロジェクト向け）"
      echo "             brownfield — minimal + 差分カバレッジ ratchet（テスト無し/希薄なレガシーの最初の線。"
      echo "                        絶対 floor を要求せず、この PR の変更行だけに被覆を要求する）"
      echo "             standard — minimal + standard-core(汎用ゲート) + Android-JVM アダプタ"
      echo "             full     — standard + ドメインモデル検査(Alloy)（状態複雑性 high 向け）"
      echo "             python   — minimal + standard-core(汎用ゲート) + Python アダプタ"
      echo "             go/typescript/rust — minimal + standard-core + 各スタックの test/coverage アダプタ"
      echo "             kotlin/haskell/lean4 — minimal + standard-core + 各スタックの test/build アダプタ"
      echo "             ※ standard-core = doc-currency / rule-doc-currency / kit-drift / merge-integrity /"
      echo "                hard-constraints / collect-gate-history / pr-preflight / third-party-notices /"
      echo "                release-version-name / setup-branch-protection / measure-complexity・coupling（advisory）"
      echo "  --target   インストール先ディレクトリ（省略時: カレントディレクトリ）"
      echo "  --with-cc-sdd  cc-sdd 本体を npx で scaffold（npx cc-sdd@latest）し、gatecrate steering と"
      echo "                 mutation の Stop hook を重ねる。agent/言語は env で上書き可:"
      echo "                 CC_SDD_AGENT（既定 --claude-skills）/ CC_SDD_LANG（既定 ja）/ CC_SDD_FLAGS（追加引数）"
      echo "  --with-skills  エージェント・ループ・ツールを配布: .claude/skills/（alloy-spec-model-generator /"
      echo "                 gatecrate-evaluate）＋ TAKT 一式（.takt/ = 二階ループ・規則 reflect の orchestration）"
      echo "  --with-headroom  AIエージェント向けコンテキスト圧縮ツール headroom を uv tool で導入"
      echo "                 （分離環境・グローバル非汚染）。uv 不在ならスキップして案内（install は失敗しない）。"
      echo ""
      echo "auto 判定: Cargo.toml→rust / go.mod→go / pyproject.toml→python / lean-toolchain→lean4 /"
      echo "          *.cabal→haskell / kotlin(\"jvm\")+manifest無→kotlin / package.json→typescript /"
      echo "          settings.gradle・build.gradle・pom.xml→standard / それ以外→minimal"
      exit 0
      ;;
    *)
      echo "エラー: 不明なオプション '$1'" >&2
      echo "使い方: sh install.sh --help" >&2
      exit 1
      ;;
  esac
done

# ---- プロファイル未指定時: 対話選択 ----
if [ -z "$PROFILE" ]; then
  echo "=== gatecrate インストーラ ==="
  echo ""
  echo "プロファイルを選択してください:"
  echo "  1) minimal  — 汎用コア衛生のみ（PR タイトル・シークレット・ファイルサイズ）"
  echo "  2) standard — minimal + Android-JVM アダプタ（テストスメル等）"
  echo "  3) full     — standard 全体 + ドメインモデル検査（Alloy・設計段階のルール退行ゲート）"
  echo "  4) brownfield — minimal + 差分カバレッジ ratchet（テスト無し/希薄なレガシー向け）"
  echo ""
  printf "番号を入力 [1-4]: "
  read -r choice
  case "$choice" in
    1) PROFILE="minimal" ;;
    2) PROFILE="standard" ;;
    3) PROFILE="full" ;;
    4) PROFILE="brownfield" ;;
    *) echo "エラー: 無効な選択 '$choice'" >&2; exit 1 ;;
  esac
fi

# ---- auto: スタック自動判定 ----
# 対象ディレクトリのビルド定義ファイルからスタックを推定し、プロファイルを選ぶ。
detect_profile() {
  d="$1"
  [ -f "$d/Cargo.toml" ] && { echo "rust"; return; }
  [ -f "$d/go.mod" ] && { echo "go"; return; }
  [ -f "$d/pyproject.toml" ] && { echo "python"; return; }
  [ -f "$d/lean-toolchain" ] && { echo "lean4"; return; }
  ls "$d"/*.cabal >/dev/null 2>&1 && { echo "haskell"; return; }
  # Kotlin/JVM shares Gradle with Android; pick kotlin only when the kotlin jvm plugin is
  # present and there is no AndroidManifest (otherwise fall through to standard = android-jvm).
  if [ -f "$d/build.gradle.kts" ] && grep -q 'kotlin("jvm")' "$d/build.gradle.kts" 2>/dev/null \
     && ! find "$d" -name AndroidManifest.xml 2>/dev/null | grep -q .; then
    echo "kotlin"; return
  fi
  [ -f "$d/package.json" ] && { echo "typescript"; return; }
  for g in "$d"/settings.gradle* "$d"/build.gradle* "$d/pom.xml"; do
    [ -f "$g" ] && { echo "standard"; return; }
  done
  echo "minimal"
}
if [ "$PROFILE" = "auto" ]; then
  PROFILE="$(detect_profile "$TARGET_DIR")"
  echo "自動判定: スタックから profile='$PROFILE' を選択（--target ${TARGET_DIR}）"
fi

# ---- プロファイル検証 ----
case "$PROFILE" in
  minimal|brownfield|standard|full|python|go|typescript|rust|kotlin|haskell|lean4) ;;
  *)
    echo "エラー: 不正なプロファイル '$PROFILE'. auto/minimal/brownfield/standard/full/python/go/typescript/rust/kotlin/haskell/lean4 のいずれかを指定してください。" >&2
    exit 1
    ;;
esac

echo "=== gatecrate インストーラ ==="
echo "プロファイル : $PROFILE"
echo "インストール先: $TARGET_DIR"
echo ""

# ---- インストール先ディレクトリ準備 ----
mkdir -p "$TARGET_DIR/scripts"

# ---- スクリプトのインストール関数 ----
# kit の core(../..)/adapter(../../..) 相対深度を、インストール先 scripts/(..) の1階層へ畳む。
# git rev-parse でルートを解決する消費モデルのスクリプトは raw コピー（後述・byte 一致維持）。
install_script() {
  src="$1"
  dest_dir="$2"
  name="$(basename "$src")"
  if [ ! -f "$src" ]; then
    echo "  [SKIP] $name (not found: $src)"
    return
  fi
  # git-first スクリプトは raw コピー（byte 一致を保つ。畳み込むと sync-check が偽ドリフトを出す）。
  if grep -q 'rev-parse --show-toplevel' "$src"; then
    cp "$src" "$dest_dir/$name"
    echo "  [OK]   $name (raw, git-first)"
  else
    # Legacy relative-path script: collapse the repo-root depth (core "/../.." or adapter
    # "/../../..") to the consumer's single "/.." level.
    sed -E 's#/\.\.(/\.\.)+#/..#g' "$src" > "$dest_dir/$name"
    echo "  [OK]   $name"
  fi
  chmod +x "$dest_dir/$name"
}

# ---- STEP 1: 汎用コア層 ----
echo "--- 汎用コア層をインストール中 ---"
CORE_SCRIPTS="$SCRIPT_DIR/core/scripts"

# minimal プロファイル: コア衛生スクリプト（全プロファイル共通）
install_script "$CORE_SCRIPTS/check-conventional-title.sh" "$TARGET_DIR/scripts"
install_script "$CORE_SCRIPTS/check-no-committed-secrets.sh"  "$TARGET_DIR/scripts"
install_script "$CORE_SCRIPTS/check-file-line-limit.sh"      "$TARGET_DIR/scripts"
# 生存証明プローブ（ROADMAP P4・二階ループの入口）: 上の予防ゲートが「黙って壊れていない」ことを
# 合成違反注入で機械判定する。harness-liveness-converge ワークフローのコマンドゲートでもある。
install_script "$CORE_SCRIPTS/probe-gate-liveness.sh"       "$TARGET_DIR/scripts"
# テスト scaffold のコンパイル検査（ignored テストもビルドされる）: rule-reflect の scaffold-compiles
# ゲート用。stack/auto プロファイルは standard ブロックを通らないため minimal core に置く（全消費者に出荷）。
install_script "$CORE_SCRIPTS/check-test-compiles.sh"       "$TARGET_DIR/scripts"
# POSIX 移植性ゲート: 出荷スクリプトを #!/bin/sh・bashism なしに保ち、bash/zsh/fish・Windows Git Bash/WSL で
# 同じく動くことを機械保証する（消費者が独自スクリプトを足す場合の回帰防止にもなる）。
install_script "$CORE_SCRIPTS/check-posix-portability.sh"   "$TARGET_DIR/scripts"

# ---- standard-core: スタック非依存の汎用ゲート（minimal 以外の全プロファイル）----
# 特定スタックに依存しない汎用ゲート。sync-manifests の全スタック core_scripts に合わせ全プロファイルへ配布。
if [ "$PROFILE" != "minimal" ] && [ "$PROFILE" != "brownfield" ]; then
  # ROI 二階ループの計測（gatecrate-evaluate スキルが消費）: CI 履歴→ゲート別 発火/コスト集計。
  install_script "$CORE_SCRIPTS/collect-gate-history.sh"    "$TARGET_DIR/scripts"
  # EN/JA ドキュメント同期ゲート: 対の片側だけ編集した PR を検知（手作業同期のドリフト防止）。
  install_script "$CORE_SCRIPTS/check-doc-currency.sh"      "$TARGET_DIR/scripts"
  # ルール→ドキュメント鮮度ゲート: 規則担持コードを変えたら対応文書も更新（or Docs-Impact: 宣言）を強制。
  install_script "$CORE_SCRIPTS/check-rule-doc-currency.sh" "$TARGET_DIR/scripts"
  # 消費スクリプトのドリフト検査（消費者側）: consumed_scripts が pin 版と byte 一致か再検査。
  install_script "$CORE_SCRIPTS/check-kit-drift.sh"         "$TARGET_DIR/scripts"
  # マージ整合性の検出（auto-merge レース）: PR 最終 head がマージに含まれるか検証（検出のみ）。
  install_script "$CORE_SCRIPTS/check-merge-integrity.sh"   "$TARGET_DIR/scripts"
  # ハード制約（コンテンツ不変条件）ゲート: forbid/require で意図の境界を機械強制（無設定なら skip）。
  install_script "$CORE_SCRIPTS/check-hard-constraints.sh"  "$TARGET_DIR/scripts"
  # mutation エスカレーション検出（一次層）: Stop hook が force-pass した記録を CI で検出し PR を止める。
  install_script "$CORE_SCRIPTS/check-mutation-escalation.sh" "$TARGET_DIR/scripts"
  # ミューテーション範囲エンジン（A+B 戦略・docs/mutation-strategy.md）: adapter の run-mutation.sh が
  # diff(PR)/full(nightly) を決めるのに使う共通ツール（ゲートではない）。無くても run-mutation は full にフォールバック。
  install_script "$CORE_SCRIPTS/mutation-scope.sh"          "$TARGET_DIR/scripts"
  # ハーネスダッシュボード（docs/harness-dashboard.md）: ゲートの型/生存/ROI判定を $GITHUB_STEP_SUMMARY に描画する
  # 描画ツール（not-a-gate）と、その2つのデータ源（型分類・ROI判定）。CI に1ステップ足すと Actions 実行ページが
  # ダッシュボードになる。いずれもゲートではない（CI を落とさない）。
  install_script "$CORE_SCRIPTS/render-harness-dashboard.sh" "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/classify-gate-type.sh"      "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/gate-roi-verdict.sh"        "$TARGET_DIR/scripts"
  # メタゲート: 採用した reject 型ゲートに挙動テストが在るかを機械強制（testless ゲートの出荷を止める）。
  install_script "$CORE_SCRIPTS/check-gate-tests.sh"         "$TARGET_DIR/scripts"
  # イベントストーミング文法ゲート（docs/event-storming-grammar.md）: es-lint は型付き .es の文法を機械強制する
  # 予防ゲート（event→event 等を reject）、es-render は .es を座標なしで Mermaid 射影する描画ツール（not-a-gate）。
  install_script "$CORE_SCRIPTS/es-lint.sh"                 "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/es-render.sh"              "$TARGET_DIR/scripts"
  # PR 前のローカル一括ゲート: 導入済みスクリプトを自動検出して実行（CI 前の早期フィードバック）。
  install_script "$CORE_SCRIPTS/pr-preflight.sh"            "$TARGET_DIR/scripts"
  # 依存表（THIRD_PARTY_NOTICES）の鮮度ゲート（TPN_* 設定。無設定なら安全 pass）。
  install_script "$CORE_SCRIPTS/check-third-party-notices.sh" "$TARGET_DIR/scripts"
  # リリース版名 guard: git タグ vs VERSION_NAME の再利用検知（ALLOW_VERSION_NAME_REUSE で許可）。
  install_script "$CORE_SCRIPTS/check-release-version-name.sh" "$TARGET_DIR/scripts"
  # リポ初期設定ヘルパー: ブランチ保護（必須チェックは REQUIRED_CHECKS で指定・既定なし）。
  install_script "$CORE_SCRIPTS/setup-branch-protection.sh" "$TARGET_DIR/scripts"
  # Fitness 計測（advisory・ゲートではない）: 複雑度（PMD ベース・COMPLEXITY_LANG 設定可）と結合度。
  install_script "$CORE_SCRIPTS/measure-complexity.sh"      "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/measure-coupling.sh"        "$TARGET_DIR/scripts"
  # Balanced Coupling 3次元（strength×distance×volatility）と、その悪化だけを止める ratchet ゲート。
  install_script "$CORE_SCRIPTS/measure-modularity.sh"      "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/check-modularity-ratchet.sh" "$TARGET_DIR/scripts"
  # ES living-model 一式（docs/es-living-model.ja.md）: 情報完全性・cmap 文法・学習ビューア・
  # 横断ハブ・TO-BE 達成計測・evidence ドリフト・用語の平易さ・成果物完全性。
  install_script "$CORE_SCRIPTS/es-lint-info.sh"            "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/es-cmap-lint.sh"            "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/es-render-html.sh"          "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/es-render-cmap-html.sh"     "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/es-coverage.sh"             "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/check-es-evidence.sh"       "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/check-es-deliverables.sh"   "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/check-jargon.sh"            "$TARGET_DIR/scripts"
  # レガシードメイン分析の深さ・真実性ゲート（legacy-domain-extraction スキルの機械層）。
  install_script "$CORE_SCRIPTS/check-bc-domain.sh"         "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/check-evidence-resolves.sh" "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/check-term-relations.sh"    "$TARGET_DIR/scripts"
  # 意味的正しさの4層（docs/es-living-model.ja.md「意味的正しさの4層」）: 主張の実行可能化・
  # refute 記録の鮮度・レビュー工程への mutation testing。
  install_script "$CORE_SCRIPTS/check-es-assertions.sh"     "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/check-model-refuted.sh"     "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/probe-semantic-liveness.sh" "$TARGET_DIR/scripts"
  # measure-complexity の PMD ルールセット（消費者が未指定時のフォールバック先 scripts/quality/）。
  if [ -f "$CORE_SCRIPTS/quality/complexity-ruleset.xml" ]; then
    mkdir -p "$TARGET_DIR/scripts/quality"
    cp "$CORE_SCRIPTS/quality/complexity-ruleset.xml" "$TARGET_DIR/scripts/quality/complexity-ruleset.xml"
    echo "  [OK]   quality/complexity-ruleset.xml"
  fi
fi

# ---- brownfield: 差分カバレッジ ratchet レーン（テスト無し/希薄なレガシーの最初の線）----
if [ "$PROFILE" = "brownfield" ]; then
  echo ""
  echo "--- brownfield レーン（ratchet 型テストレーン）をインストール中 ---"
  # このPRで追加/変更した行だけに被覆を要求（絶対 floor はレガシー初日に落ちてゲートごと外される）。
  install_script "$CORE_SCRIPTS/check-diff-coverage.sh"        "$TARGET_DIR/scripts"
  # characterization（golden-master）の安全網: 未承認スナップショットのコミットを reject。
  install_script "$CORE_SCRIPTS/check-no-received-approvals.sh" "$TARGET_DIR/scripts"
fi

# ---- standard/full 追加: リリース/バージョニング系ユーティリティ ----
# （check-test-smells は下の Android-JVM アダプタ層が配布する）
if [ "$PROFILE" = "standard" ] || [ "$PROFILE" = "full" ]; then
  install_script "$CORE_SCRIPTS/version-check.sh" "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/version-env.sh"   "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/version-show.sh"  "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/start-work.sh"    "$TARGET_DIR/scripts"
  install_script "$CORE_SCRIPTS/prepare-play-store-screenshot.sh" "$TARGET_DIR/scripts"
fi

# full のみ: ドメインモデル検査（Alloy）。ドメイン学習ループの「実行可能な出口」——alloy スキル/
# rule-reflect が生む .als を CI で回し、ルール退行を実装より手前で止める（既定 advisory・java/jar 不在で skip）。
# 状態複雑性が高く設計段階で形式仕様を持つ（持ちたい）リポ向けゆえ full に限定（full の差別化要素）。
if [ "$PROFILE" = "full" ]; then
  install_script "$CORE_SCRIPTS/check-domain-model.sh" "$TARGET_DIR/scripts"
fi

# ---- STEP 2: Android-JVM アダプタ層（standard/full のみ）----
if [ "$PROFILE" = "standard" ] || [ "$PROFILE" = "full" ]; then
  echo ""
  echo "--- Android-JVM アダプタ層をインストール中 ---"
  ADAPTER_SCRIPTS="$SCRIPT_DIR/adapters/android-jvm/scripts"
  if [ -d "$ADAPTER_SCRIPTS" ]; then
    found=0
    for f in "$ADAPTER_SCRIPTS"/*.sh; do
      [ -f "$f" ] || continue
      install_script "$f" "$TARGET_DIR/scripts"
      found=$((found + 1))
    done
    if [ "$found" -eq 0 ]; then
      echo "  [INFO] adapters/android-jvm/scripts に移植済みスクリプトがありません"
    fi
  else
    echo "  [INFO] adapters/android-jvm/scripts が存在しません"
  fi
fi

# ---- STEP 2b: 単一スタックアダプタ層（python/go/typescript/rust）----
case "$PROFILE" in
  python|go|typescript|rust|kotlin|haskell|lean4)
    echo ""
    echo "--- $PROFILE アダプタ層をインストール中 ---"
    STACK_ADAPTER_SCRIPTS="$SCRIPT_DIR/adapters/$PROFILE/scripts"
    if [ -d "$STACK_ADAPTER_SCRIPTS" ]; then
      for f in "$STACK_ADAPTER_SCRIPTS"/*.sh; do
        [ -f "$f" ] || continue
        install_script "$f" "$TARGET_DIR/scripts"
      done
    else
      echo "  [INFO] adapters/$PROFILE/scripts が存在しません"
    fi
    ;;
esac

# ---- STEP 2c: ハーネスダッシュボードの初期スナップショット ----
# インストール直後から「リポから見えるダッシュボード」を用意する（docs/harness-status.md）。
# 以後の鮮度維持は core/workflows/dashboard.yml を .github/workflows/ に配線すれば自動 PR で行われる。
if [ -f "$TARGET_DIR/scripts/render-harness-dashboard.sh" ]; then
  echo ""
  echo "--- ダッシュボード初期スナップショット ---"
  mkdir -p "$TARGET_DIR/docs"
  # 推移グラフ用の履歴を当日 1 点でシード（2 点目以降で折れ線が現れる）。
  ( cd "$TARGET_DIR" && DASHBOARD_DIR=scripts sh scripts/render-harness-dashboard.sh --counts ) \
       > "$TARGET_DIR/docs/harness-history.tsv" 2>/dev/null || rm -f "$TARGET_DIR/docs/harness-history.tsv"
  if ( cd "$TARGET_DIR" && DASHBOARD_DIR=scripts DASHBOARD_HISTORY=docs/harness-history.tsv \
         sh scripts/render-harness-dashboard.sh --snapshot ) \
       > "$TARGET_DIR/docs/harness-status.md" 2>/dev/null; then
    echo "  [OK]   docs/harness-status.md（リポからゲートの型/生存/ROI判定＋数字/グラフが見える）"
    echo "         自動更新＋推移グラフ蓄積: core/workflows/dashboard.yml を .github/workflows/ に配線（要 Actions の PR 作成許可）"
  else
    rm -f "$TARGET_DIR/docs/harness-status.md" "$TARGET_DIR/docs/harness-history.tsv"
    echo "  [INFO] ダッシュボード生成をスキップ（git repo 外など）。CI で job-summary 版は利用可"
  fi
fi

# ---- STEP 3: 設定ファイル（harness.config.sh）の生成 ----
# 各スクリプトは ROOT 解決後に `. harness.config.sh` で source する（シェル変数を読む）ので、
# 生成するのは harness.config.sh（YAML ではない）。固有設定は消費者側に置き kit は汎用のまま。
echo ""
echo "--- 設定ファイル ---"
CONFIG_TEMPLATE="$SCRIPT_DIR/templates/harness.config.sh.example"
CONFIG_DEST="$TARGET_DIR/harness.config.sh"
if [ ! -f "$CONFIG_TEMPLATE" ]; then
  echo "  [WARN] templates/harness.config.sh.example が見つかりません" >&2
elif [ -f "$CONFIG_DEST" ]; then
  echo "  [SKIP] harness.config.sh は既に存在します（上書きしません）"
else
  cp "$CONFIG_TEMPLATE" "$CONFIG_DEST"
  echo "  [OK]   harness.config.sh（テンプレートから生成）"
fi

# ---- STEP 3b: cc-sdd 連携（--with-cc-sdd 指定時のみ）----
# cc-sdd は .kiro/ 前提の opt-in。指定時は (1) cc-sdd 本体を npx で scaffold し、(2) その上に
# gatecrate 自身の custom steering を重ね、(3) 機械的裏打ちの Stop hook まで入れる。順序が重要:
# 先に cc-sdd が .kiro/ とエージェントコマンドを作り、後から steering+hook を足すことで「cc-sdd は
# 素のまま・gatecrate の loop（判断層 steering ＋ 機械層 hook）だけ注入」が成立する。
# hook を同梱するのは、steering（prompt）だけでは validate-impl が「緑テストのみ」で終われてしまい、
# survivor-strict mutation の裏取り（学びのフィードバック）が機械的に保証されないため。
if [ "$WITH_CCSDD" = "1" ]; then
  echo ""
  echo "--- cc-sdd 連携 ---"

  # (1) cc-sdd 本体を npx で scaffold（agent/lang は env で上書き可。既定は Claude Code 日本語）。
  #     npx --yes は npx 自身の「パッケージを入れて良いか」確認を抑止（非対話化）。
  CC_SDD_AGENT="${CC_SDD_AGENT:---claude-skills}"   # 例: --codex-skills / --cursor-skills
  CC_SDD_LANG="${CC_SDD_LANG:-ja}"                   # 例: en / zh / ko ...
  if command -v npx >/dev/null 2>&1; then
    echo "  [RUN]  npx --yes cc-sdd@latest $CC_SDD_AGENT --lang ${CC_SDD_LANG}（${TARGET_DIR}）"
    if ( cd "$TARGET_DIR" && npx --yes cc-sdd@latest "$CC_SDD_AGENT" --lang "$CC_SDD_LANG" ${CC_SDD_FLAGS:-} ); then
      echo "  [OK]   cc-sdd を scaffold（.kiro/ とエージェントコマンドを生成）"
    else
      echo "  [WARN] cc-sdd の scaffold に失敗（ネットワーク/権限等）。手動で 'npx cc-sdd@latest $CC_SDD_AGENT --lang $CC_SDD_LANG' を実行してください" >&2
    fi
  else
    echo "  [WARN] npx が見つかりません（Node.js 未導入）。cc-sdd 本体はスキップ。" >&2
    echo "         Node.js 導入後に 'npx cc-sdd@latest $CC_SDD_AGENT --lang $CC_SDD_LANG' を実行してください。" >&2
  fi

  # (2) gatecrate の custom steering を .kiro/steering/ に重ねる（cc-sdd が無くても steering 単体で機能）。
  STEERING_SRC="$SCRIPT_DIR/templates/kiro-steering/gatecrate-spec-test-loop.md"
  STEERING_DEST="$TARGET_DIR/.kiro/steering/gatecrate-spec-test-loop.md"
  if [ ! -f "$STEERING_SRC" ]; then
    echo "  [WARN] cc-sdd steering テンプレが見つかりません" >&2
  elif [ -f "$STEERING_DEST" ]; then
    echo "  [SKIP] .kiro/steering/gatecrate-spec-test-loop.md は既に存在します"
  else
    mkdir -p "$TARGET_DIR/.kiro/steering"
    cp "$STEERING_SRC" "$STEERING_DEST"
    echo "  [OK]   gatecrate steering を .kiro/steering/ に配置"
  fi

  # (3) 機械的裏打ちの Stop hook（「緑テストだけ」では validate-impl を終えられないよう mutation を強制）。
  HOOK_SRC="$SCRIPT_DIR/templates/hooks/spec-test-mutation-gate.sh"
  HOOK_DEST="$TARGET_DIR/.claude/hooks/spec-test-mutation-gate.sh"
  if [ ! -f "$HOOK_SRC" ]; then
    echo "  [WARN] Stop hook テンプレが見つかりません" >&2
  else
    if [ -f "$HOOK_DEST" ]; then
      echo "  [SKIP] .claude/hooks/spec-test-mutation-gate.sh は既に存在します"
    else
      mkdir -p "$TARGET_DIR/.claude/hooks"
      cp "$HOOK_SRC" "$HOOK_DEST"
      chmod +x "$HOOK_DEST"
      echo "  [OK]   Stop hook を .claude/hooks/ に配置"
    fi
    # settings.json: 無ければ生成、在れば手動マージを案内（POSIX sh で JSON はマージしない）。
    SETTINGS_DEST="$TARGET_DIR/.claude/settings.json"
    if [ -f "$SETTINGS_DEST" ]; then
      echo "  [WARN] .claude/settings.json が既存。hooks.Stop を手動マージしてください（templates/hooks/settings-stop-hook.json 参照）" >&2
    else
      cp "$SCRIPT_DIR/templates/hooks/settings-stop-hook.json" "$SETTINGS_DEST"
      echo "  [OK]   .claude/settings.json に Stop hook を登録"
    fi
    # arm マーカーを .gitignore（無ければ追記）。
    GI_DEST="$TARGET_DIR/.gitignore"
    if [ ! -f "$GI_DEST" ] || ! grep -qF '.kiro/.gatecrate-mutation-pending' "$GI_DEST"; then
      printf '\n# gatecrate spec-test: Stop hook の mutation arm マーカー\n.kiro/.gatecrate-mutation-pending\n' >> "$GI_DEST"
      echo "  [OK]   .gitignore に mutation arm マーカーを追記"
    fi
  fi
fi

# ---- STEP 3c: エージェント・ループ・ツールの配布（--with-skills 指定時のみ）----
# 二階ループ／規則 reflect の orchestration（TAKT）とエージェントスキルは「どのプロジェクトが使うか」が
# 判断事項なので opt-in。指定時のみ consumer の .claude/skills/ と .takt/ に配置する。
if [ "$WITH_SKILLS" = "1" ]; then
  echo ""
  echo "--- エージェント・ループ・ツール ---"
  # (1) 消費者向けスキル: Alloy モデル生成と二階ループ評価。
  for s in alloy-spec-model-generator gatecrate-evaluate; do
    SK_SRC="$SCRIPT_DIR/.claude/skills/$s"
    SK_DEST="$TARGET_DIR/.claude/skills/$s"
    if [ ! -d "$SK_SRC" ]; then
      echo "  [WARN] skill $s が kit に見つかりません" >&2
    elif [ -d "$SK_DEST" ]; then
      echo "  [SKIP] .claude/skills/$s は既に存在します"
    else
      mkdir -p "$TARGET_DIR/.claude/skills"
      cp -R "$SK_SRC" "$SK_DEST"
      echo "  [OK]   skill $s を .claude/skills/ に配置"
    fi
  done
  # (2) TAKT 一式（config + workflows + personas）を .takt/ に配置（テンプレからコピー）。
  if [ -d "$SCRIPT_DIR/templates/takt" ]; then
    if [ -d "$TARGET_DIR/.takt" ]; then
      echo "  [SKIP] .takt は既に存在します（手動マージしてください）"
    else
      cp -R "$SCRIPT_DIR/templates/takt" "$TARGET_DIR/.takt"
      echo "  [OK]   TAKT 一式を .takt/ に配置"
    fi
  fi
fi

# ---- build/ を .gitignore に追加（check-test-smells.sh 副作物対応）----
GITIGNORE="$TARGET_DIR/.gitignore"
if [ -f "$GITIGNORE" ]; then
  if grep -qF 'build/' "$GITIGNORE"; then
    echo "  [SKIP] .gitignore に build/ は既に記載済み"
  else
    printf '\n# gatecrate: check-test-smells.sh の中間ファイル出力先\nbuild/\n' >> "$GITIGNORE"
    echo "  [OK]   .gitignore に build/ を追記"
  fi
fi

# ---- STEP 3d: headroom（AIエージェント向けコンテキスト圧縮）の導入（--with-headroom 指定時のみ）----
# gatecrate のエージェント側（skills/cc-sdd/TAKT）を補完する任意ツール。CI ゲートの核（依存ゼロのシェル）には
# 触れない。uv tool install で分離環境に入れる（消費者のグローバル Python を汚さない・uv 必須ルール準拠）。
# uv 不在や導入失敗でも install 全体は失敗させない（任意機能）。
if [ "$WITH_HEADROOM" = "1" ]; then
  echo ""
  echo "--- headroom（AIコンテキスト圧縮・任意）---"
  if command -v uv >/dev/null 2>&1; then
    if uv tool install "headroom-ai"; then
      echo "  [OK]   headroom を uv tool で導入（'headroom --help' で確認・gatecrate のエージェント側を補完）"
    else
      echo "  [WARN] headroom の導入に失敗（PyPI 到達不可など）。後で 'uv tool install headroom-ai' を手動実行可" >&2
    fi
  else
    echo "  [SKIP] uv が見つかりません。uv 導入後に 'uv tool install headroom-ai'（pip 直接実行は避ける）"
  fi
fi

# ---- STEP 4: 完了メッセージ ----
echo ""
echo "==========================================="
echo "  gatecrate インストール完了！"
echo "  プロファイル: $PROFILE"
echo "==========================================="
echo ""
echo "次のステップ（詳しい手順は docs/usage.md）:"
echo "  1. 生成された harness.config.sh を編集（スクリプトはこれを source します）"
echo "     ファイル行数ゲート: FILE_LINE_LIMIT / FILE_LINE_NAMES / FILE_LINE_PATHS"
case "$PROFILE" in
  standard|full) echo "     ミューテーション: BUILDCONFIG_PACKAGE / TARGET_CLASSES / TARGET_TESTS（Android-JVM）" ;;
  python)        echo "     カバレッジ: COVERAGE_SOURCE / COVERAGE_THRESHOLD / MUTATION_THRESHOLD（Python）" ;;
esac
echo "  2. CI にゲートを配線: core/workflows/ci.yml をベースに、必要なアダプタ workflow を追加"
echo "     ダッシュボード: docs/harness-status.md を生成済み（リポから見える）。最新維持は"
echo "     core/workflows/dashboard.yml を .github/workflows/ に配置（要 Actions の PR 作成許可）。詳細 docs/harness-dashboard.md"
echo "  3. （任意）エージェントの仕様駆動学習ループ / cc-sdd 連携 → docs/spec-driven-loop.md"
if [ "$WITH_CCSDD" = "1" ]; then
  echo "     gatecrate steering ＋ Stop hook を配置済み（cc-sdd 本体の導入状況は上のログ参照）"
  echo "     モードは harness.config.sh の SPEC_LOOP_MODE。導入後 'sh scripts/run-mutation.sh' で実走確認を"
else
  echo "     有効化: 再実行で --with-cc-sdd を付与（cc-sdd を npx で導入）。詳細は spec-driven-loop.md"
fi
if [ "$WITH_SKILLS" = "1" ]; then
  echo "  4. エージェント・ループ・ツール配置済み（.claude/skills/ ＋ .takt/）。CI への workflow 配線"
  echo "     （domain-model-check / merge-integrity / harness-drift-check）は gatecrate-setup を参照"
else
  echo "  4. （任意）二階ループ/形式手法を使うなら --with-skills（.claude/skills + TAKT を配布）"
fi
if [ "$WITH_HEADROOM" = "1" ]; then
  echo "  5. headroom（AIコンテキスト圧縮）導入を試行済み（上のログ参照）。'headroom wrap claude' 等で利用"
else
  echo "  5. （任意）エージェントのトークン削減に headroom を使うなら --with-headroom（uv tool で分離導入）"
fi
echo ""
echo "  これで完了です。scripts/ 配下のファイルは、もうあなたのものです（版固定も同期も不要）。"
echo "  （任意・複数PJを束ねるチーム向け）更新追跡は sync-manifest を導入（README の Advanced 参照）。"
echo ""
echo "詳細: https://github.com/Yos-K/gatecrate"
