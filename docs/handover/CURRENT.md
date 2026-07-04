# 引き継ぎ資料（CURRENT）

このファイルは、AIが突然利用不能になっても人間が作業を引き継げるよう、直近の改修の状態・根拠・
次アクションを記録する。一連の作業完了時に `docs/handover/archive/YYYY-MM-DD_NN.md` へ移す。
（〜2026-06-19 の P4 二階ループ構築〜型分類 step1 の経緯は `archive/2026-06-20_01.md` 参照。）

## 現在の状態

**最直近: JVM 限定機能の多言語化（2026-07-03・本ブランチ）**。ユーザー要望「JVMのみ機能が進んでいるので
他言語対応を」に対し、洗い出した本丸2つを rust/typescript/python/go へ展開:

- **変更ファイル**: `check-diff-coverage.sh`（+lcov/gocover パーサ・対称サフィックス突合。lcov 絶対パス SF と
  go モジュールプレフィックスに対応）、`measure-coupling.sh`（COUPLING_LANG=java|python|go|typescript|rust の
  エッジ抽出器。モジュール=dir のドット結合・ts 相対 import 解決・rust use crate:: 小文字セグメント・
  go は PKG_PREFIX=go.mod モジュールパス必須・java 既定で後方互換）、`tests/test-check-diff-coverage.sh`
  14→22、`tests/test-measure-coupling.sh` 新設11、docs（test-selection-roi EN/JA にスタック別被覆生成表・
  code-quality-metrics・brownfield profile・setup skill）。
- **効果**: brownfield ratchet レーンが全主要スタックで使用可能に。**measure-modularity（distance・
  Balanced Coupling・ratchet）が非JVMで動く**（python end-to-end をテストで実証）。
- **判断の根拠**: ①複雑度（PMD）は言語ごとの native ツール依存が重く今回は見送り（docs に既存の限界記載
  のまま）②形式は lcov+gocover の2つで4言語をカバー（cobertura 等は需要が出てから）③非JVMのモジュール
  境界は「ディレクトリ」を正とした（言語の module 概念の差異をkitが吸収しない・pkgdist がそのまま効く）。
- **検証済み**: 全45スイート green・手動変異4体全滅（lcov cov固定/go hit固定/resolvemod素通し/normpath破壊）・
  shellcheck/posix/file-line pass・emit_edge の set -e 罠（&&連鎖が除外時に非ゼロ→ループ死）を踏んで修正。
- **次のアクション**: (1) 本ブランチをPR (2) 実消費者（rust/ts等）で brownfield レーンを実測
  (3) measure-complexity の多言語化は native ツール委譲方式（radon/gocyclo/eslint 等の薄いアダプタ）を
  検討事項として残す (4) haskell/lean4 は import 解析未対応（需要待ち・co-change は今日から効く）。

---

**最直近: 意味的正しさの4層ゲート実装（2026-07-03・本ブランチ）**。ユーザー問「意味的な正しさのゲート化の
いい方法」への回答を1〜4層すべて実装:

- **変更ファイル**: 新規=`check-es-assertions.sh`（第1層・test= のマイクロ検証を強制）＋
  `docs/model/assertions/`3本（probe exit解釈/レジストリ優先/型別ROI を実挙動でピン留め）、
  `check-model-refuted.sh`（第3層・反証記録の model-hash=git blob hash 鮮度）＋
  `docs/model/*.refutation.md`（敵対的レビュー実録）、`probe-semantic-liveness.sh`（第4層・文法非可視の
  意味違反3種を決定論注入し refuter の検出力を ALIVE/DEAD 判定）、挙動テスト3本。
  更新=`es-lint-info.sh` R11/R12（第2層・when↔out 三角測量＝実モデルの不一致を即検出・
  transitions↔states）、MUST_TEST/NON_GATE/8manifest、ci.yml ESモデルゲートを4層仕様に、
  `docs/es-living-model.ja.md` 4層の節、モデルに test= 付与と when=常時 修正。
- **実験結果**: 変異モデル（evidence 入替・既存ゲート全通過を確認）を独立 refuter に流し
  **両違反を名指し検出→ --verify ALIVE**。「捕まえないレビュアは壊れていても見えない」の死角を
  probe の相似形で塞げることを実測。
- **検証済み**: 全43テストスイート green・手動変異5体全滅（R11/R12/hash比較/握りつぶし/常時ALIVE）・
  shellcheck -S error clean・posix/file-line/gate-tests/gate-classified pass・sample への退行ゼロ
  （sample.es の既存 ERROR=3 は main と同一＝別課題）。
- **次のアクション**: (1) 本ブランチをPR (2) sample.es の既存 R1/R2 ERROR 3件の解消は別PR
  (3) 未ピン主張5件（cmd_collect 等の decide）への test= 追加はホットスポット優先で漸進
  (4) 第4層の定期運用（refute 記録更新時に probe を1本流す）は TAKT ワークフロー化の候補。
- **注意事項**: R11 は「常時」を許容語として特別扱い（policies.md の「常時なら明記」規約と整合）。
  R12 は to|fail の fail 側（失敗の帰結）を免除＝ミニ言語ヘッダの文法例と整合。反証記録の質そのものは
  機械保証されない——それを測るのが第4層、という層構造を崩さないこと。

---

**最直近: gatecrate 自身のドメインモデル構築＋self-harness へのESモデルゲート配線（2026-07-02・本ブランチ）**。
ユーザー要望「このツール自身のハーネスを更新し、ドメインモデルを構築して期待通りか評価」に対する consumer #0
ドッグフード。

- **変更ファイル**: 新規=`docs/model/harness.cmap`（BC5つ: 衛生/品質計測/二階ループ(core)/ES(core)/配布・
  導出根拠と決めること付き）、`docs/model/harness-meta.es`（AS-IS 21ノード・全ノード evidence=実コード行）、
  `docs/model/harness-meta-tobe.es`（TO-BE=AS-IS 維持＋workflow失敗通知フロー3ノード追加）、
  `docs/model/harness-meta-es.html`（6タブビューア射影）、`docs/model/harness-hub.html`（全体マップハブ射影）。
  更新=`.github/workflows/ci.yml`（self-harness に es-lint/es-lint-info/check-es-evidence/es-cmap-lint を
  ブロックで、es-coverage を advisory で配線）、`core/scripts/es-coverage.sh`＋`tests/test-es-coverage.sh`
  （実バグ修正: becomes= 突合先を「TO-BE 全ノード」に。actor への正当な対応を不整合と誤報していた）。
- **評価結果（要点）**: 機械ゲート全 ERROR=0・evidence 全解決・TO-BE 達成 16/19。敵対的レビュー12指摘中
  10件を裏取りの上反映——最重要は「pol_triage の因果逆流」（escalation-only の除外は DEAD 後の分岐でなく
  **probe 前のマーカー分割**＝exp3 対策の本体。エッジと decide を実装に合わせ再構成）と evidence の意味ズレ
  5件（関数ヘッダ/docstring 行→ロジック本体行へ）。反証に耐えた項目11件（exit code 解釈・型別ROI判定表・
  レジストリ単一ソース・Conformist ext_gha 等）。残置2件=dashboard 自動PR再生成フローとトレンド readmodel
  （別スライスで扱う・本モデルは21ノードで可読性優先）。
- **ドッグフーディングの副産物**: ①es-coverage の実バグ発見・修正（上記）②私自身の編集ミス
  （置換の部分一致で evidence が :188→:1238 に化けた）を es-coverage が stale として即検出＝
  「ドリフト/捏造を機械で弾く」設計の実地証明。
- **次のアクション**: (1) 本ブランチを PR (2) 残りBC（衛生/ES/品質計測/配布）の .es スライス化——ハブの
  「ESモデル未作成」一覧が作業キュー (3) TO-BE の missing 3（workflow 失敗通知）の実装判断は人間へ
  (4) 別スライス候補: dashboard 自動PR再生成フロー。
- **注意事項**: モデルの意味的正しさは文法ゲートでは保証されない（今回の因果逆流は全ゲート green のまま
  存在した）——敵対的レビューをモデル作成の必須工程にすべき、が最大の学び。

---

**前回: TO-BE 達成計測（es-coverage）＋横断コンテキストマップのハブHTML（2026-07-02・PR #134）**。
ユーザー要件「①ESモデル↔コード対応・AS-IS/TO-BEギャップ・コミット毎の進捗可視化 ②複数リポ束ね時に
複数AS-ISが単一TO-BEへ収束し重複して見える→cps-meta の cps-context-map.html のような横断ハブが欲しい
③実装モデルの可視化（アルゴリズム等の認知負荷対策）」の 段階1+2 を実装:

- **変更ファイル**: 新規=`core/scripts/es-coverage.sh`（advisory 160行・TO-BE evidence の集合演算で
  implemented/stale/missing を導出・達成率とギャップ一覧・AS-IS `becomes=` 突合。EVIDENCE_CODE_ROOT は
  check-evidence-resolves と同名・解決規則も同一）、`core/scripts/es-render-cmap-html.sh`（not-a-gate 163行・
  横断 `.cmap`→ハブHTML。`domain=`=subgraph 群化・`es=`=クリック遷移先・無ければ「ESモデル未作成」一覧）、
  `tests/test-es-coverage.sh`（9性質14アサーション）、`tests/test-es-render-cmap-html.sh`（8性質11）。
  更新=`classify-gate-type.sh`（NON_GATE に es-render-cmap-html）、`sync-manifests/*.yaml`（8スタック）、
  `docs/context-map-grammar.ja.md`（domain=/es= 属性とハブ節）、`docs/es-living-model.ja.md`（coverage節）、
  `CHANGELOG.md`。
- **判断の根拠**: ①対応台帳は evidence リンクに一本化（新台帳を作らない）②status は導出値＝源泉に
  書き戻さない ③達成度に LLM 判断を使わない（ゲームされ揺れる）④TO-BE 重複は表示でなく「源泉が複数」の
  構造問題→横断 `.cmap` 1つに一本化しハブは射影 ⑤click/色をAIに手書きさせない（座標手描き問題の再発防止）。
- **検証済み**: 全38テストスイート green、手動変異4体全滅（stale偽装/種別フィルタ/クリック全付与/kind無視）、
  shellcheck -S error clean、posix/gate-classified/gate-tests/file-line/hard-constraints pass、
  サンプル（書店 .cmap/.es）で end-to-end 実走（cmap-lint OK→ハブ2.7KB生成・coverage 0/15 missing を正しく報告）。
- **次のアクション**: (1) 本ブランチを PR（参照: `docs/context-map-grammar.ja.md` ハブ節・
  `docs/es-living-model.ja.md` coverage節）(2) 段階3=ビューアへの coverage 色オーバーレイ＋
  es-status snapshot（推移折れ線・dashboard.yml パターン再利用）(3) 段階4=コマンド単位呼出チェーンの
  実装ビュー（`.spec` コマンド evidence 起点・JVM から。真理の向きが反転＝コードから導出、の設計は
  会話ログ参照）(4) cps-meta 側で横断 `.cmap` を起こし実データでハブを検証。
- **注意事項**: es-coverage の対象種別は ES_COVERAGE_KINDS で可変（既定はコードになる6種別）。
  ハブの click 遷移先（es=）は相対パス＝生成HTMLの置き場所基準。進捗ゲート化するなら ratchet
  （達成率が前回を下回ったら reject）にする——水準述語は TO-BE 追記（分母増）を罰するため不可。

---

**前回: アーキテクチャ品質ゲート（Balanced Coupling 3次元 + ratchet + 判断層スキル）を新設（2026-07-02・PR #130）**。
ユーザー要望「コード品質やアーキテクチャの品質をゲートにしたい（参考: vladikk/modularity）」に対し、既存
`measure-coupling.sh`（strength×volatility の2次元・distance 未実装は docs 明記の既知欠落）を土台に3層で実装:

- **変更ファイル**: 新規=`core/scripts/measure-modularity.sh`（advisory・バランス式
  `BALANCE=(STRENGTH XOR DISTANCE) OR NOT VOLATILITY` を評価、RED=強×遠×変動/YELLOW=弱×近×変動、
  seam: `MODULARITY_EDGES_FILE`/`MODULARITY_VOLATILITY_FILE`）、`core/scripts/check-modularity-ratchet.sh`
  （prevention・`modularity-baseline.tsv` に無い新規 RED のみ reject・`--emit-baseline` で brownfield 初期化）、
  `tests/test-measure-modularity.sh`（9性質16アサーション）、`tests/test-check-modularity-ratchet.sh`（7性質12）、
  `templates/modularity-strength.tsv.example`、`.claude/skills/modularity-review/SKILL.md`（判断層）。
  更新=`probe-gate-liveness.sh`（`modularity` injector・REJECT_GATES・kit dogfood specs）、
  `check-gate-tests.sh`（MUST_TEST）、`sync-manifests/*.yaml`（8スタック）、`docs/code-quality-metrics.md`、`CHANGELOG.md`。
- **判断の根拠**: ①vladikk/modularity は LLM 判断のスキル（CC BY-NC-SA・非商用）→本文は取り込まず
  Balanced Coupling モデルを独自実装。②strength の4段階（contract<model<functional<intrusive）は意味論的
  判断で機械計測不能→分業3層（計測=機械/分類=modularity-review スキルが `modularity-strength.tsv` に証拠つき
  記入/承認=人間）。③絶対 floor はレガシー初日に落ちゲートごと外される→diff-coverage と同じ ratchet 型。
  ④未分類エッジは既定 model で評価+作業キュー化（黙って通さない・黙って塞がない）。
- **検証済み**: 全38テストスイート green、手動変異4体全滅（RED条件のdistance/volatility項・comm方向・exit 1）、
  probe 生存証明 ALIVE、shellcheck -S error clean、posix/file-line/hard-constraints/gate-tests/gate-classified 全 pass。
- **次のアクション**: (1) 済——PR #130 として起票済み
  (2) JVM 実消費者（cps-meta 等）で `--emit-baseline` から実測（参照: `docs/code-quality-metrics.md` の
  Modularity 節、`templates/modularity-strength.tsv.example`）(3) 済——gatecrate-setup Phase 6.5 に
  採用手順（計測→凍結→強制→分類）を追記、Phase 7 の injectable kind に modularity を追加
  (4) 済——ダッシュボード陳腐化の根本原因を特定・修理: render は正常で、dashboard.yml の
  `gh pr create` がリポ設定「Allow GitHub Actions to create and approve pull requests」無効により
  6/27以降全実行失敗していた（handover に要設定と記載済みだったが未適用）。設定を有効化（人間承認済み）、
  失敗実行の残骸ブランチ `chore/dashboard-refresh-*` 17本を削除、dispatch で success + 自動PR #133
  （18→29ゲート・ES系欠落解消）を確認。以後は nightly / core変更push で自動追従する。
- **注意事項**: measure-modularity は JVM 前提（COUPLING_PKG_PREFIX 必須）。kit 自身（shell-only）では
  edges が空になるため ratchet を kit CI に配線していない（probe は seam 注入で JVM 不要）。
  ベースラインへの自動追記はスキルに禁止させている（負債受入は人間の承認事項）。

---

**前回: 全ドキュメント・全スクリプト文言の総点検（PR #131・2026-07-02）**。4並列レビューで洗い出し全指摘を
裏取りして修正（26ファイル +81/-55）。**実バグ1件**: `render-harness-dashboard.sh:29` の `$GATE_DIR_`
未定義変数参照（set -eu 下で classify 不在時の意図した skip(exit 0) がハードエラー化）→ `${GATE_DIR}` に修正・
実行確認済み。**実態とのズレ9件**: README/structure の「core=10本」等の固定数→概数化（正確な台帳は
dashboard へ委譲）、「core/workflows は空」（実際5本）、「消費形はパイロット2本のみ」（実際 core 全移行済み）、
CONTRIBUTING/usage の誤スクリプト名（check-file-sizes.sh→check-file-line-limit.sh、run-mutation はアダプタ別名を
明記）、full プロファイルの過大表現、probe kind 列挙の陳腐化、es-lint-info ヘッダの R7 欠落、ROADMAP「現状」見出し。
**表現6件**（「検出は称さない」「バレ丸投げ」等）。**意図的に対象外**: test-selection-roi.ja のリンク修正
（ja片側編集を doc-currency が弾く・PR単位の免除経路なし＝**ゲート設計ギャップとして要検討**）、
event-storming-grammar.md のリネーム（外部参照破壊）、[汎用コア]/[汎用core] 表記揺れ（15ファイル・実害薄）、
歴史記録（archive/evaluations/CHANGELOG 過去節）。全38テストスイート green・CI pass。
関連: 同日 PR #130（Balanced Coupling アーキテクチャ品質ゲート）＝上のエントリ。

---

（それ以前の完了済みエントリは `archive/2026-07-02_01.md` へ移動。）
