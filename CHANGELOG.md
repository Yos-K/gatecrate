# Changelog

All notable changes to this project will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **ADR 運用を自リポに強制（ドッグフード）**: feat/fix コミットに `ADR-Review:` トレーラを CI で必須化
  （Rust 版 adr-review ゲートを self-CI に配線。消費者向けは従来どおり sh 版——役割分離は ADR-0002）。
  移植境界を「層」から「判定の構造性」へ差し替え（ADR-0002: 構造判定は Rust・正規表現1本は sh が正解・
  awk 30行閾値・probe-gate-liveness 互換の制約を明文化）。ADR-0001（ソース配布第一）とあわせ
  `docs/adr/` を新設。

### Added
- **Alloy 収束ループと意図反例ゲート（TAKT `spec-model-converge` ＋ `check-intended-counterexample.sh`）**:
  `check-domain-model.sh` は自らを「ドメイン学習ループの実行可能な出口」と定義しているが、ループ自体は
  未表現だった（`harness-rule-reflect` は assert を scaffold するだけで converge-to-green ではない）。
  反例駆動の反復——検査→反例を読む→**モデルの誤りか仕様の誤りか**を判断→修正→再検査——は
  alloy-spec-model-generator スキルの散文に暗黙化していた＝ループ規律が判断層にあった。
  収束させる際の構造的リスクは「`expect 0` → `expect 1` と宣言すれば必ず緑にできる」こと（最も安い
  逃げ道でありモデリング判断に見える＝characterization trap の Alloy 版）。exp3 の知見どおり persona
  ルールでは抑えられないため防御は決定論に置いた——新ゲートが理由（`intended: <why>`）のない
  `expect N>0` を reject する。**宣言を禁じるのではなく理由を強制する**（本リポの
  `ADR-Review: none (<reason>)` と同型）。両ゲートを同一ステップの quality gate に並べ、
  「諦めて緑」が「赤のまま」と同じ強さで落ちるようにした。挙動テスト10性質・REJECT_GATES へ注入器
  つきで登録（生存証明あり）・全 sync-manifest に配布登録。
- **modularity 分類のバッチ処理（TAKT `modularity-classify-batch` ＋ `measure-modularity.sh --emit-queue`）**:
  modularity-review の完了条件は機械判定可能だが、作業の実体は収束でなく**分類**（各エッジの src を
  読んで共有知識量を判定する）であり、行ごとに「緑にする」対象が無い。よって converge ではなく
  arpeggio（data-driven batch）で回す。TAKT の組み込みデータソースは CSV 固定（区切り `,`・ヘッダ必須）
  で TSV を列分解できないため、未分類エッジを `build/quality/modularity-queue.csv` に出す
  `--emit-queue` を追加（挙動テスト2性質）。ワークフローは分類の正しさを検証せず（スキル自身が
  機械検証不能と明記）、baseline も触らない。`concurrency` を上げる前の警告を明記——「迷ったら強い側に
  倒す」は判断層の規律で、1エッジあたりの文脈が薄くなると守られにくく、**弱い誤分類の方向が高くつく**
  （RED を取り逃がしゲートが黙る）。
- **Rust 移植 Phase 0（#rust-port・docs/design/rust-port-plan.md の実装着手）**: ハーネスの2原型を型として実装。
  **Gate 原型** = `gatecrate-harness`（intent/population/criterion/coherence/evidence/finding/report の層。
  「検査不成立(exit 2)」と「違反0」を型で分離し、設定ミスが緑に化ける経路を構造で排除）＋
  `gatecrate-gates`（adr-review・interaction-traceability の2本。証拠層差し替えで実 git 不要の検査23件）。
  **Projection 原型** = `gatecrate-model`（.es/.cmap/.cld/.spec 共通の行レコード文法と型）＋
  `gatecrate-render`（Mermaid/内蔵データ/Markdown/ビューア組み立て）。CLI は clap（`gatecrate check …` /
  `gatecrate es render-html …`）。

### Changed
- **`es-render-html.sh` を Rust 実装へのシムに置換（800行 → 28行）**: 呼び出し面・exit code 契約
  （0/1/2）・出力は完全互換。等価性はゴールデン6本（最小〜実モデル104KB〜sample一式）の
  **バイト一致**で証明し、既存スモークテスト49件はシム経由で Rust 実装を検証する。
  CI は挙動テスト前に `cargo build --release`（実測 ~9s・配布形態判断の材料）。
  binary 未ビルド時は「黙って劣化」せず exit 2 で明示エラー。

## [v0.12.0] - 2026-07-20

### Added
- **interaction command traceability ガード `check-interaction-command-traceability.sh`（consumer実証→汎用化, #27）**:
  契約台帳（PSV: state_id|command|implementation|implementation_locator|test|test_locator）の各行について
  **state+command → モデル遷移 → 実装 path+locator → 挙動テスト path+locator** の連鎖を検査。切断5種
  （遷移なし・evidence ファイル欠落・locator ドリフト・未契約の実装マーカー・契約重複）で PR を止める。
  「ADR と構造テストが在るのにモデルにコマンドが無く、緑のモデルが実装を守らない」という consumer の
  実欠陥（localmd-reader PR #18: scroll_menu）への回答。増分採用の基準（高リスク・新規・変更・探索由来
  のみ契約化。一括要求はプレースホルダテストを誘発するため不可）を台帳雛形
  `templates/interaction-command-contracts.psv.example` に成文化。設定面は INTERACTION_CONTRACTS/
  TRANSITIONS/SOURCE_ROOT（harness.config.sh）。挙動テスト19件・手動変異4体全滅。

## [v0.11.0] - 2026-07-20

### Added
- **ポータブル ADR レビュー宣言ゲート `check-adr-review.sh`（consumer実証→汎用化, #25）**: feat/fix コミットに
  `ADR-Review:` トレーラを**ちょうど1つ**要求し、参照 ADR の実在・随伴文書（対訳）・必須セクションを
  **宣言コミット時点**で構造検査する（HEAD に後から足しても通らない）。`none (<理由>)` の許可は
  `ADR_ALLOW_REASONED_NONE` で制御、裸の `none` は常に fail。解決不能な base は skip でなく明示 fail(exit 2)。
  設定面（対象タイプ・ADR置き場・サフィックス・必須セクション）はすべて `harness.config.sh`。
  `--message` モード＋ commit-msg フックテンプレ（`templates/hooks/adr-review-commit-msg.sh`）で
  コミット時の早期フィードバック層も同梱（ロジックはゲート本体に一本化）。挙動テスト25件・手動変異4体全滅。
  消費者プロトタイプ: localmd-reader PR #13。

### Added
- **オントロジー・ライト（存在論カテゴリの導入）**: `.es` に `is=kind|role|phase|relator`（種/役割/相/関係子）・
  `kind-of=`（is-a。下位は上位の不変条件を引き継ぐ）・`role-of=`（役割の担い手）・`alias=`（別名）を追加。
  `es-lint-info` に **R15**（役割に担い手が無い/カテゴリ矛盾）/**R16**（is-a の未解決warn・循環error）。
  ビューアはカテゴリバッジ・上位概念/担い手/別名の表示・用語集に「分類(is-a)」節、alias はクロスリンクに合流。
  「Xの一種か、Xを生成するルールか」「同名でも立場で別概念か」という概念モデル先行の判断を機械検査に。

### Changed
- **`legacy-domain-extraction` skill を progressive disclosure 化（情報最小化）**: 常時ロードの SKILL.md を
  279→111行に削減（規律＝品質バー・ES意味規律ダイジェスト・フェーズ索引のみ）。手順詳細は
  `reference/extraction.md`（Phase 1-5,7-9）と `reference/modeling.md`（Phase 6〜6.8）へ分離し、
  各 Phase 着手時に読む方式に。「強いモデルほど全情報を渡さず必要時に探索」の実践。

### Added
- **cron が仕事を生成する（実行の置き場をローカルPCからクラウドへ）**: 消費側テンプレ `templates/workflows/`
  を新設——`es-evidence-drift.yml`（日次: モデルとコードの乖離を検査し、壊れたら issue 起票・緑復帰で自動クローズ）と
  `harness-roi.yml`（週次: 発火履歴からROI判定＋ダッシュボードをSummaryへ。消費側=localmd-readerで実証済みの汎用化）。
  gatecrate 自身も `.github/workflows/es-drift.yml` で同型を dogfood（docs/model の日次ドリフト検査）。

### Added
- **interaction-storming 完結性ゲート `check-interaction-storming.sh`（consumer実証→汎用化, #6）**: UI探索から
  蒸留した状態表(PSV)を入力に、各画面状態に**完結・離脱・回復**の手段が available_commands 内に揃い evidence が
  実在することを行番号つきで検査。「ダイアログに閉じる手段がない」等の“流れが完結しない”欠陥をUI自動操作の
  前段で止める。**探索はゲートにせず、蒸留された状態表の整合性だけをゲートにする**（docs/exploratory-to-smoke.md）。

### Added
- **動詞・状態に「ドメイン上の意味」（辞書カードの semantics 強化）**: `transitions=名:from->to|fail // 意味`・
  `states=名 // 意味` の記法を追加（behaviors の `//定義` と同形）。「オーソリする＝決済手段に支払い枠を確保する
  （まだ金銭は動かない）」「受信＝チャージ要求を受け取り決済が未着手の局面」のように、名前だけでは分からない
  業務上の意味を動詞カード・状態カード・集約詳細の先頭に表示。`es-lint-info` に **R13**（動詞の意味未定義）/
  **R14**（状態の意味未定義）を追加し、既存 R12（未宣言state）を `//` 記法対応に修正。

### Added
- **辞書カード（動詞が暗黙に生む状態区別の展開）**: 用語集タブに、`transitions=` から機械導出する動詞カード
  （シグネチャ＝前提状態を型として受ける／**受理パネル＝全状態の✓と✗（✗は防いでいる事故：二重実行等）**／
  前提状態を生む動詞＝能力の供給網／実装指針＝実行時チェックでなく引数の型で受ける）と、
  状態カード（双対：この状態でできること・できないこと・生む動詞）を追加。
  「決済する」という語が「決済可能／不可能」の区別を暗黙に生む——を可視化する。

### Fixed
- **公開treeの生成物除去**: Android-JVM adapter配下に誤って追跡されていたGradle実行cacheを削除し、
  nested `.gradle` directoryのignoreと自己衛生テストを追加。
- **ダッシュボードsnapshotへ Next action 列を反映（#1・#152のフォローアップ）**: 生成済み `docs/harness-status.md` が
  旧4列のままだったため、workflowと同一コマンドで再生成。`not-probed`/ROI未確定の各行に次の保守アクションが出る。
- **OS メタデータの自己ハイジーンテスト（#2）**: `.DS_Store` 等が tracked に無いこと・`.gitignore` の予防エントリが
  在ることを毎CIで検証する `tests/test-no-os-metadata.sh` を追加（現mainに混入は無し・予防を機械化）。

### Fixed
- **localmd-reader からのフィードバック5件（#149-153）**: (#152) ハーネスダッシュボード
  `render-harness-dashboard.sh` に **Next action 列**を追加し、`not-probed`/DEAD/untyped/ROI未確定 の各非終端状態を
  具体的な保守アクションに接続（テスト更新）。(#149) `docs/design/expansion-loop.md` を実態に整合——
  `harness-coverage-deepen`/`-expand` を「設計済・未配布」と明記（配布物に無いものを implemented と書かない）。
  (#150) README/usage（日英）の導入フローに **`--with-skills`（エージェント駆動ループ）** を明記。
  (#151) `standard` プロファイルが**スタック中立でない（Android-JVM）**ことを明記、既定例を `--profile auto` に。
  (#153) 探索的UI発見を安定スモークへ蒸留する再利用パターン `docs/exploratory-to-smoke.md` を追加。
- **出荷サンプル AS-IS（sample.es）の es-lint-info ERROR 3件を解消**: R1（evt_done/evt_fail に fields= 無し）
  R2（agg_svc に構造無し）を AS-IS の実態表現で補完——agg_svc の fields に「決済状態コード:[0|1|2]
  （各所が部分解釈・正典定義なし）」＝hotspot hs_pay の実体を表出。evt_done の決済状態コードには R5
  （フラグ/コードの臭い）が意図どおり点灯し、「AS-IS の臭い→TO-BE で状態機械へ昇格」という教材の筋書きと
  becomes= の記述が一致する形に。
- **全ドキュメント・全スクリプト文言の総点検（4並列レビューで洗い出し・全指摘を裏取りの上で修正）**:
  実バグ1件——`render-harness-dashboard.sh` の `$GATE_DIR_`（未定義変数参照。`set -eu` 下で classify 不在時の
  意図した skip(exit 0) がハードエラーに化け、メッセージからディレクトリ名も欠落）を `${GATE_DIR}` に修正。
  実態とズレた記述——README/structure の「core=10本」「android-jvm 27本」を概数表記に（正確な台帳は
  dashboard に委譲）、「core/workflows は空のプレースホルダ」（実際は5 workflow あり）、「check-file-sizes.sh が
  消費形パイロット・残りは順次移行」（実際は core 全移行済み）、CONTRIBUTING の 300行ゲート名
  （check-file-sizes.sh→check-file-line-limit.sh）、usage の mutation スクリプト名（アダプタ別に明記）と
  汎用例（check-file-line-limit.sh へ）、full プロファイルヘッダ（mutation/Alloy/smoke「含む」→「将来追加する器」）、
  probe kind 列挙（3種→全一覧参照へ）、setup skill の「v0.3.1 時点で消費形2本」。
  文言——es-lint-info ヘッダに R7 説明を補完（本体は R7 を出すのにカタログに無かった）、classify の Usage に
  --explain を追記、「検出は称さない」「バレ丸投げ」等の崩れた日本語、EN タイポ（"there nothing"）、
  ROADMAP「現状」見出し→「起点スナップショット」、plugin manifest の ES 略語展開、check-kit-drift の重複行削除。

### Added
- **JVM 限定機能の多言語化（rust / typescript / python / go）**: ①`check-diff-coverage.sh` に
  `COVERAGE_FORMAT=lcov`（rust=cargo llvm-cov / typescript=vitest / python=coverage lcov）と
  `gocover`（go test -coverprofile ネイティブ）を追加——brownfield ratchet レーンが全主要スタックで
  使える。lcov の絶対パス SF・gocover のモジュールプレフィックスに対応する対称サフィックス突合へ拡張。
  ②`measure-coupling.sh` に `COUPLING_LANG=java|python|go|typescript|rust` のエッジ抽出器を追加
  （モジュール=COUPLING_SRC 相対ディレクトリのドット結合・ts は相対 import をファイル位置から解決・
  rust は use crate:: の小文字セグメント・go は go.mod モジュールパス必須）——**measure-modularity
  （distance・Balanced Coupling・ratchet）が非JVMで動く**ことをテストで実証（python end-to-end）。
  挙動テスト: diff-coverage 14→22・measure-coupling 新設11（計7言語プロパティ・手動変異4体で検出力確認）。
  docs（test-selection-roi にスタック別の被覆生成表・code-quality-metrics・brownfield profile・setup skill）更新。
- **配布経路の完全一致（install.sh ⟷ sync-manifests の双方向欠落を解消）**: install.sh に未配布だった
  16本（ES living-model 一式・意味的正しさ4層・measure-modularity/ratchet・レガシー分析3ゲート・
  prepare-play-store-screenshot）を standard-core/standard 層へ、manifest 未登録だった8本（dashboard
  3点セット=旧handover の宿題・diff-coverage/no-received-approvals/bc-domain/evidence-resolves/
  term-relations）を全8スタックへ登録し、**両方向の差集合ゼロ**に。さらに `--profile brownfield` を
  installer に新設（対話メニュー4番・minimal 基盤+diff-coverage+no-received-approvals・standard-core は
  含めない＝profiles/brownfield.yaml.example の仕様どおり）。test-install.sh を 19→29 アサーションへ拡張
  （standard-core の新規5本・brownfield 境界・minimal からの除外）。
- **install.sh の挙動テストを新設（489行・12文書が参照する配布入口が無テストだった穴を閉じる）**:
  `tests/test-install.sh`（8性質19アサーション）——profile 境界（minimal は standard-core を含まない）・
  harness.config.sh の非上書き（固有設定保護）・git-first スクリプトの byte 一致 raw copy（差分ゼロ同期の
  前提）・--profile auto のスタック判定・不正入力 reject・dashboard 初期スナップショット・導入先での
  ゲート実走と消費者 config の実効。手動変異2体（config 上書き化・raw copy 無効化）で検出力確認。
- **意味的正しさの4層ゲート（因果逆流が全ゲート green で潜んだ実害への対策）**: 意味は直接判定できない
  ので「意味的誤りが生き残れない構造」を4層で機械化。①`check-es-assertions.sh`（prevention）——
  decide=/invariant= を `test=` のマイクロ検証スクリプトへ翻訳させ「存在し・exit 0」を強制（1主張=2反映の
  モデル版）。自モデルの中核3主張（probe の exit 解釈・レジストリ優先偽装不能・型別ROI判定表）を
  docs/model/assertions/ でピン留め。②`es-lint-info.sh` に R11/R12（三角測量・warn）——policy の out= ↔
  エッジ when=（常時を許容）、transitions の from/第1遷移先 ↔ states=（to|fail の fail 側は帰結として免除）。
  R11 が自モデルの実不一致（pol_verdict の when=判定可）を即検出→修正。③`check-model-refuted.sh`
  （prevention）——反証記録（model-hash=git blob hash・指摘・反証耐性項目）の存在と鮮度を強制
  （rule-doc-currency の「モデルが変わったら再レビューも」版）。敵対的レビュー実録を
  docs/model/*.refutation.md に固定。④`probe-semantic-liveness.sh`（tool）——文法を通過する意味違反
  （evidence差替/decide入替/when入替）を決定論注入し refute 工程の検出力を ALIVE/DEAD で測る＝
  レビュー工程への mutation testing（probe-gate-liveness の相似形）。挙動テスト4本（9+13+8+13 アサーション・
  手動変異4体で検出力確認）、MUST_TEST/NON_GATE/全stack manifest 登録、ci.yml の ESモデルゲートを4層仕様に、
  `docs/es-living-model.ja.md` に4層の節。
- **gatecrate 自身のドメインモデル（consumer #0 ドッグフード）+ self-harness への ESモデルゲート配線**:
  `docs/model/harness.cmap`（BC 5つ＝衛生/品質計測/二階ループ/ES/配布・導出根拠つき・ハブHTML射影）と
  中核BC「二階ループ（ハーネス自己評価）」の AS-IS/TO-BE `.es`（evidence は実コード行・全ノード）を新設。
  ci.yml の self-harness に es-lint / es-lint-info / check-es-evidence / es-cmap-lint（ブロック）+
  es-coverage（advisory・TO-BE達成を毎回表示）を配線＝自分のモデルを自分のゲートで守る。
  敵対的レビューで高2件（トリアージの因果逆流＝除外は probe 前の構造・evidence の意味ズレ）を含む
  10指摘を裏取りの上で反映。ドッグフーディングの副産物として es-coverage の実バグ
  （becomes= の突合先を coverage 対象種別に限定→actor への正当な対応を「モデル不整合」と誤報）を
  発見・修正（回帰テスト追加・変異殺傷確認）。TO-BE 達成 16/19（missing 3 ＝ workflow失敗通知フロー）。
- **TO-BE 達成の計測（es-coverage）＋横断コンテキストマップのハブHTML（es-render-cmap-html）**:
  ①`es-coverage.sh`（advisory）— TO-BE `.es` の evidence リンクを座標系に、各ノードを
  implemented（evidence が実コードに解決）/ stale（解決しない=ドリフト）/ missing（未実装ギャップ）へ
  決定論分類し、TO-BE 達成率・ギャップ一覧・AS-IS `becomes=` 突合（宙づり id・新規能力）を出す。
  LLM の達成度判断を使わない・導出 status を源泉に書き戻さない。対象はコードになる種別のみ
  （actor/external/hotspot は要求しない）。②`es-render-cmap-html.sh`（not-a-gate）— 複数リポ・複数 AS-IS が
  単一 TO-BE に収束すると BC別ビューアでは TO-BE が重複して見える問題に対し、横断 `.cmap` 1つを源泉として
  全体コンテキストマップのハブHTMLへ決定論射影。`domain=` で subgraph 群化・`kind=` で色分け・`es=` を持つ
  BC はクリックで各 ES ビューアへ遷移（click 行は属性から機械生成）・`es=` の無い BC は「ESモデル未作成」
  として一覧＝モデリング作業キュー。挙動テスト2本（9性質14 + 8性質11 アサーション・手動変異4体で検出力確認）、
  classify NON_GATE 登録、全 stack manifest 同梱、`docs/context-map-grammar.ja.md`（domain=/es= とハブ）・
  `docs/es-living-model.ja.md`（coverage）更新。サンプル（書店 .cmap/.es）で end-to-end 実走確認。
- **アーキテクチャ品質ゲート（Balanced Coupling 3次元 + ratchet）**: `measure-modularity.sh`（advisory）が
  vladikk のバランス式 `BALANCE = (STRENGTH XOR DISTANCE) OR NOT VOLATILITY` を機械評価——distance は
  パッケージ木距離（measure-coupling の既知の欠落を解消）、volatility は git 履歴、strength の質的4段階
  （contract<model<functional<intrusive）は判断層が `modularity-strength.tsv` に証拠つきで分類し機械は
  consume するだけ。`check-modularity-ratchet.sh`（prevention）は既知違反を `modularity-baseline.tsv`
  （`--emit-baseline` で brownfield 初期化）に凍結し**新規の RED（強い×遠い×変動）だけを reject**する
  ratchet（絶対 floor はレガシー初日に落ちてゲートごと外される＝diff-coverage と同じ設計判断）。
  判断層は新スキル `modularity-review`（Integration Strength の分類・台帳保守・是正提案）が担う。
  挙動テスト2本（16+12 アサーション・手動変異4体で検出力確認）、probe 生存証明（`modularity` injector・
  seam 注入で JVM 不要）、`check-gate-tests` MUST_TEST 登録、全 stack manifest へ同梱。
  概念は vladikk/modularity（CC BY-NC-SA）の本文を取り込まず Balanced Coupling モデルを独自実装。
  `docs/code-quality-metrics.md` に3次元の定義・閾値・ratchet の設計根拠を追記。
- **成果物完全性ゲート＋完成ループ（手抜き＝TO-BE省略 等を機械で止める）**: `check-es-deliverables`（AS-IS/TO-BE/
  コンテキストマップ/ビジネス分析源泉(biz=)/分析レポートが揃い文法も通る＝6タブの源泉を D1-D6 で検証）を新設。
  TAKTワークフロー `es-complete`（audit→produce を反復し、完成ゲート exit 0 を権威に成果物の欠落を埋める）を追加。
  完成は「スキルの自己レビュー（判断）」でなく「ゲート（機械判定）＋TAKTループ」で強制する設計に。skill 完了判定に組込。
- **ES意味規律の機械ゲート（cps-meta 全リポ分析が毛玉化・非ドメインイベント混入した実害への対策）**:
  `es-lint-info` に R9（1図のノード>40＝毛玉化 → 1BCスライスに分割）/ R10（取得・照会・ロック等の問合せ・
  技術操作を event 化＝非ドメインイベントの疑い → リードモデル化/除外）を追加。`es-lint` のコレオグラフィ型文法を
  補完（`command → 集約|外部システム`、`event → policy|アクター`、`external → errorevent`。イベントは集約/外部の後・
  コマンド直後でない、を機械強制）。`legacy-domain-extraction` skill に「真のドメインイベントのみ・アクター起点・
  1図=1BCスライス・render前にWARN→0収束」、`docs/context-map-grammar.ja.md` に「複数リポ・境界混在の進め方
  （リポ≠BC）」を明記。
- **ES living-model ツールキット（イベントストーミングを「育てる」ドメイン知識資産）**: 予防ゲート `es-lint-info`
  （情報完全性 R1-R8）・`es-cmap-lint`（コンテキストマップ文法）・`check-es-evidence`（evidenceドリフト）・
  `check-jargon`（用語の平易さ）と、学習ビューア `es-render-html`（AS-IS/TO-BE/コンテキストマップ/用語集/
  ビジネス分析/分析レポートの6タブ自己完結HTML、markdown決定論射影、Ctrl+ホイール/ピンチでズーム）。
  TAKT収束ループ `.takt/es-converge`。`legacy-domain-extraction` skill に Phase 0(品質バー)/6.6(ビジネス分析・
  因果ループ調整案)/6.7(リファクタ+ハーネス計画)/6.8(永続化設計)を追加。文法 `docs/event-storming-grammar.md`・
  `docs/context-map-grammar.ja.md`・`docs/es-living-model.ja.md`。全ゲートに behaviorテスト、全stack manifestへ同梱。
- **Claude Code プラグインとして導入可能に**: `.claude-plugin/plugin.json`（skills=`.claude/skills` 参照、scriptsは
  `${CLAUDE_PLUGIN_ROOT}`）＋ `.claude-plugin/marketplace.json`（source=`./`）。`/plugin marketplace add` →
  `/plugin install` で導入し `gatecrate-setup` で配線。shell install は併存。
- **レガシードメイン分析を TAKT で制御するパイプライン（深さゲート `check-bc-domain` + ワークフロー + persona）**:
  ドメイン知識の深掘りはエージェントに任せると「深さ」がぶれ（浅すぎ/無限に掘る）、スキルの注意書きでは停止条件を強制
  できない。そこで「どこまでやるべきか」を機械ゲートで定義し TAKT で制御する。`core/scripts/check-bc-domain.sh`
  （prevention）が BC ドメイン知識文書の**規定の深さ**（用語>=N・各用語に定義/不変条件/evidence が非空・ユースケース流れ・
  hotspot）を機械判定（`BC_MIN_TERMS` 可変・JP/EN 見出し対応・BSD awk の多バイト `==` 罠を regex で回避）。
  `tests/test-check-bc-domain.sh`（7性質9アサーション）。`templates/takt/workflows/legacy-domain-analysis.yaml`
  が5フェーズ（俯瞰→BC地図→各BC深掘り→ハーネス→道筋）を各フェーズの command ゲートで制御し、深さ未達なら同ステップを
  再実行して深掘りを強制。`templates/takt/personas/legacy-domain-analyst.md` が判断（クラスタ選定・意図vs欠陥・BC境界・
  命名・優先）を供給。＝「TAKT が制御・persona が判断」。`check-gate-tests` の MUST_TEST に登録。
  - **真実性ゲート `core/scripts/check-evidence-resolves.sh`（prevention）**: 実走で「深さゲートはセルが非空かしか見ない→
    ソースを読めない agent が file:method を**捏造**して通す」抜け道を観測（TAKT 内 agent が実ファイルにアクセスできず
    `Foo.java:validateKanyushaCd()` 等の実在しないメソッドでゲームした）。本ゲートは evidence の file:line/file:method 参照が
    `EVIDENCE_CODE_ROOT` 配下の実コードに**解決するか**を機械検証し捏造を弾く。深さ(check-bc-domain)＋真実性(本ゲート)で対。
    `tests/test-check-evidence-resolves.sh`（7性質9アサーション）。ワークフローの deepen ゲートが両方を回すよう更新。
  - **用語間ルールゲート `core/scripts/check-term-relations.sh`（prevention）**: 全5フェーズ実走で「深さゲートは用語ごとの
    不変条件しか強制しない→**用語間のルール**（包含/多重度/ペア/整合/コンテキスト間の同一性）が抜ける」を観測（TAKT 生成の
    BC 文書に用語間ルールの節が無かった）。ゲートが強制しない次元は agent が手を抜く（捏造ゲーミングと同型）。本ゲートは
    「用語間のルール」節と、**型付き(包含/多重度/ペア/整合/同一性/依存)＋evidence** のルールを `TERM_REL_MIN` 個以上含むことを
    機械強制。`tests/test-check-term-relations.sh`（7性質8アサーション）。deepen ゲートを深さ＋真実性＋用語間ルールの3点に拡張。
- **レガシー（テスト無し）向け brownfield レーン — 差分カバレッジ ratchet ＋ characterization 安全網**: テストレーンが
  絶対 floor（`coverage>=80`）型ゲートしか出荷しておらず、テスト無しレガシーに入れると初日に必ず落ち→ゲートごと外され→
  安全網が育たない穴を埋める。概念モデルでは**水準述語**（あなたは十分良い）しか無く、レガシーに効く**導関数述語**
  （悪化していない/触った所は良くなる＝ratchet）が欠けていた。
  - `core/scripts/check-diff-coverage.sh`（detection）: 「このPRで追加/変更した行だけ」に被覆を要求する差分カバレッジゲート。
    入力は JaCoCo XML のみ（Kotlin/Android は kover/jacoco が出せる・`COVERAGE_FORMAT` でフォーマット拡張可）。判定（git diff の
    変更行 ∩ 被覆報告）はスタック非依存。外部 diff ドライバ（difftastic 等）対策に `--no-ext-diff`。`tests/test-check-diff-coverage.sh`
    （8性質14アサーション）。`profiles/brownfield.yaml.example`（minimal + diff-coverage）。
  - `core/scripts/check-no-received-approvals.sh`（prevention）: 未レビューの golden-master スナップショット（`*.received.*`）の
    コミットを reject ＝「未承認の挙動が仕様として紛れ込む穴」を機械強制で塞ぐ。`tests/test-check-no-received-approvals.sh`（6性質）。
  - `templates/characterization/`: 触る前に現挙動を固定する golden-master 雛形。依存ゼロのヘルパ（**Java** `Approvals.java` /
    **Kotlin** `Approvals.kt`）＋例テスト＋ `approve-characterization.sh` ＋ ループ正典化 `README.md`（分析→pin→意図/欠陥仕分け→
    リファクタ→ratchet）。
  - 解説 `docs/test-selection-roi.md`(EN/JA)「レガシー（テスト希薄）の入口」、setup skill に「テスト有無で standard/full or
    brownfield を分岐」「brownfield でリファクタ時は characterization を先に張る」を追記。
  - **実プロジェクトで end-to-end 実証**: 実運用の大規模 jacoco.xml（Maven 産・約8千計装行）で diff-coverage を検証中に
    `tr '>' '>\n'` が単一行 XML を分割できないバグを発見→ `awk RS=">"` に修正（fixture が複数行で見逃していた・単一行XMLの
    回帰テスト追加）。実 Java クラスタで「現挙動 pin→factory method 抽出リファクタ→characterization 緑維持→diff-coverage 100%」を
    通しで実証、わざとの挙動破壊も安全網が検知。Java ヘルパは JDK21 javac で実コンパイル＋実行スモーク確認。
- **`legacy-domain-extraction` スキル**: テストの無い手続き型レガシーから、ドメイン知識（用語の定義・用語固有の
  不変条件・用語間の関係）をハーネス構築駆動で抽出し概念モデル化する手順をエージェントに与える。手続き型コードは
  「読んで起こす」と精度が出ないため、characterization で挙動を pin → **mutation で未固定ルールを機械的に炙り出し**
  （生存ミュータント＝ルール候補）→ 宣言的配線/call graph から用語別の不変条件を実値で回収 → 用語・不変条件・関係の
  概念モデル＋hotspot を生成。必要に応じ形式モデル(Alloy)・探索的テスト(stateful PBT)へ。収束サブループは任意で TAKT
  委譲（`gatecrate-setup` Phase 9 と同型）。判断（クラスタ選定・意図vs欠陥分類・関係導出）はエージェントが担う。
- **イベントストーミング文法ゲート（`es-lint` / `es-render`）**: AIエージェントがESを構造的に不得意とする問題
  （根拠なきイベント生成・「ルール」を「集約」と誤ラベル・event→event 直結・不確実性の平滑化・drawio座標の手描き歪み）を、
  文法を**判断層から機械ゲートへ剥がす**ことで解く。`core/scripts/es-lint.sh`（prevention）が型付きテキスト `.es` の文法を
  強制し違反を reject（event→event / command→event＝集約スキップ / 不変条件なし集約 / 複数集約emit / 未宣言ノード参照）。
  `core/scripts/es-render.sh`（not-a-gate）が `.es` を**座標なしで Mermaid 射影**（AIは座標を書かない）。`.es` が source of
  truth、図はその決定論射影。`tests/test-es-lint.sh`（7性質12アサーション）。`classify-gate-type`（es-render を NON_GATE に）/
  `check-gate-tests`（es-lint を MUST_TEST に）へ登録。解説 `docs/event-storming-grammar.md`。オーケストレーション
  （harvest→classify→refute→model）は消費プロジェクト側が担い、kit は汎用ゲートの道具供給に純化。localmd-reader 文書
  サブドメイン（43ノード/58エッジ）で end-to-end 実証。**コードレビュー対応**: install.sh と全 sync-manifest に両スクリプト
  を登録（消費者の install/sync に乗せる）／es-render に `external` 型の shape と classDef を追加（lint通過モデルでも
  外部システムノードが壊れない）／es-lint が hotspot エッジを `marks` 以外なら reject（文法語彙を強制・doc と一致）。
- **ダッシュボードに CIコスト/発火 棒グラフ**: `DASHBOARD_FIRING_TSV`（`collect-gate-history` の出力・要 gh）を渡すと、
  **ゲート別 CI秒の棒グラフ（コスト上位8）**と**発火回数の棒グラフ（fires>0 のゲート）**を Mermaid xychart-beta で描画。
  「高コスト × 発火0 = removal-candidate」という剪定シグナルを可視化（ROI verdict 列と整合）。kit の live job-summary に
  発火履歴取得を配線（best-effort）。コミット型スナップショットは gh 非前提なので静的のまま（コスト節は live のみ）。テスト25性質。
- **`--with-headroom` 任意フラグ（AIコンテキスト圧縮ツール headroom の導入）**: `install.sh --with-headroom` で
  [headroom](https://github.com/chopratejas/headroom)（AIエージェントのトークンを 60-95% 削減するコンテキスト圧縮）を
  **`uv tool install` で分離導入**（消費者のグローバル Python を汚さない・uv 必須ルール準拠）。gatecrate のエージェント側
  （`.claude/skills`/cc-sdd/TAKT）を補完する位置づけで、**CI ゲートの核＝依存ゼロのシェルには触れない**（既存の
  `--with-cc-sdd`/`--with-skills` と同じ opt-in パターン）。uv 不在や導入失敗でも install 全体は失敗させず案内に留める。
  実環境で uv 経由 `headroom-ai 0.26.0` の導入と graceful-skip の両経路を実走確認。

### Changed
- **ダッシュボードを数字＋グラフで可視化**: `render-harness-dashboard.sh` に**メトリクスサマリ**（型別カウント・
  ✅ALIVE/❌DEAD/—not-probed の生存集計・全体ステータス行）と **Mermaid 円グラフ2枚**（型分布・予防ゲート生存）を追加。
  GitHub は markdown 内の Mermaid をネイティブ描画するので、コミット型 `docs/harness-status.md` でも**グラフが見える**。
  さらに「How gates are judged」**Mermaid フローチャート（型別の判定方法を図示）**を追加（gh 不要・静的レジェンド）。
  **推移グラフ**も追加: `render --counts` が日付つきカウント行を出し、`docs/harness-history.tsv` に**ゲート数が変わった時だけ**
  1 点記録（毎日 PR を出さない）。`DASHBOARD_HISTORY` を渡すと総ゲート数の時系列を **Mermaid xychart-beta（折れ線）**で描画
  （履歴 1 日なら「accruing」注記＝捏造しない）。`dashboard.yml`（kit/消費者テンプレ）が日次で履歴を更新、`install.sh` が
  当日 1 点でシード。既存の表は維持。テスト20性質（手動欠陥挿入で検証）。

### Added
- **インストール時にダッシュボードを作成（消費者展開）**: `install.sh` が**初期スナップショット `docs/harness-status.md`
  を生成**するようになり、インストール直後から「リポから見えるダッシュボード」が用意される（git repo 外などでは安全に
  スキップ）。以後の最新維持用に消費者テンプレ `core/workflows/dashboard.yml`（`scripts/**` パス・再生成→変更時のみ PR）を
  追加し、完了メッセージで配線を案内。kit の設計どおりワークフローは自動配置せずテンプレ提供（消費者が `.github/workflows/` へ
  配置）。`rust` プロファイルで install 実走し `docs/harness-status.md` 生成を確認済み。
- **リポから見えるダッシュボード（コミット型スナップショット + 自動PR再生成）**: ジョブサマリ版はリポをブラウズ
  しているだけでは見えない（Actions の各実行ページにしか出ない）ため、ゲート別ダッシュボードを
  `docs/harness-status.md` にコミットして**リポ上でインライン表示**できるようにした。`render-harness-dashboard.sh`
  に `--snapshot`（スタンドアロン見出し付き）を追加し生成を1箇所に集約（ローカル生成と CI が drift しない）。
  `.github/workflows/dashboard.yml`（nightly + ゲート変更 push + dispatch）が再生成し、**表が変わった時だけ PR を開く**
  （main 直 push せずブランチ保護を尊重＝提案→人間承認の gatecrate 流）。鮮度は git の最終コミット日時（毎回変わる時刻は
  入れないので無駄な PR が出ない）。README(EN/JA) を status スナップショットへリンク。job-summary 版には生成時刻を併記
  （`DASHBOARD_GENERATED_AT`）。
  - 注: 自動 PR にはリポ設定「Allow GitHub Actions to create and approve pull requests」が必要。
- **ハーネスダッシュボード（GitHub ネイティブ・A+B）**: 導入したゲートの状態を GitHub 上で一目で見られるように。
  (A) `core/scripts/render-harness-dashboard.sh`（新規・not-a-gate・TDD）が各ゲートを**型/生存/ROI判定**の1枚の
  markdown 表に描画し、CI が `$GITHUB_STEP_SUMMARY` に流す＝Actions 実行ページがそのままダッシュボードになる
  （既存の classify-gate-type・probe-gate-liveness・gate-roi-verdict を再利用・描画ツールなので CI を落とさない）。
  (B) README（EN/JA）に CI ワークフロー status バッジ（main が緑か一目）。kit 自身の ci.yml と全 adapter ci.yml に
  `if: always()` のダッシュボードステップを配線（adapter 側は未導入なら no-op のガード付き）。消費者向け手順を
  `docs/harness-dashboard.md` に記載。配布のため render/classify/gate-roi-verdict を install.sh に追加。
- **ミューテーション A+B 戦略（差分PR + nightlyフル）と共通エンジン**: 全アダプタのミューテーションゲートが
  毎PRで**全コード**を回して分単位で遅かったのを是正。新しい `core/scripts/mutation-scope.sh`（diff/full の範囲決定を
  全スタックで1度だけ実装・後方互換で既定 full・`MUTATION_SCOPE`/`MUTATION_DIFF_BASE`・挙動テスト付き）を軸に、
  各 `run-mutation.sh` を A+B 化:
  - **A=差分(PR)**: rust `cargo mutants --in-diff`／typescript `stryker --since`（ネイティブ）／python `mutmut --paths-to-mutate`／
    go はパッケージ限定（path-scoped）／kotlin・android-jvm の PIT は「変更 production source 無しなら SKIP」の床（schedule-first・
    ネイティブ per-line diff は plugin 要）。変更ソース無しなら全スタックで SKIP。
  - **B=フル(nightly)**: 各 `ci.yml`/`mutation.yml` に `schedule`（毎日3時）を追加し、PR=diff・push/schedule=full に分岐。
    差分モードが構造的に見ない「未変更コードの退行」を nightly フルが捕捉する。
  - 設計と**推奨ブランチ戦略**（trunk ベース・短命 feature branch・diff は merge-base 基準）を `docs/mutation-strategy.md` に正典化
    （per-stack 差分対応表つき）。`mutation-scope.sh` を install.sh と6 sync-manifest に追加（消費者へ配布）。

### Changed
- **CI lint ジョブの高速化（挙動テストを1ステップに統合）**: 約21個の `sh tests/test-*.sh` 個別ステップを
  `tests/*.sh` を回す単一ループに統合。各テストはサブ秒だが GitHub Actions のステップ固定 overhead が lint の
  実時間（実測 ~19s・大半が overhead）を支配していた。統合で overhead を1回に圧縮（lint ~19s→~11s・総時間 ~21s→~12s 見込み）。
  per-test の PASS/FAIL と失敗時の全出力ダンプでデバッグ性は維持。**副次効果**: glob で全テストを自動カバーし、
  「テストを足したが CI 配線を忘れる」drift を解消（`test-check-release-version-name.sh` が個別配線リストから漏れて
  CI で一度も実行されていなかったのを是正）。
- **`gatecrate-evaluate` skill に型分類と ROI verdict を結線**: Phase 1 で `classify-gate-type`（型を機械導出・
  手動で検出型/予防型を当てない）と `check-gate-classified`（untyped を判断材料つきで止める）を実行し、
  `collect-gate-history | gate-roi-verdict` で **axis-1 の型別 verdict を機械化**。Phase 2 はゼロから判定し直さず、
  verdict が人間に flag した条件（②独自性・prevention の risk-gone・advisory の consumed?・axis-2 維持負荷）だけを
  判断する形に再フレーム（§3.2＝仮説を証拠と照合）。中心原則テーブルと `harness-auditor` persona も同様に更新。

### Added
- **型別 ROI verdict（decision record §3 step3・§3 完結）**: `core/scripts/gate-roi-verdict.sh`（新規）を追加。
  `collect-gate-history` の発火 TSV（stdin）を**ゲートの型で解釈**して axis-1 の verdict を機械化する欠けた結節点。
  型を見ずに「発火0=無駄」とすると最重要の予防層を消す（反事実の罠）ため、型別に分岐: **prevention の fires=0 は keep**
  （罠回避・価値は liveness）／**detection fires=0 × 高コスト → removal-candidate**（②uniqueness は機械判定不能ゆえ人間に flag・
  提案のみ・自動削除しない）／detection fires=0 × 安価 → keep（removal ①コスト不成立で固定）／detection fires>0 → keep／
  advisory → human-judgment（信号が消費されるか・人間判断）／not-a-gate → skip。axis-2（consolidate/downgrade）・②uniqueness・
  prevention の risk-gone・advisory の consumed? は本 script では判定せず gatecrate-evaluate skill / 人間の領分（過剰主張しない）。
  挙動テスト `tests/test-gate-roi-verdict.sh`（7性質・固定 TSV・手動欠陥挿入で変異K/L 検出力確認）を lint に配線。verdict 自体は
  非ゲート（ROI tooling）なので classify の NON_GATE に登録（メタゲートが untyped 扱いしないため）。
- **untyped メタゲート（decision record §3 step2）**: `core/scripts/check-gate-classified.sh`（新規）を追加。
  ROI 剪定は各ゲートの型を要するが、型の無い（untyped）ゲートは「分類し忘れ」で剪定軸が決められない。本メタゲートは
  GATE_DIR の全 *.sh を `classify-gate-type.sh --one` にかけ、untyped が一つでもあれば fail（exit 1）。**失敗時は
  `--explain` の判断材料（証拠＋推論のはしご）を載せる**（§3.2＝バレ丸投げにしない）。叱るのは untyped のみ——advisory/
  not-a-gate は正当な終端で叱らず、**意味的誤分類は検出しない**（機械では不能・是正は人間 escalation）。挙動テスト
  `tests/test-check-gate-classified.sh`（5性質・手動欠陥挿入で検出力確認）を lint に、ゲート本体を self-harness に配線（blocking）。
  `check-gate-tests` の MUST_TEST にも追加。**kit を 0 untyped に収束**: 6つの未分類ゲートに根拠ある `# gatecrate-type:`
  マーカーを付与（check-test-compiles=detection／check-gate-tests=prevention／check-kit-drift・check-domain-model・
  measure-complexity・measure-coupling=advisory）→ 最終 prevention13／advisory4／detection1／not-a-gate10。

- **ゲート型分類の導出（decision record §3 step1 + §3.1 精緻化）**: `core/scripts/classify-gate-type.sh`（新規）を追加。
  ROI 剪定は「予防型で発火0(正常)」と「検出型で発火0(削除候補)」を発火履歴だけで区別できないため、各ゲートの型を
  **手貼りラベルでなく構造から導出**する。判定順: `not-a-gate`（ハーネスのツール/ユーティリティ=分類対象外）→ `prevention`
  （reject-type レジストリ在籍）→ `# gatecrate-type:` マーカー（`advisory`/`detection`/`prevention` の人間上書き）→ `untyped`
  （ブロックするのに未分類=真の穴）。**3カテゴリ+untyped+not-a-gate**: 非ブロッキング層は `advisory`（発火ベースの ROI 剪定を
  適用しない・価値は「信号が読まれ行動に使われるか」で人間判断）。「ブロックするか」はモード(`--strict`)とCI配線(required か)に
  依存しスクリプト単体では導出できないため、advisory/detection は人間マーカーで宣言する（CI配線からの導出は後続改良）。意味的誤分類の
  検出は称さない（在籍が一次でマーカーより優先・是正は人間 escalation）。単一ソース化のため `probe-gate-liveness.sh` に
  `--list-reject-gates` を追加（REJECT_GATES 二重定義=drift 防止）。挙動テスト `tests/test-classify-gate-type.sh`（18性質・
  手動欠陥挿入で検出力確認）を CI(lint) に配線。kit 自身で実証＝**prevention11／not-a-gate10／untyped6**（untyped6 は
  measure-*/kit-drift/test-compiles/domain-model/gate-tests＝step2 でマーカー付与予定）。
- **判断材料の提示 `--explain`（decision record §3.2）**: 人間に分類を委ねる際、ただ「untyped」と丸投げせず**判断を安くする証拠を
  添える**（さもないと当て推量/rubber-stamp=沈黙の腐りが人間側に移るだけ）。`classify-gate-type.sh --explain <gate>` が派生可能な
  証拠（非0 exit 経路／reject-registry 在籍／`--strict` 有無／advisory 自己宣言／behavior-test／workflow 呼出）と**根拠つきの
  suggested type** を出力。派生不能な required-check/firing-history は `needs-gh` と明示（憶測しない）。**提案であって自動適用しない**
  （マーカー付与は人間の手作業）——自動エンフォースとの境界が沈黙の腐りを防ぐ。step2 のメタゲートは untyped 失敗時にこの出力を載せる。
  suggested type は**推論のはしご（Ladder of Inference: observe→select→assume→conclude）**で提示し、人間が各段を降りて検証できる。
  load-bearing な仮定が needs-gh 依存なら `[UNVERIFIED]` と段に明示し「check first」で名指す。推論の飛躍が無い場合（registry 在籍等）は
  observe→conclude にはしごを畳む（飛躍の無い段を捏造しない）。テストは 25性質に拡張（手動欠陥挿入で変異 G/H 検出力確認）。

### Documentation
- **プローブ責務と型分類の設計判断を decision record に正典化**（`docs/probe-scope-and-gate-classification-decision.md`）:
  P4 二階ループの「次の一段」を巡る検証つき議論を決着。(1) 生存証明プローブを correctness（正常入力→受理）に拡張する案を
  **却下**——correctness は挙動テスト層の責務で消費者環境も既に再現済み、誤爆は沈黙せず即顕在化するためプローブ守備範囲外。
  (2) ROI 剪定の予防型/検出型は**手貼りラベルでなく導出**し、メタゲートは「未分類」可視化のみ担う（意味的誤分類の検出は称さない）。
  背景原理「存在の強制は機械化できるが意味的正しさの強制はできず人間信頼に着地する」を明文化。ROADMAP P4 からリンク。

## [v0.10.1] - 2026-06-19

### Fixed
- **エスカレーション記録の CI 伝播が消費者の gitignore に依存していた穴を修正（再評価 #3）**: Stop hook が書く
  `.kiro/.gatecrate-mutation-escalated` は、消費者が `.kiro/` を gitignore していると `git add -A` で staged されず
  （ignored ディレクトリ配下のファイルは `.gitignore` 否定でも再包含できない）、コミットされず一次層 CI ゲートに
  届かない＝ローカル bypass が黙る経路があった。hook が記録を書いた直後に **`git add -f` で force-stage** するよう
  修正し、`.kiro/` 無視下でも記録が次コミットに乗り CI に伝播するようにした。Stop hook には従来テストが無かった
  ため `tests/test-spec-test-mutation-gate.sh` を新設（arm/block/escalate＋#3 の force-stage 回帰を固定・9件緑）し
  CI に配線。

## [v0.10.0] - 2026-06-19

### Added
- **gatecrate を gatecrate 自身で保護（ドッグフードの全域化）**: 出荷ゲートのうち kit に適用可能なのに
  自分の CI で回していなかったものを self-harness に配線。`hard-constraints.tsv` を新設（kit 自身の不変条件＝
  cc-sdd 帰属の維持／README の "battle-tested" 等の誇張表現禁止＝#71 honesty 修正の退行防止）し
  `check-hard-constraints` を実走。`probe-gate-liveness --audit`（生存証明カバレッジ）・
  `check-mutation-escalation`（committed escalation の混入防止）も self-harness に追加。さらに
  `.github/workflows/merge-integrity.yml` を配置し、kit 自身の PR マージで auto-merge レースを検知する。
  ＝kit が出荷する全ゲート（posix/secrets/file-line/title/doc-currency/rule-doc/probe(+audit)/gate-tests/
  hard-constraints/mutation-escalation/merge-integrity）を自分自身に適用する状態に。

### Added
- **「全 reject ゲートに挙動テスト」を機械強制するメタゲート＋欠落テストの補完**: 監査の結果、reject 型
  ゲートのうち `check-conventional-title` / `check-no-committed-secrets` / `check-third-party-notices` に
  挙動テストが無かった（file-line バグが長期間見逃された原因と同じ「testless ゲート」）。3本の挙動テストを
  追加し、さらに `core/scripts/check-gate-tests.sh`（メタゲート）を新設＝出荷 reject 型ゲートに
  `tests/test-<gate>.sh`（命名ゆれ `test-<gate-without-check>.sh` も可）が在ることを機械確認し、testless な
  ゲートの出荷を構造で止める。メタゲート自身もテスト付き・CI で dogfood。install standard-core と全
  `sync-manifests/<stack>.yaml` に配布、gatecrate-setup Phase 7 に配線手順を追記。

### Fixed
- **file-line ゲートが大半のファイルを黙って走査漏れしていた潜在バグを修正**: `check-file-line-limit.sh` が
  `SCAN_NAMES`（`*.sh *.md`）を未クォートで word-split していたため、パターンが cwd に対して **glob 展開**され、
  ルート直下の実ファイル名（`install.sh`/`CHANGELOG.md` 等）に化けていた。find はその実名だけを repo 全体で探し、
  **サブディレクトリ固有名のファイル（`core/scripts/*.sh`・`.claude/**.md` 等）を永久に未走査**＝300行ルールが
  ほぼ未強制で、しかも緑のまま通っていた（「ゲートが黙って仕事をしていない」死角）。`set -f`（noglob）で
  パターンを literal に保ち全域走査に修正。修正後、新たに露出した超過は既存の例外（probe 352 / SKILL 313）のみで
  実害なし。**このゲートには挙動テストが無かった**ため新設（`tests/test-check-file-line-limit.sh`＝サブディレクトリ
  違反の回帰を固定）。CI 未配線だった `test-check-mutation-escalation` も併せて配線。

### Added
- **生存証明の残り注入器を整備（#1 の honest gap を解消）**: NOTE「no injector yet」だった5つの reject 型
  ゲートに合成違反の注入器を追加し、`probe-gate-liveness.sh` で全 reject 型を生存証明できるようにした。
  `doc-currency`（EN/JA 片側だけ変更した2コミットを生成）/ `rule-doc`（RULE_DOC_CHANGED seam で規則変更・doc 未更新）/
  `merge-integrity`（最終 head を含まない2親マージを生成）/ `release-version`（VERSION_NAME を最新タグと一致させる）/
  `third-party`（バンドル資産在・必須文字列欠落）。kit の dogfood 既定 PROBE_GATES を全10ゲートに拡張、
  `--audit` の REJECT_GATES も全 injectable に更新（pending NOTE が消滅）。probe テスト 32件緑。probe は注入器
  集約のため file-line 例外に登録。

### Added
- **生存証明（二次ハーネス）の全域化（仕上げ #1・本丸）**: `probe-gate-liveness.sh` の注入種別が
  title/secrets/filesize/hard-constraints の4種しかなく、他の reject 型予防ゲートは生存証明の対象外
  ＝「正常時に発火しない＝壊れても分からない」死角に逆戻りしていた。注入種別に **posix**（非#!/bin/sh
  shebang）と **escalation**（mutation エスカレーション記録）を追加し、kit の dogfood 既定 PROBE_GATES にも
  両者を登録。さらに **`--audit` メタチェック**を追加＝採用済みの probe 可能 reject 型ゲートが PROBE_GATES に
  未登録なら fail（「ゲートを足して登録し忘れた」を構造で検出）。注入器が未整備の reject 型（doc-currency /
  rule-doc-currency / merge-integrity / release-version-name / third-party-notices）は NOTE で**可視化**し
  残ギャップを silent にしない。probe テストに property 8/9 追加（27件緑）。gatecrate-setup Phase 7 に audit を配線。

### Changed
- **機械強制を「催促」から「多層防御」に格上げ（仕上げ #2）**: spec-test の Stop hook は MAX_BLOCKS 到達で
  silent に force-pass していた（ローカルで粘れば痕跡なく通過できた）。到達時に可視記録
  `.kiro/.gatecrate-mutation-escalated`（理由＋survivor）を残すよう変更し、新ゲート
  `core/scripts/check-mutation-escalation.sh`（一次層・CI）がその記録を検出して人が解消するまで PR を fail
  させる。＝即時層（hook）＋CI 層の多層防御で「黙って抜ける」経路を封鎖。挙動を正確に語るよう hook の
  コメント／`templates/hooks/README.md`／`spec-driven-loop`（EN/JA）も「3回催促後にエスカレーション」に修正。
  install standard-core と全 `sync-manifests/<stack>.yaml` に新ゲートを配布。挙動テスト追加。

### Fixed
- **堅牢化のムラを「監査」でなく「メタゲート」で再発防止（仕上げ #3）**: `check-hard-constraints.sh` の
  予測可能な PID 後置 `/tmp` 一時ファイルを `mktemp`＋trap に、`check-kit-drift.sh` の予測可能フォールバックも
  `mktemp` のみ（不在なら advisory skip）に修正。さらに `check-posix-portability.sh` に **check 3**（出荷
  スクリプトに予測可能 PID 後置 `/tmp` パスがあれば fail）を追加し、同種ミスを一度の掃除でなく構造で再発不能に
  した（コメント言及は除外・grep の単一/複数ファイル両形式に対応）。テスト property 6/7 を追加。

## [v0.9.0] - 2026-06-18

### Added
- **install.sh / gatecrate-setup が抽出済み資産を実配布するよう配線**: 抽出しただけで配られていなかった
  資産を install で届ける。standard-core 層に `pr-preflight.sh` / `check-third-party-notices.sh` /
  `check-release-version-name.sh` / `setup-branch-protection.sh` / `measure-complexity.sh` /
  `measure-coupling.sh`（＋ `scripts/quality/complexity-ruleset.xml`）を追加。新フラグ **`--with-skills`** で
  `.claude/skills/`（`alloy-spec-model-generator` / `gatecrate-evaluate`）と TAKT 一式 `.takt/` を配布
  （ROADMAP「install がスキルを配布する option」を実装）。`gatecrate-setup` SKILL に workflow ラッパー配線
  （Phase 5）と Alloy 雛形・`--with-skills`・Fitness 計測の採用手順（Phase 6.5）を追記。install↔sync 整合のため
  全 `sync-manifests/<stack>.yaml` の core_scripts に新スクリプトを追記。

### Added
- **形式手法（Alloy）＋ TAKT オーケストレーションを localmd から上流抽出**: kit は Alloy ゲート
  （`check-domain-model.sh`）は持つが、入口（生成）と雛形が無かった。`.als` 雛形 `templates/spec/models/example.als.example`・
  `core/workflows/domain-model-check.yml`（advisory Alloy CI）・`docs/domain-model-ci-decision.md`・Alloy 生成スキル
  `.claude/skills/alloy-spec-model-generator/`（汎用化）・TAKT 一式 `templates/takt/`（config／workflows
  `harness-evaluate-cycle`・`harness-liveness-converge`・新規 `harness-rule-reflect`／personas `gatecrate-evaluate`・
  `harness-auditor`・新規 `spec-author`）を追加。これで二階ループ／規則 reflect の実行資産が揃った。
- **集約配線**: `harness-rule-reflect.yaml` が参照する `spec-author` persona を追加（宙ぶらりん参照を解消）。
  CI self-harness の checkout を `fetch-depth: 0` に修正（rule-doc / doc-currency ゲートが `git log BASE..HEAD` で
  コミット本文＝`Docs-Impact:` トレーラを読むため。浅 checkout で ship-scripts レーンが誤発火していた・PR #80/#82 で観測）。
- **Fitness 計測を localmd から上流抽出（複雑度・結合度・ROI グループ）**: kit は file-line しか測れなかった。
  `core/scripts/measure-complexity.sh`（PMD ベース・`COMPLEXITY_LANG`/`COMPLEXITY_PATHS` 設定可・
  `core/scripts/quality/complexity-ruleset.xml` 同梱）と `core/scripts/measure-coupling.sh`（Ca/Ce/不安定度・
  SDP・git co-change。import 解析は JVM 依存のため `COUPLING_PKG_PREFIX` 設定可、未設定時は co-change のみで
  graceful degrade）を追加（いずれも advisory）。`templates/gate-groups.tsv.example`（collect-gate-history の
  論理ゲート relabel テンプレ）と `docs/code-quality-metrics.md`（S-01〜D-03 閾値）も同梱。
- **bootstrap/preflight/リリース衛生ゲート＋workflow ラッパーを localmd から上流抽出**: `core/scripts/` に
  `setup-branch-protection.sh`（必須チェックは `REQUIRED_CHECKS` 設定可）・`pr-preflight.sh`（導入済みゲートを
  自動検出して実行）・`check-third-party-notices.sh`・`check-release-version-name.sh`（＋ `tests/` に挙動テスト）、
  `core/workflows/` に `merge-integrity.yml` / `harness-drift-check.yml`（既存スクリプトの CI ラッパー）。Play/Android
  固有の `setup-github-actions-repo.sh` / `release-preflight.sh` / `check-release-notes.sh` は
  `adapters/android-jvm/scripts/` に汎用化配置。規則の起票形式 `docs/proposed-rule-format.md`（DR-ID・
  observed_behavior・evidence・als_conflict・intent/defect 裁可）も同梱。

## [v0.8.1] - 2026-06-18

### Added
- **仕様駆動ループの scaffold を出荷（reflect/doc レーンを turnkey に）**: kit はゲートエンジン
  （`check-rule-doc-currency.sh`）と形式定義（`spec-rules.md`）を出荷していたが、消費者が書き始める
  雛形が無く、実消費者（todo_app）では `docs/spec`・`rule-doc-lanes.tsv`・`stryker.config.json` を全て
  手書きする必要があった。雛形を追加: `templates/spec/`（規則文書の索引＋`area.md` 骨子）・
  `rule-doc-lanes.tsv.example`（鮮度ゲートのレーン定義テンプレ）・
  `adapters/typescript/stryker.config.json.example`（`break` 閾値＋テスト支援ファイル除外を内蔵）。
  `gatecrate-setup` に Phase 6.5（spec 文書と rule-doc-currency の scaffold 手順）を追加し、
  `spec-rules`（EN/JA）と TS アダプタ README から導線を張った。

### Added
- **`install.sh --with-cc-sdd` が Stop hook（機械層）まで入れるように**: 従来は cc-sdd 本体＋steering
  （判断層）止まりで、`validate-impl` 後の survivor-strict mutation を機械強制する Stop hook は手動
  だった（実消費者 todo_app で「機械層だけ抜けてループが閉じない」事故が発生）。`--with-cc-sdd` が
  `templates/hooks/spec-test-mutation-gate.sh` を `.claude/hooks/` に配置し、`.claude/settings.json` を
  生成（既存時は手動マージ案内）、arm マーカーを `.gitignore` に追記する。

### Changed
- **「ゲートは存在ではなく実走で検証」を gatecrate-setup と TS アダプタに明文化**: setup が検証するのは
  「ゲートが在るか」でなく「ゲートが実際に走り期待出力が出るか」。版非互換（例: Vitest 4 ×
  `@stryker-mutator` 8.x はクラッシュ＝mutation が一度も走らない）を setup 時に捕捉するため、
  `SKILL.md` Phase 7 に mutation の実走確認を必須化、`adapters/typescript/README.md` に版整合
  （Vitest 3/4 → `@stryker-mutator` ≥9）とテスト支援ファイルの mutate 除外を明記。

### Added
- **`install.sh --with-cc-sdd` が cc-sdd 本体を npx で導入するように**: これまで steering を置くだけで
  cc-sdd 本体は別途手動導入が必要だった。指定時に `npx --yes cc-sdd@latest --claude-skills --lang ja`
  を TARGET で実行して cc-sdd を scaffold し、その上に gatecrate steering を `.kiro/steering/` へ重ねる
  （cc-sdd の steering は `{{KIRO_DIR}}/steering/` が正規の拡張点で spec 系コマンドが自動参照することを確認）。
  agent/言語は env で上書き可（`CC_SDD_AGENT` 既定 `--claude-skills` / `CC_SDD_LANG` 既定 `ja` /
  `CC_SDD_FLAGS`）。`npx` 不在時は警告して cc-sdd 本体はスキップ・steering は配置（install は止めない）。
  検証: UTF-8 locale で実 scaffold まで end-to-end 緑、npx 不在パスも graceful。usage / spec-driven-loop の
  EN/JA を npx 導入手順に更新。install.sh は cc-sdd 導入を取り込み 300 行超のため file-line 例外に登録。

### Fixed
- **sync-propose.yml の固有設定 除外フィルタが実ファイル名にマッチしていなかったのを修正**:
  二重防御の除外パターンが消費者設定を `harness-config.yaml` の名で参照していたが、実体は
  `harness.config.sh`。万一その設定が同期差分に紛れても弾けなかった（主防御のホワイトリストは健在）。
  `case` パターンと関連コメント・PR 本文・チェックリストの計5箇所を `harness.config.sh` に是正。
  `profile.yaml` の追加ガードは無害なため維持。
- **install.sh が「誰も読まないファイル」を生成していたのを修正（インストール後設定の混乱の主因）**:
  install は `harness-config.yaml`（YAML）を生成していたが、全スクリプトが source するのは
  `harness.config.sh`（シェル）で、生成物は誰も読まず・指示が編集を促すファイルは未生成だった。
  install を `templates/harness.config.sh.example` → `harness.config.sh` を生成するよう修正。
  「次のステップ」の変数名も実体に合わせて `FILE_LINE_LIMIT` / `FILE_LINE_NAMES` に修正
  （旧案内の `FITNESS_MAX_LINES` は core 版では別名）。死にファイルの元
  `templates/harness-config.yaml.example` を削除（structure / android-jvm README / CONTRIBUTING の参照も是正）。

### Added
- **install.sh `--with-cc-sdd` フラグ + cc-sdd 連携の導線**: 指定時に custom steering
  `templates/kiro-steering/gatecrate-spec-test-loop.md` を消費者の `.kiro/steering/` へ配置。
  「次のステップ」と usage.md/.ja.md から `docs/spec-driven-loop.md` への導線を追加（連携手順は元々
  存在したが install から辿れなかった）。`templates/harness.config.sh.example` を現行スクリプトに合わせ刷新
  （`FILE_LINE_*` / `SPEC_LOOP_MODE` / `PROBE_GATES` 等を収録）。

### Added
- **使い方ドキュメント充実: `docs/spec-driven-loop.md` / `.ja.md`（仕様駆動学習ループの包括ガイド）**: 今セッションで
  追加した一連の機能（`harness-spec-test-loop`・モード選択 `SPEC_LOOP_MODE`・cc-sdd 統合の steering・mutation の Stop hook）が
  usage 系に未掲載だったのを解消。新設の包括ガイドに、5ステップ（explore→propose-model→specify→reflect→measure）・
  クイックスタート（変更クラスタに同 PR で並行）・モード（autonomous/expert-gated の設定と使い分け）・cc-sdd 併用
  （steering 設置・各フェーズの動作・Stop hook の install/settings/marker）・autonomous の実例（cart-pricing で形成された
  ドメイン知識＋mutation が緑の穴を捕捉）・設定リファレンス・正直な限界 を収録。`usage.md` / `.ja.md` に導線と新設定変数
  （`SPEC_LOOP_MODE` / `SPEC_TEST_MUTATION_CMD`）を追記。


### Added
- **cc-sdd 統合の機械的裏打ち: validate-impl 後の survivor-strict mutation を Stop hook で強制**: steering は
  prompt 注入＝判断層なので、`/kiro:validate-impl` の「緑だけでは不可・mutation で十分性を裏取り」を**機械保証**する
  Claude Code Stop hook を追加。`templates/hooks/spec-test-mutation-gate.sh` は marker（steering が validate-impl 冒頭で
  `touch .kiro/.gatecrate-mutation-pending`）が在るときだけ survivor-strict mutation を実行し、**生存があれば exit 2 で
  エージェントの停止をブロック**して survivor 一覧をフィードバックする＝生存を消すまで validate-impl を終えられない。
  無限ループ防止に session_id 別カウンタで連続ブロックを上限（既定3）→ force-through。設定は `SPEC_TEST_MUTATION_CMD` /
  `SPEC_TEST_MUTATION_MAX_BLOCKS`。`settings-stop-hook.json`（settings.json への Stop 登録）と install 手順 README、steering の
  arm 手順を同梱。hook ロジックを直接検証（marker無し=no-op / 生存=ブロック exit2・counter++ / 上限=force-through exit0 /
  クリーン=即通過）。＝prompt 層（steering）を機械層（hook の mutation ゲート）で裏打ちする構成が完成。


### Added
- **cc-sdd 統合（非侵襲・cc-sdd のソース無改変）**: gatecrate の spec-test-loop を cc-sdd（Kiro 流 Spec-Driven
  Development・MIT・gotalab/cc-sdd）の各フェーズに参加させる。**フォークせず**、cc-sdd 自身の拡張点
  （custom steering・各コマンドが `.kiro/steering/` を全読みする）を使う: gatecrate は自前の custom steering
  テンプレート `templates/kiro-steering/gatecrate-spec-test-loop.md` を1枚提供し、消費者がそれを `.kiro/steering/` に
  置くと、cc-sdd の11コマンドを一切改変せずループが流れに入る。steering / validate-gap→domain-modeler 逆行（欠落概念）、
  spec-design→entity/value/policy 供給、spec-impl→reflect(ROI技法)+measure(mutation)、validate-impl→mutation clean+
  仕様↔テスト traceability+drift 照合。モードは SPEC_LOOP_MODE（cc-sdd 仕様あり=expert-gated／なし=autonomous で
  `.kiro/specs` を bootstrap）。**ライセンス**: cc-sdd は MIT、gatecrate は Apache-2.0 で互換。cc-sdd のソースは
  bundle/再配布せず（gatecrate の no-bundle 方針どおり）、THIRD_PARTY_NOTICES.md に帰属を追記。**正直な限界**:
  steering は prompt 注入＝判断層（ハードゲートでない）。機械保証は gatecrate のゲート（survivor-strict mutation 等）、
  概念確定は cc-sdd のフェーズ承認（人間）が担う。


### Added
- **`harness-spec-test-loop` にモード選択（autonomous / expert-gated）＋コーディング並行の枠組み**: モデル仮説発見の
  「誰が規則化を決めるか」を `SPEC_LOOP_MODE` で選べるようにした。**`expert-gated`（既定・ビジネス要件駆動）**は従来どおり
  仮説を提示し DRAFT＋テスト skip で人間の確定を待つ。**`autonomous`（バイブコーディング＝別個の人間の意図が無い）**では
  **エージェントが「機能としてどうあるべきか（functional correctness / good design）」から判断して規則を canon 化し、
  ACTIVE なテストを書く**——ただし**ビジネスポリシー型の判断**（tier/失効/猶予期間など、機能推論では default しか出せない
  もの）は `DECIDED AUTONOMOUSLY (policy) — chose X because Y; an owner may prefer Z` と**必ず明示**し、金銭/契約/UX を
  驚かせうる判断はその項目だけ expert-gated に escalate する。どちらのモードでも欠落概念（H1 失効/H4 多 tier 等）は
  surface される＝オーナーの学びは保たれる。あわせて本ループを**変更したクラスタに対しコーディングと同 PR で回す**
  （inner-loop・mutation は変更クラスタにスコープして安価に）枠組みを workflow header に明文化。`domain-modeler` persona に
  全モード規則を、各 step（propose-model/specify/reflect/measure）にモード分岐を配線。


### Added
- **`harness-spec-test-loop` ワークフロー + `domain-modeler` persona（AIエージェントの仕様駆動学習ループ）**:
  「エージェントが自らドメインを探索し→仕様を発見し→ドキュメント化し→仕様に対してテストする（技法は ROI で選び・
  有効性は mutation/ROI で裁く）」を**1ループに合成**。既存の3ワークフロー（coverage-expand=探索/技法選定・
  rule-reflect=仕様化/反映・coverage-deepen=mutation 収束）を explore→propose-model→specify→reflect→measure の
  1シーケンス+2 command ゲートループに束ねた。**新規 `domain-modeler` persona**: コードが構造的に体現する制約
  （データ形・不変条件・多重度・操作の事前事後・状態/時間）から、**ドメイン概念の"モデル仮説"を提案**する——
  「完全な業務仕様は人間が要る」という限界を認めつつ、「このコードはこんな概念を示唆する→専門家、これは実在の規則か?」
  と問う**ドメインエキスパートの学びの起点**を生む（FACT と HYPOTHESIS を分離・canonize しない・散在制約=欠落概念の
  示唆を最優先）。技法選定は per-規則の ROI 判断として記録（example/PBT/stateful-PBT+model/exploratory）、有効性は
  survivor-strict mutation で収束まで反復。正直な限界を明記: 発見できるのはコードが含意する仕様のみ（実装漏れの仕様は不可視）。


### Fixed
- **`install.sh`: 汎用ゲートを `standard-core` ティアに分離（全非 minimal プロファイルへ配布）**: doc-currency /
  check-rule-doc-currency / check-kit-drift / check-merge-integrity / check-hard-constraints / collect-gate-history は
  スタック非依存の汎用ゲートなのに、従来は `standard`/`full`（＝Android-JVM）ブロックに束ねられ、**python/go/rust/kotlin/
  haskell/lean4 の消費者には install で届かなかった**。一方 sync-manifests は既に全スタックの core_scripts に列挙しており
  **install↔sync が不整合**だった。本ティアを `[ "$PROFILE" != "minimal" ]` の独立ブロックに切り出し、全非 minimal
  プロファイルへ配布して整合させた。あわせて旧 `install:163` の `$CORE_SCRIPTS/check-test-smells.sh`（実体は
  adapters/android-jvm 側＝参照バグ・存在しない core を install しようとしていた）を除去。version-*/start-work は
  standard/full、check-domain-model は full のみ（full の差別化要素）を維持。検証: minimal=ゲート無し / python・rust=
  汎用ゲート全取得 / standard=全取得+version / domain-model は full のみ。


### Added
- **`probe-gate-liveness.sh` に `hard-constraints` 注入種別 + 有効性確認ドキュメント**（有効性検証）:
  probe の注入種別は `title|secrets|filesize` のみで、**設定駆動ゲート（config-driven）が生存証明できない**
  天井があった。`hard-constraints` 種別を追加——消費者の `hard-constraints.tsv` の最初の forbid 規則から違反を
  合成注入し、健全ゲートは ALIVE・壊れたゲートは DEAD・forbid 規則が無ければ **setup error（決して偽 ALIVE に
  しない）**。これで設定駆動の予防ゲートも survival proof の対象になる（L1 網羅の拡張）。回帰テスト 性質7 追加
  （ALIVE/DEAD/no-forbid-rule setup error・22ケース緑）。あわせて有効性確認の正典 `docs/effectiveness-validation.md`
  /`.ja.md` を新設——「機械的正しさ ≠ 価値」を明確化し、証拠の階層 L0〜L5・反事実の罠・localmd 実測の第一次証拠
  （docs-currency 2/12 発火・pr-title 1/13・mutation 927秒/発火0 等）・ゲート別判定・欠落と次アクションを記録。
- **`check-hard-constraints.sh` に条件付き `guard` 列（third-party notices を統合）**（A群・A-4）: localmd の
  `check-third-party-notices.sh` は実質「vendored 依存が在るときだけ帰属表示を require ＋ CDN 参照を forbid」で、
  **near-duplicate な新ゲートを作らず** hard-constraints に **6列目 `guard_pathspec`（条件）**を足して表現可能にした
  （DRY・「同形ガードを2本持たない」方針）。guard が在り1件もマッチしなければその制約はスキップ＝「依存が在るときだけ
  必須にする」が書ける。third-party-notices はゲート本体の設定例（スクリプト header に記載）として実現。回帰テスト
  性質8（guard 不在→スキップ / guard 在→require 適用→帰属欠落で FAIL / 帰属在→ok）を追加（17ケース・手動変異で検出力確認）。
  既存5列ルールは guard 空＝常時適用で後方互換。
- **`check-hard-constraints.sh` を core スクリプト化（コンテンツ不変条件ゲート）**（A群）: プロダクトの
  「絶対に破ってはいけない設計判断」をソースレベルで機械強制し PR を fail-fast。これらは「正しさ」（テストが見る）
  ではなく「**意図の境界**」——人/AI が善意で破りうる（オフライン reader に INTERNET 権限を足す・特定 WebView で
  JS を有効化する・新ソースに LICENSE ヘッダ忘れ等）。意図はコードに自明に書かれないので機械固定が要る。
  **設定駆動**: 制約は消費者ごとに違うので `hard-constraints.tsv` に外出し（`<kind>\t<file_pathspec>\t<regex>\t<message>\t[<mode>]`・
  kind=forbid/require・pathspec は git ls-files・mode=raw/nows）。**nows モード**で空白除去後に照合＝複数行/整形ゆれに
  強い（localmd の `setJavaScriptEnabled(\n true\n)` 検出を一般化）。require のリテラル必須ファイル欠落も違反、glob 0件は
  vacuous pass。無設定なら advisory skip。回帰テスト `tests/test-check-hard-constraints.sh`（14ケース・forbid/require/nows/
  必須ファイル欠落/glob/no-config skip・手動変異2種で検出力確認）を lint に配線、install standard/full + 全 sync-manifest に追加。
- **`check-merge-integrity.sh` を core スクリプト化（auto-merge レース検知）**（A群）: 全チェック緑+
  未解決スレッドのみの PR に対応コミットを push し直後にスレッドを解決すると、新コミットの CI 完了を待たず
  「旧 head」でマージが発火し最後のコミットが既定ブランチから漏れる（ブランチ保護では防げない・レビュー往復の
  多い AI 駆動開発で現実に踏む）。本ガードは「PR の最終 head がマージコミットの祖先か」を機械検証し漏れを赤で
  知らせる（予防不可なので検出層）。**責務分離**: スクリプトは検出のみ（純 git・決定論・テスト可能）、issue 起票・
  通知は消費者ワークフロー側（gh + 文面ポリシーは消費者固有）に残す。squash/rebase（親<2）は ancestor 検証が構造上
  不能なので SKIP（誤検知しない）。引数/解決不能は exit 2（黙って pass しない）。回帰テスト
  `tests/test-check-merge-integrity.sh`（11ケース・真マージ ok / 旧 head マージ FAIL / squash SKIP / 引数・解決不能 exit2・
  手動変異2種で検出力確認）を lint に配線、install standard/full + 全 sync-manifest に追加。
- **`check-kit-drift.sh` を core スクリプト化（消費スクリプトのドリフト検査・消費者側）**（A群・
  同期機構の欠落補完）: gatecrate は「同期を提案する producer 側（sync-propose）」だけ出荷し、消費者が
  「consumed_scripts が pin 版のキット原本と byte 一致か」を検査する**消費者側の片割れを出荷していなかった**
  ＝消費者が各自で自作する羽目になっていた（localmd が実装）。それを core 化。`sync-manifest.yaml` の
  `consumed_scripts` 各ファイルを pin tag のキット原本と diff し、改変＝DRIFT・whitelist 外＝UNRESOLVED を
  区別して報告。**既定 advisory**（drift を検出しても落とさない・`--strict` で gating）。**ネットワーク/キット
  取得不能は `--strict` でも非致命**（オフラインが赤ゲートになってはいけない・SKIP exit 0）。`KIT_DIR` で
  既存 checkout 差し替え（clone 非依存のテスト seam）、`KIT_REPO` 既定 `Yos-K/gatecrate`（旧 `HARNESS_KIT_REPO`・
  `harness_kit_version` pin キーも honored）。回帰テスト `tests/test-check-kit-drift.sh`（16ケース・一致/drift/
  --strict/ローカル不在/UNRESOLVED/manifest不在SKIP/オフラインSKIP・手動変異2種で検出力確認）を lint に配線、
  install standard/full + 全 sync-manifest に追加。
- **`check-rule-doc-currency.sh` を core スクリプト化（ルール→ドキュメント鮮度ゲート）**（B-中核・
  ドメイン学習ループの「学んだ知識が腐らない」保証）: 規則担持ファイル（ドメイン/ハーネス/ポリシーの
  コード・設定）を変えたのに、それを人とエージェントに教える**文書を更新しないと CI で落ちる**。次に
  そのコードに触る人/AI が古い文書を信じて誤るのを防ぐ。**設定駆動**——何が「規則担持」で対応文書はどれかは
  消費者ごとに違うので、レーンを `rule-doc-lanes.tsv`（`<lane>\t<trigger_regex>\t<doc_regex>\t[<exempt_trailer>]`）に
  外出しし、スクリプトは汎用エンジンに保つ。普遍トレーラ `Docs-Impact:` で発火した全レーンを免除（純リファクタ
  宣言）、レーン別の旧トレーラも col4 で honored。`RULE_DOC_CHANGED`/`RULE_DOC_COMMITS` を git 非依存のテスト
  seam に。既存の `check-doc-currency.sh`（EN/JA 対訳鮮度）とは別物（コードの規則→文書の鮮度）。回帰テスト
  `tests/test-check-rule-doc-currency.sh`（13ケース・trigger/doc/普遍&レーン別トレーラ/複数レーン/no-config skip・
  手動変異2種で検出力確認）を lint に配線、install standard/full + 全 sync-manifest に追加。**gatecrate 自身で
  ドッグフード**（`rule-doc-lanes.tsv`: 出荷スクリプト変更→CHANGELOG 必須）を self-harness に配線。
- **`check-domain-model.sh` を core スクリプト化（Alloy ドメインモデル検査の CI ゲート）**（B-中核・
  ドメイン学習ループの「実行可能な出口」）: gatecrate は上流（`alloy-spec-model-generator` スキル・
  `harness-rule-reflect` が「ドメイン学習 → `.als` assert」を生成）を持つのに、それを **CI で検査する
  ゲート本体を出荷していなかった**。＝エージェントが書いた仕様アサートが CI で効かず、「学ぶ→書く→CI
  フィードバック→直す」ループが検査の手前で切れていた。これを閉じるゲートを core 化。`docs/domain/models/*.als`
  （`DOMAIN_MODEL_PATHS` で上書き可）を Alloy で `exec`、`check ... expect N` の食い違い＝ルール退行で非0。
  **既定 advisory**（java/Alloy jar 不在は skip・偽陽性ブロックしない／`DOMAIN_MODEL_STRICT=1` で hard 化）。
  Alloy jar は pin 版を sha256 検証してから実行（改竄 jar 実行拒否）。`DOMAIN_MODEL_JAVA` をテスト/特定 JDK
  指定の seam に。回帰テスト `tests/test-check-domain-model.sh`（14ケース・探索/上書き/no-models/引数 override/
  advisory skip/STRICT fail・手動変異2種で検出力確認）を lint に配線、install **full** プロファイルと全 sync-manifest に追加。
  実 Alloy で反例あり→exit 1／保証成立→exit 0 を実測（java 21）。
- **`collect-gate-history.sh` に論理ゲート・グルーピング（`--group-map <file>`）**（Issue #56・
  localmd-reader での二階ループ実走から）: 既定では `gate` 列が生の CIステップ名なので、本物の品質ゲート
  （Run mutation tests…）とセットアップ手順（Checkout / Set up Java…）が同じ表に混在し、ROI 判断の
  シグナルが薄まる。マップ（TSV `<step_pattern>\t<logical_gate>`・3列目以降は無視・グロブ `*` 可・
  `#` コメントと空行は無視・FIRST match wins・CRLF 許容）で step名を `mutation` / `gradle-build` /
  `docs-currency` / `pr-title` 等の**論理ゲートに集計前 relabel** する。設計判断: グルーピングは
  **aggregate 層（純 POSIX・決定論・テスト可能）**に置き、レコード契約（`<gate>\t<conclusion>\t<seconds>` の3列）を
  変えない——ゆえにマッチは step名のみ（workflow/job 不要、公開契約を壊さない）。**未マップ step は生の行のまま保持**
  （隠さない＝消費者が小さなマップから漸進的に育てられる・AC「preserved as raw rows」）。既定挙動（フラグ無し）は不変。
  読めないマップは非0で明示失敗（黙って無視しない）。回帰テスト 性質6/6b/6c を追加（グルーピング・後方互換・
  マップ不在の明示失敗。手動変異2種で検出力確認）。グロブ→ERE 変換は `*` 以外の正規表現メタ文字を全エスケープし
  マップ経由の regex 注入を防止。`gatecrate-evaluate` スキル Phase 1 に使用例を追記。

### Fixed
- **`collect-gate-history.sh` の既定モードが fetch 失敗を隠す問題**（localmd 導入時の自動レビューで発見＝双方向還元）:
  `fetch | aggregate` のパイプ status は最後の `aggregate`（exit 0）になるため、gh 未認証等で fetch が失敗しても
  空の TSV ヘッダだけ出して「成功」に見え、ROI 評価が「履歴ゼロ」と「未確認」を取り違えうる。→ fetch を一時ファイルに
  捕捉して**status を伝播**（失敗時 非0・"UNCONFIRMED" を明示）。加えて fetch 内の `gh repo view`/`gh run list` を
  **明示的に return**するよう修正（`if fetch` 内では `set -e` が無効で、`var=$(gh …)` 失敗が伝播しなかった）。
  回帰テスト 性質4（偽の gh で fetch を失敗させ、非0伝播・空ヘッダ非出力を検証）を追加。

### Added
- **POSIX 移植性ゲート + シェル/プラットフォーム対応の明文化**: 出荷スクリプトを POSIX `sh` に保ち、
  **bash / zsh / fish（実行は shebang で sh）と Windows Git Bash/WSL** で同じく動くことを機械保証する。
  `core/scripts/check-posix-portability.sh`（非 `#!/bin/sh` shebang と shellcheck SC3xxx=bashism を検出・
  `POSIX_CHECK_PATHS` でスコープ可・shellcheck 不在時は shebang 検査のみ）+ 回帰テスト
  `tests/test-check-posix-portability.sh`（6ケース）を lint に配線、install minimal + 全 sync-manifest に追加。
  既存の `sh -n`（runner では dash＝POSIX 構文検査）と合わせ、**構文＋意味的 bashism＋shebang** を3層で強制。
  実測: 全57スクリプトが `#!/bin/sh`・真の bashism（SC3xxx）ゼロ・`dash -n` 通過。README 両言語に
  「シェル・プラットフォーム対応」表を追加（PowerShell/cmd は POSIX 層 Git Bash/WSL 経由・native 不可を明記）。
  **レビュー指摘を反映**: shebang 検査を**完全一致 `#!/bin/sh` のみ許可**に厳格化（`#!/bin/sh -e` 等の引数付き
  shebang や CRLF 終端は挙動がプラットフォーム間で変わるため reject・回帰テスト 性質5 追加）。
- **`check-test-compiles.sh` を core スクリプト化**（rule-reflect の scaffold-compiles ゲートの follow-up）:
  inline のスタック検出シェルを出荷物の1コマンドに。スタック自動検出（Cargo.toml→`cargo test --no-run`／
  go.mod→`go test -run=__nomatch__`／tsconfig.json→`tsc --noEmit`／pyproject→`compileall`）または
  `harness.config.sh` の `TEST_COMPILE_CMD` override で build-no-run を実行し、非コンパイルなら非0で落とす。
  `--print` で検出のみ（テスト用）。回帰テスト `tests/test-check-test-compiles.sh`（13ケース・検出/override/skip）を
  lint に配線、install と全 sync-manifest に追加。`harness-rule-reflect` の command ゲートを
  `sh scripts/check-test-compiles.sh` に差し替え。デモ消費者で壊れた scaffold に対し exit 101 を実測確認。
  **レビュー指摘2件を反映**: (1・P1) install を **minimal core** に移動——`--profile auto`/単一スタック
  プロファイル（rust/go/python/ts）は standard ブロックを通らず、まさに必要な消費者にゲートが配布されない穴を解消。
  (2) python は `git ls-files` の生出力を `sh -c` に展開していたため空白/メタ文字を含むパスで分割・注入しうる→
  **ディレクトリ単位 `compileall -x <除外regex> .`** に変更（ファイル名をシェルに再パースしない）。
- **点A 統合デモ実証 + scaffold コンパイル必須化**（ROADMAP P4・拡充の自律成長）: 仮 rust 消費者に2機能目
  （`Percent` 入力空間不変条件）を実装し、Broaden→rule-reflect をもう一周。**ルールが累積**（`docs/spec/` に tabset.md +
  percent.md）し、**システムがリスク形状ごとに技法を正しく差別化**——TabSet（順序/状態）は**ステートフルPBT+Alloy**、
  Percent（入力空間）は**Plain PBT のみ・モデルは model-code gap を増やすだけと却下**。pending テストは `#[ignore]` 付き。
  「実装が進むとルール+テスト+モデルが一緒に育つ」を多クラスタで実証。**デモが実バグを発見し還元**: `#[ignore]` は
  実行を skip するがコンパイルはされるため、scaffold がコンパイルエラー（proptest の format 文字列 `{n}` 引数欠落）だと
  ビルドが赤になる＝skip だけでは不十分。→ **scaffold は「コンパイルも通る」ことを必須化**（spec-author persona・
  rule-reflect・spec-rules に明記、`todo!()` 等の最小コンパイル可能本体を推奨）。**さらにレビュー指摘で
  プロンプトだけでは enforce されない**（TAKT が非コンパイルでも COMPLETE できる）→ `reflect` ステップに
  **`scaffold-compiles` command ゲート**を追加（スタック検出で build-no-run: `cargo test --no-run`/
  `go test -run=^$`/`tsc --noEmit`/`compileall`）。デモの壊れた scaffold で exit 101 を確認＝非コンパイル時は
  ゲートが落ちて TAKT が再実行・修正する。横断的な `check-test-compiles.sh` は follow-up。
- **仕様ルールの文書化と「1ルール=2反映」**（ROADMAP P4・拡充）: テストとモデル検査が**同じルール**を検証するなら、
  ルールを単一ソース化すれば両方が一緒に育つ。方法論 `docs/spec-rules.md`/`.ja.md`（ミニ言語 invariant/policy・ID・
  トレーサビリティ rule→test→assert・意図vs欠陥ゲート）。実装 `harness-rule-reflect`（TAKT specify→reflect）+
  `spec-author` persona: リスク/不変条件を `docs/spec/<area>.md` にルール（ID付き）で書き、実装テスト+（順序/状態なら）
  Alloy assert に反映。提案/scaffold・behaviour 由来は DRAFT で人間の意図vs欠陥分類待ち・自動 canonize しない。
  **仮 rust 消費者で実走実証（Broaden と統合）**: TabSet の active-tab 不変条件を R-1 として確定し、ステートフルPBT
  （`tests/tabset_pbt.rs`・**コンパイル&pass 確認**）と Alloy assert（`spec/tabset.als`・3 preservation check）に反映、
  R-1→test→assert を記録、隣接4挙動は DRAFT で canonize せず（2反復・~10m45s）。1クラスタからルール+テスト+モデルが
  一緒に育つことを実証。README 両言語の Documentation 表に spec-rules を追加。**レビュー指摘を反映**: pending テスト
  scaffold を `tests/` 等の自動検出パスに置くと `cargo test`/`pytest`/`go test ./...`/`vitest` が拾い、人間の意図/欠陥
  分類前に PR を赤化（or 緑スタブが現挙動を仕様固定）しうる→pending テストは言語の skip（`#[ignore]`/`@pytest.mark.skip`/
  `t.Skip`/`it.skip`）で discovery から外すことを persona・ワークフロー・spec-rules に必須化。
- **拡充ループ Broaden サブモード**（ROADMAP P4・拡充の判断側）: `harness-coverage-expand`
  （TAKT scan→assess→propose シーケンス）+ `coverage-scout` persona。変更クラスタのリスク形状を
  test-selection-roi の Q1–Q4 手順（persona に自己完結＝doc 不在の消費者でも可）で判定し、リスク形状はあるが
  検証が無いクラスタに**新技法を提案**（PBT/ステートフルPBT/mutation/モデル検査）。提案のみ・自動追加しない・
  behaviour 由来の提案は**人間の意図vs欠陥分類ゲート**へ回す（バグを仕様に正典化しない）。**仮 rust 消費者で実走実証**:
  TabSet 状態機械（順序/状態・trivial テストのみ）を EXPAND-CANDIDATE と判定し**ステートフルPBT を提案**、無ロジックの
  mod 宣言は「pure noise」と明示スキップ、TLA+ は過剰と正しく却下（3反復・~3m45s・自動追加なし）。これで拡充は
  Deepen（機械的）+ Broaden（判断）の両輪が揃った。
- **拡充ループ（外側ループの加える半分）・Deepen サブモード**（ROADMAP P4）: これまでの外側ループが**剪定偏重**だった
  非対称性を是正。設計 `docs/design/expansion-loop.md`（Deepen=mutation survivor 駆動の converge / Broaden=新技法提案の
  判断シーケンス）。**Deepen を実装**: `harness-coverage-deepen`（TAKT converge）+ `coverage-deepener` persona——
  survivor を殺すテストを mutation ゲートが clean になるまで足す（除外・floor 下げで誤魔化さない）。**仮 rust 消費者
  （cargo-mutants）で実走実証**: 弱いテストの4 survivor を 8/8 caught・exit 0 に収束（2反復・~3m45s・除外ゼロ）。
  剪定が機械的シグナルから刈るように拡充は機械的シグナルから成長する鏡。Broaden は設計済み・未実装。
  `development-workflow`(EN/JA) を「外側ループ＝拡充⇄剪定」に更新。**レビュー指摘2件を反映**: (1) Deepen は
  **survivor-strict ゲート**（survivor が残る限り非0で終わる）が前提。cargo-mutants は native に strict だが
  floor 型（mutmut/PITest/go/ts）は `score >= floor` で survivor 残存でも exit 0＝Deepen が空振りしうる→前提・persona・
  設計に「floor 型は deepen pass を floor=100 で strict 実行」を明記、横断的な require-zero-survivors を follow-up 化。
  (2) android-jvm は `run-mutation-tests.sh`（`run-mutation.sh` でない）＝コマンド名差異を前提に明記。
- **外側ループの実行可能ワークフロー `harness-evaluate-cycle`**（ROADMAP P4・二階ループを1起動で）:
  `.claude/skills/gatecrate-evaluate/takt/` に追加。外側ループ（4計測→5評価→6ルーティング）を**1起動で回す
  シーケンス型 TAKT ワークフロー** + `harness-auditor` persona（2軸・5判定・反事実の罠回避・提案のみ）。判断は
  persona、TAKT は順序付け・監査で**撤去は自動実行しない**（修理は `harness-liveness-converge` へ・撤去/統合は
  人間承認の提案へ）。これまで「部品＋手順書」だった外側ループを**1コマンドで通る workflow** にした。
  **gatecrate 自身で実走実証**: measure→evaluate→route が完走（2反復・~14m・全12層 keep・全 ALIVE）。
  **二階ループの収束を実証**——Cycle 1（手動評価）が見つけた consolidate-candidate を PR #46 が閉じ、Cycle 2 が
  「候補ゼロ・全 keep」を確認（`docs/evaluations/2026-06-14-2.md`）。所見: サンドボックスで `sh`/`gh` がブロックされ
  measure が静的解析に退避、新ゲートは `unconfirmed` と明記（推測しない）。`development-workflow` も外側ループが
  workflow 化された旨に更新。**レビュー指摘を反映**: 消費者は install でスクリプトのみ vendoring し
  `docs/harness-roi-evaluation.md` は入らないため、auditor が記憶頼みになる懸念。→ 方法論の中核（2軸・removal3条件・
  反事実の罠・**5判定の定義**）を `harness-auditor` persona に**自己完結**させ、doc 参照は「あれば読む」に降格
  （doc 不在でも憶測なく適用可能に）。
- **開発ライフサイクル概観 `development-workflow`（二重ループ・モデル）**: `docs/development-workflow.md`/`.ja.md`
  を新規。gatecrate の各部品が「実装→CI→評価→是正」の開発フローとしてどう噛み合うかを正典化。内側ループ
  （速い・毎PR・コードを直す）と外側ループ（遅い・周期的・非ブロッキング・ハーネスを直す）の二重構造、
  6ステップ↔資産の対応、人間ゲート（提案承認・escalation-only 除外）、6→1 フィードバック、2026-06-14 自己評価を
  外側ループ一周の実例として収録。ピラミッド頂点の概観として README 両言語の Documentation 表に「start here」
  で追加し、抜けていた test-selection-roi / gatecrate-evaluate の行も補完。
- **評価スキル初回実走 + EN/JA doc-currency ゲート**（ROADMAP P4・二階ループ一周完結）:
  `gatecrate-evaluate` を gatecrate 自身に初実走し、計測（全層 fires=0・ShellCheck が CI 秒の約60%）＋生存証明
  （予防3ゲート ALIVE）から **removal=0／consolidate-candidate 1件（EN/JA ドキュメント手動同期）** を導出
  （レポート `docs/evaluations/2026-06-14.md`）。検出した consolidate を実際に閉じ、**二階ループ（計測→評価→是正）を
  一周完結**: `core/scripts/check-doc-currency.sh` を追加（`*.md`/`*.ja.md` 対の片側だけ編集した PR を STALE 検知・
  孤立 doc は対象外・base 不能や `DOC_CURRENCY_SKIP=1` で skip）。self-harness CI（PR 時）に配線、回帰テスト
  `tests/test-doc-currency.sh`（10ケース）を lint に配線、install standard と全 sync-manifest に追加。
  **レビュー指摘2件を反映**: (1) doc-currency を変更セット駆動に書き換え、対の**片側だけの削除/リネーム**も
  STALE 検知（既存 `*.ja.md` のみ走査する穴を解消・JA 翻訳の追加のみは許容）。(2) `install_script` を修正し
  git-first スクリプト（check-doc-currency / probe-gate-liveness / check-file-line-limit）を **raw コピー**
  （従来は深度畳み込み sed が `../..`→`..` を書き換え byte 不一致＝fresh install 直後に sync-check が偽
  `[UPDATED]` ドリフトを出す潜在バグ）。
- **決定論的 pre-loop triage（escalation-only ゲートの converge 除外）**（ROADMAP P4・exp3 の構造的修正）:
  ゲートファイルに `# gatecrate-scope: escalation-only` マーカーを置けるようにし、`probe-gate-liveness.sh`
  に `--repairable-only` フラグを追加。このモード（harness-liveness-converge の command ゲートが使用）は
  マーカー付きゲートを**マシン判定で SKIP** する＝converge ループは human-owned ゲートを構造的に見ない。
  既定モード（生存証明）は従来どおり全ゲートを probe し、壊れた escalation-only ゲートを human 向けに surface する。
  exp3 で「persona 規則ではループ圧力に勝てず governed ゲートを編集してしまう」問題を、exp3b で**マーカー付き
  1反復完了・governed 無編集**と実証して根絶。回帰テスト 性質6 を追加（probe test 17ケース緑）。
- **二階ループ TAKT ワークフロー `harness-liveness-converge`**（ROADMAP P4・三段目）:
  `.claude/skills/gatecrate-evaluate/takt/` に追加。生存証明プローブ（`probe-gate-liveness.sh`）を
  `type: command` ゲートにし、DEAD ゲートを persona（`gatecrate-evaluate`）が修理して全 ALIVE へ収束させる。
  mutation-config loop と同型。**仮消費者で実走実証**: 単一破損ゲートを1反復で修理（~2m20s）、異なるバグ型の
  2ゲートを one-change-per-turn で2反復収束（~3m5s）、いずれも弱体化・削除なし。剪定は機械判定できないため
  本ループは修理のみで、撤去は ABORT で人間承認の提案に回す。**実走で構造的限界を発見**（exp3）: ガバナンス保護
  ゲートで persona は反復1で正しく ABORT したが、converge-to-green の command ループは exit code 駆動のため
  ABORT を尊重できず、反復2でループ圧力下に編集を正当化した。**再走で persona 規則だけでは直らないことも実証**:
  「ABORT 堅持」規則6 を入れて同条件を再走したが、抵抗が1反復延びた（反復1・2で ABORT）だけで反復3でやはり編集
  （「2回 ABORT してもループが戻る＝ABORT は終端でない」と推論）。→ prompt ガードは構造的圧力に勝てず、唯一の
  確実な対策は**エスカレーション専用ゲートを converge スコープ外に保つ手続き的/決定論的 triage**。設計規則を
  persona・ワークフローヘッダ・README に明文化し、決定論的な pre-loop triage（`# gatecrate-scope: escalation-only`
  マーカーで除外）を次の kit 機能として記録。
- **生存証明プローブの消費者対応**: `core/scripts/probe-gate-liveness.sh` が `harness.config.sh` の
  `PROBE_GATES`（`<path>:<kind>` 列）を読み、消費者自身の予防ゲートを probe できるようにした（未設定なら
  kit 既定3ゲートにフォールバック＝後方互換）。`tests/test-probe-gate-liveness.sh` に消費者経路の性質を追加。
  **レビュー指摘2件を反映**: (1) ゲート exit code を厳密判定（0=DEAD / 1=ALIVE / その他=setup error）し、
  kind の打ち間違い（`secret`・コロン欠落）を**偽 ALIVE にせず setup error で落とす**（非ゼロ一律 ALIVE の
  穴を塞ぐ・回帰テスト追加）。(2) probe を `install.sh` minimal core と全 sync-manifest に追加、
  `collect-gate-history.sh` を standard core/manifest に追加し、**消費者が install/sync で実際に入手できる**ように
  した（従来はワークフロー入口なのに未配布で `not found` になりえた）。
- **二階ループ計測スクリプト**（ROADMAP P4・ROI手順①②）: `core/scripts/collect-gate-history.sh` を追加。
  CI 実行履歴（`gh`）から各ゲート(=CIステップ)の `runs / fires / fire_rate / total_seconds / avg_seconds` を集計する。
  fetch 層（gh 依存・非決定論）と aggregate 層（stdin TSV・純 POSIX・`tests/test-collect-gate-history.sh` でゲート）を
  分離し、判断の核を決定論かつテスト可能にした。生存証明プローブ（`probe-gate-liveness.sh`・手順③）の**補完**で、
  検出層の発火実績と継続 CI コストを供給する。`ci.yml` lint に集計層の回帰テストを配線。
- **評価スキル `gatecrate-evaluate`**（ROADMAP P4）: 計測出力＋生存証明を `harness-roi-evaluation.md` の2軸・
  removal 3条件論理積・5判定にかけ、剪定/統合候補を根拠つきで提示する persona 層。「発火ゼロ＝無駄」の反事実の罠回避、
  安全制約（シークレット/禁止権限）の自動撤去禁止、提案のみ（実行は人間）を明記。
- **検証選定ガイド `docs/test-selection-roi.md` / `.ja.md`**: PBT / ステートフル PBT / ミューテーション / モデル検査を
  ROI で選ぶ判断手引き。model-code gap（モデル検査は CI 回帰ゲートでなく設計時ハーネス）、断片化チェック
  （gatecrate の価値∝ツールチェーン断片化度）、1ルール=2反映、ドメイン知識深化ループを成文化。`harness-roi-evaluation`
  から相互リンク。「選定（何を作るか）」と「剪定（効いているか）」を再利用可能ハーネスの両輪として接続。
- **第三者ソフトウェアの帰属表示**: `THIRD_PARTY_NOTICES.md` を新規追加。gatecrate-setup スキルが任意で連携する
  **TAKT**（[nrslib/takt](https://github.com/nrslib/takt)・MIT・© 2026 Masanobu Naruse）を明記。gatecrate は
  TAKT のソースを同梱せず（`npm install -g takt` の外部依存）、`takt/` 配下は gatecrate 自作（TAKT のワークフロー
  スキーマに準拠）であることを確認・記載。MIT は再配布時のみ表示義務が生じるため厳密には義務外だが、出所明確化のため帰属。
- **sync の co-dependency 自動解決**（issue #34）: スクリプトが別の kit スクリプトを source する依存を
  `$ROOT/scripts/<x>` の静的抽出で扱う（依存宣言がコード自体に在りドリフトしない）。`sync-check.sh` は
  採用済みスクリプトが source する**未採用**の kit スクリプトを `[DEP]` として要対応に検出（回帰テスト4ケース目）。
  `sync-propose.yml` は consumed_scripts の依存を**推移的に同期対象へ取り込む**（消費者がヘルパーを採り忘れても
  自動で同梱）。`consumed_scripts` のフラットさに起因する破損（localmd #194 で実際に発生）を仕組みで防ぐ。

### Changed
- **プロジェクト名を `harness-kit` → `gatecrate` に改名**: GitHub 上に同名リポジトリが30件以上存在し、さらに
  「harness」が AI コーディングエージェントのハーネス（prompt-first scaffolding / skills / MCP）を指す流行語として
  飽和したため、本キット（古典的な CI/品質ゲートのスクリプト集）の意味が埋もれ発見性を失っていた。あわせて CI/CD
  企業 [Harness](https://www.harness.io/) との同ドメイン商標近接も回避する。agent skill `harness-setup` →
  `gatecrate-setup` も改名。**互換性維持のため** `harness.config.sh` ファイル名と `harness_kit_version`
  manifest キーは据え置き（既存消費者の `sync-manifest.yaml` / CI 配線を壊さない）。

### Fixed
- **sync-propose の同期 PR が消費者 CI を起動しない問題に対処**（issue #35）: 同期 PR を `GITHUB_TOKEN` で
  作成すると GitHub の再帰防止仕様で消費者の CI が走らず、ゲートなしでマージされうる（メタハーネス原則違反）。
  PR 作成を `secrets.HARNESS_SYNC_PAT`（あれば）優先に変更し CI を自動起動可能に。未設定時は GITHUB_TOKEN に
  フォールバックしつつ「**CI が自動起動しない・マージ前に手動で回すこと**」を PR 本文に明示警告。テンプレ冒頭に設定手順を追記。
- **Kotlin ヘルパーの co-dependency を明示エラー化**（localmd #194 で判明）: v0.8.0 で
  `run-unit-tests.sh` / `run-mutation-tests.sh` が `android-kotlin-compile.sh` を source する必須依存に
  なったが、既存消費者が前者だけを sync するとヘルパー欠落で cryptic に失敗した（greenfield では4本
  同時採用で露見せず）。ヘルパー欠落時に**何を consumed に足すべきか案内する明示エラー**で落とすガードを追加。
  AGENTS.md にスクリプト間 co-dependency の扱いを、アダプタ README に必須依存である旨を明記。
  sync 機構自体の依存自動解決は未対応（別 issue で追跡）。

## [v0.8.0] - 2026-06-14

### Changed
- **`sync-check.sh` を採用集合（opt-in）モデルに変更**（issue #28）: 部分採用の消費者で、未採用の
  kit スクリプトを一律 `[NEW]`＝「同期が必要」と誤報告していた問題を解消。`sync-propose.yml` と同じく、
  消費側 `sync-manifest.yaml` の `consumed_scripts`（無ければ消費側 `scripts/` の実在ファイル）を採用集合と
  し、**採用済みファイルのドリフトのみ**を要対応（`[UPDATED]`/`[MISSING]`）とする。未採用は件数のみの情報扱い。
  終了コードも「採用済みにドリフト無し＝0」に整理。回帰防止テスト `tests/test-sync-check.sh` を追加し
  CI（lint ジョブ）で実行する。

### Added
- **ハーネス ROI 評価方法論**（`docs/harness-roi-evaluation.md` / `.ja.md`）: 入れた層を時間軸で
  **keep/strengthen/consolidate/remove** 判定する評価方法論。kit は層の *選択*（profiles）と *消費・同期* は
  持つが *評価・剪定* の方法論を同梱していなかった（ROADMAP の実証フロー先頭「評価」が未出荷）。**2軸**で評価:
  第1軸=CI コスト×頻度による removal 積判定、第2軸=維持負荷（ドリフト誘発/認知負荷・重複/人的維持時間）による
  consolidate 判定。**第2軸の意義**は、安価な層が第1軸では永久に removal 候補にならず評価が層の純増を追認する
  問題（kit ミッション「張るほど維持費が積み上がる」が警告する過剰ハーネス）を、CI 秒と直交する軸で検出すること。
  消費者 **localmd-reader でドッグフーディング済み**（第1軸 removal=0 だった同一ハーネスから第2軸が
  consolidate-candidate 4件を実測抽出）。
- **Android×Kotlin の test/mutation 経路**（issue #25 Gap1）: `adapters/android-jvm` の
  `run-unit-tests.sh` / `run-mutation-tests.sh` が `.kt` を扱えるようになった。`.kt` があれば
  `kotlinc` で先にコンパイルして `.class` を混ぜ、既存の JUnit5/PITest 経路にそのまま流す
  （Gradle/AGP 非依存・Android SDK 不要を維持）。混在コンパイルは新ヘルパー
  `adapters/android-jvm/scripts/android-kotlin-compile.sh` に集約し、2スクリプト間のドリフトを防ぐ。
  実消費者 **vibe-coder の `:exec` モジュール（マルチモジュール・Kotlin・JUnit4・NDK）で実走検証済み**
  （JUnit4 テスト5件緑 / 純関数 classify の変異 100% kill・閾値80%）。`.kt` が無ければ `kotlinc` は
  取得されず従来の Java 限定挙動と完全一致。mutation.yml の変更検知も `.kt`／Kotlin ソース dir を含むよう拡張。
  - dogfooding で判明した移植性改善: **マルチモジュール対応**（`JVM_MAIN_SRC_DIRS`/`JVM_TEST_SRC_DIRS`）、
    **Kotlin `internal` 越境**（test compile に `-Xfriend-paths` で main 出力を渡す。無いと internal 使用
    プロジェクトで test がコンパイル不能）、**compile 時の Android 依存除外**（mutation にも `MAIN_SOURCES_EXCLUDE`）、
    `run-unit-tests.sh` を git-first ROOT 解決 + harness.config.sh 自動 source（mutation 側と一貫化）。
- **NDK / native build 対応**（issue #25 Gap2）: `adapters/android-jvm/workflows/ci.yml` が
  repository variables 経由で `ANDROID_NDK` / `ANDROID_CMAKE` を sdkmanager にオプション install
  するようになった（未設定ならスキップ）。新スクリプト `check-native-libs.sh` が、APK 内の
  `lib/<abi>/<name>.so` 同梱を実機 sideload 前に CI で一次検証する（`NATIVE_LIB_NAMES` 設定時のみ）。
- **実消費者 CI でループをクローズ**: vibe-coder PR#3（実 AGP+Kotlin+NDK・マルチモジュール）で、kit の
  mutation ゲート（実 Kotlin の classify を 100% kill）と `check-native-libs.sh`（実 AGP+NDK ビルドの
  実 APK で `.so` 同梱を assert）が **CI 緑**。Gap1/Gap2 とも合成スモークでなく実消費者 CI で実証された。

### Fixed
- `adapters/kotlin/scripts/run-tests.sh` が Lean4 スクリプトのコピペ（`lake build`）になっており、
  Kotlin 消費者で確実に壊れていた（#23 で混入）。README どおり `./gradlew test koverVerify` を
  実行するよう修正。

## [v0.7.1] - 2026-06-14

### Added
- Shipped mutation gates for four more adapters — `adapters/rust` (cargo-mutants), `adapters/go`
  (gremlins), `adapters/typescript` (Stryker), `adapters/kotlin` (PITest) — each via a
  `scripts/run-mutation.sh` and a `mutation` CI job, **validated green on a real pull_request** in
  each stack's consumer. The kit's signature gate (mutation) is no longer only on android-jvm and
  python: **six of eight stacks now ship a validated mutation gate.** Haskell (immature mutation
  tooling) and Lean4 (the build already proof-checks) remain documented N/A. This is the depth +
  consistency follow-up to the breadth expansion — the new adapters are no longer single-gate.

## [v0.7.0] - 2026-06-14

### Added
- Three more stack adapters — **`adapters/kotlin/`** (Gradle + kover coverage rule),
  **`adapters/haskell/`** (cabal test), **`adapters/lean4/`** (lake build = typecheck + proof
  check) — each validated end to end on a private consumer (green on a real pull_request), with
  the three core hygiene scripts byte-identical across all stacks. The kit now spans **eight
  stacks**. Lean4 shows the boundary generalizes beyond example-based testing: for a proof
  assistant the meaningful gate is the build (it proof-checks the `by decide` examples), so the
  adapter ships a build gate instead of coverage/mutation.
- `install.sh --profile auto` now also detects `lean-toolchain` → lean4, `*.cabal` → haskell, and
  a `kotlin("jvm")` Gradle build without an AndroidManifest → kotlin (so it is not confused with
  the android-jvm stack). `--profile kotlin|haskell|lean4` install the matching adapter.

## [v0.6.0] - 2026-06-14

### Added
- Three more stack adapters — **`adapters/go/`**, **`adapters/typescript/`**, **`adapters/rust/`** —
  each with a test+coverage gate (`go test`/`go tool cover`; `vitest --coverage`;
  `cargo llvm-cov --fail-under-lines`), a consumer-ready `workflows/ci.yml`, a README, a
  sync-manifest, and a profile. Each was validated end to end: a private consumer per stack ran
  `fitness` + `test` green on a real pull_request, with the three core hygiene scripts
  byte-identical across all of them. The kit now has five stacks (android-jvm, python, go,
  typescript, rust) behind its "portable" claim, not one.
- `install.sh --profile auto` now also detects `Cargo.toml` → rust, `go.mod` → go,
  `package.json` → typescript; `--profile go|typescript|rust` install the matching adapter.

## [v0.5.2] - 2026-06-14

### Added
- `install.sh --profile auto` — detects the stack from the target project and selects a profile:
  `pyproject.toml` → python, `settings.gradle`/`build.gradle`/`pom.xml` → standard, otherwise
  minimal. Adds a `python` profile (`profiles/python.yaml.example`) and installs the Python
  adapter scripts for it. `--help` and the post-install guidance now cover auto and python.

### Fixed
- The installer's minimal/core step tried to copy `core/scripts/check-file-sizes.sh`, which does
  not exist in core (that script is the android-jvm adapter's), so every install silently
  `[SKIP]`-ed the file-size gate. Now installs the generic `core/scripts/check-file-line-limit.sh`.
- Guarded a `$TARGET_DIR` reference that abutted a full-width parenthesis, which some `sh`
  implementations folded into the variable name (`unbound variable` under `set -u`); braced it.

## [v0.5.1] - 2026-06-14

### Changed
- Validated the full Android/Gradle build CI end to end — the one part of "can the kit construct
  CI?" that was still only partially proven. A minimal Android consumer (single module, no flavors/
  signing/billing) wired with the kit ran `fitness` + `android-build` green on a real pull_request
  (AGP 8.13.1 / Gradle 8.14 / Android SDK 35, ~1m20s). Recorded the honest finding in
  `adapters/android-jvm/README.md`: the adapter's `ci.yml` test/gradle-build jobs are shaped by
  localmd (billing prep, free/pro flavors, signing, bundleRelease) and are a TEMPLATE — a generic
  Android consumer must swap in its own Gradle tasks. The core hygiene CI is turnkey; the Android
  build CI is not.

## [v0.5.0] - 2026-06-14

### Added
- **`adapters/python/`** — the second stack adapter (uv): `run-tests.sh` (pytest + coverage floor)
  and `run-mutation.sh` (mutmut against a floor), plus a consumer-ready `workflows/ci.yml` and a
  README. This is the kit's first evidence that the core/adapter boundary is genuinely
  stack-agnostic: a private Python consumer ran fitness + test + mutation green on a real
  pull_request, **with the core hygiene scripts byte-identical to the android-jvm consumer's**.
  `sync-manifests/python.yaml` whitelists the adapter for downstream sync.
- Honest porting frictions from building the Python mutation gate, recorded in the adapter README:
  `mutmut run` has no clean threshold-exit (so the gate parses `export-cicd-stats` and enforces the
  floor itself), and mutmut's `mutants/` working copy collides with pytest collection (fixed with
  `testpaths`/`norecursedirs`). These are the real, measured cost of "portable".

### Changed
- README / structure docs and the layer table now show two adapters (android-jvm, python); the
  "portable" claim is no longer single-stack.

## [v0.4.7] - 2026-06-14

### Added
- `core/workflows/ci.yml` — a generic, stack-agnostic CI workflow running only the core hygiene
  gates (conventional PR title, per-file line limit, committed-secret scan). Until now `core/
  workflows/` was an empty placeholder, so a consumer of any stack had to hand-assemble its
  hygiene CI; the kit shipped the scripts but not the workflow that wires them. Validated end to
  end: this exact `fitness` job ran green on a real pull_request in a JVM consumer (alongside the
  mutation gate). This makes CI construction a shipped core artifact and works on any stack.

### Changed
- Enabled branch protection on the kit's own `main` (`lint` + `self-harness` as required status
  checks, strict, no force-push/deletion) — ROADMAP P1's last open item. The kit now gates itself
  with the very checks it ships, instead of relying on a clean merge-state by convention.

## [v0.4.6] - 2026-06-14

### Changed
- Executed the TAKT mutation-config workflow end to end (it was schema-validated only in v0.4.5)
  and folded the results back in:
  - **Renamed** `harness-config-derive.workflow.yaml` -> `harness-config-derive.yaml`. TAKT
    resolves a workflow by `<name>.yaml`; the `.workflow.yaml` name did not resolve.
  - **Sharpened the persona**: it must ratchet `MUTATION_THRESHOLD` UP to the achieved green
    score. The real run passed the default floor 79 while the code scored ~92 and left a genuine
    SURVIVED mutation tolerated — the floor must lock in the coverage the code actually has.
  - **SKILL.md Phase 9 + takt/README.md** now carry the concrete install/setup/run commands
    (`npm install -g takt`, `~/.takt/config.yaml`, `.takt/workflows/<name>.yaml`, the
    `--pipeline --skip-git` invocation) and the executed-status evidence. The run used provider
    `claude`, converged in one iteration, and TAKT machine-executed the command gate (verified by
    build artifacts + session log); an independent re-run confirmed the gate exits 0.

## [v0.4.5] - 2026-06-14

### Added
- `.claude/skills/gatecrate-setup/takt/` — an optional TAKT orchestration for the mutation-config
  iteration loop. Validated against TAKT's own yaml-schema.md, the loop maps not to a multi-step
  state machine (TAKT rules cannot branch on a shell exit code) but to a single `derive` agent
  step guarded by a `type: command` quality gate that runs `run-mutation-tests.sh`: TAKT executes
  it, passes only on exit 0, and on failure re-invokes the same step with the exit code + triage,
  which drives the next refinement. Ships the workflow, the deriver persona (the SURVIVED-vs-
  NO_COVERAGE judgment TAKT does not supply), and a README. Schema-validated, not yet executed.

## [v0.4.4] - 2026-06-14

### Changed
- Recorded the mutation-iteration validation. A throwaway pure-JVM consumer (harness-probe-jvm),
  built to trigger all four Phase-4 derivation points, exercised `run-mutation-tests.sh` end to
  end. The grep recipes nailed the mechanical values; the "8->10" iteration converged in three
  deterministic gate runs (javac unresolved-symbol -> EXTRA_MAIN_SOURCES; PITest SURVIVED -> add a
  test, NO_COVERAGE -> EXCLUDED_CLASSES; green -> MUTATION_THRESHOLD), green in CI on temurin JDK17.
  SKILL.md and ROADMAP P3 now carry this evidence and its implication for orchestrating the loop:
  the loop is regular and gate-terminated (a good fit for a TAKT-style state machine), but the
  SURVIVED-vs-NO_COVERAGE fork is judgment the persona/skill must supply, not the orchestrator.

## [v0.4.3] - 2026-06-14

### Changed
- Ran the `gatecrate-setup` skill against gatecrate itself as a second, different-stack consumer
  (shell-only, non-Android — a stricter probe than another Android app). The run exposed and fixed
  two defects on the core-only path:
  - `profiles/minimal.yaml.example` referenced the Android adapter `check-file-sizes.sh`
    (`src/**.java`-only), so a non-Android minimal consumer would scan nothing. Switched to the
    language-agnostic `check-file-line-limit.sh`.
  - `SKILL.md` had no core-only Phase 4 recipe (it was entirely Android/mutation). Added the
    minimal path and recorded the gatecrate accuracy (3/3 applicable core decisions automatic;
    the 7 Android-specific decisions — including the iterative ones — are N/A on a shell stack).

### Added
- `harness.config.sh` at the kit root — gatecrate as a faithful consumer #0 (core-only). The
  self-harness file-line gate now sources its values from here instead of inline CI env, so the
  kit dogfoods the config -> script wiring a real consumer uses, not just the script.

## [v0.4.2] - 2026-06-13

### Added
- `core/scripts/check-file-line-limit.sh` — a language-agnostic per-file line-count gate, the
  stack-agnostic sibling of `adapters/android-jvm/check-file-sizes.sh` (which is hardwired to
  `src/**.java`). It scans caller-chosen paths/name-patterns (`FILE_LINE_PATHS`, `FILE_LINE_NAMES`),
  honors the same exceptions-file mechanism, and resolves its repo root via `git rev-parse` (the
  consumable model), so the identical file works in the kit and in a consumer's `scripts/`.
- `ci.yml` `self-harness`: the kit now dogfoods its own 300-line rule on its `*.sh` and `*.md`
  using that script. This closes the gap the self-dogfooding exercise surfaced — the kit could
  preach a 300-line rule (CONTRIBUTING) but had no language-agnostic tool to enforce it on its
  own shell scripts. Added to the `android-jvm` sync-manifest as a kit-managed core script.

## [v0.4.1] - 2026-06-13

### Changed
- `gatecrate-setup` skill: sharpened from an accuracy measurement against localmd-reader (the
  built ground-truth harness). Blind application of the recipes reproduced 7/10 setup decisions
  fully automatically (package, BuildConfig fields, target classes/tests, excluded tests), 8/10
  with one mutation run (the threshold floor), and 10/10 with the two iteration-driven items now
  given concrete loops: EXTRA_MAIN_SOURCES via compile-error discovery, and the NO_COVERAGE-based
  EXCLUDED_CLASSES (e.g. i18n string tables). Recorded the measured accuracy in the skill.

## [v0.4.0] - 2026-06-13

### Added
- `.claude/skills/gatecrate-setup/SKILL.md` — an agent skill (Claude Code / Codex) that sets up a
  full gatecrate-based harness on a target project. It encodes the per-project judgment a static
  installer cannot do: choosing consumed_scripts, generating `harness.config.sh` (TARGET_CLASSES
  from package structure, BUILDCONFIG_FIELDS from the BuildConfig references in the code,
  EXTRA_MAIN_SOURCES, the mutation floor from the current green score), wiring CI, installing the
  sync workflow, verifying each gate, and avoiding the traps hit while doing this for localmd-reader.
  The kit now carries its own how-to-set-me-up procedure.

## [v0.3.1] - 2026-06-13

### Fixed
- `sync-propose.yml`: scope the downstream sync to the consumer's `consumed_scripts`
  (its opt-in list) instead of the kit's entire whitelist. The old behavior copied every
  whitelisted script into the consumer, overwriting scripts a partial consumer never adopted
  (and which need config/root resolution it has not set up) — destructive. Now only the scripts
  the consumer declared as consumed are synced; the kit whitelist is used only to validate that
  each is a legitimate kit-managed file. This makes update propagation safe and incremental.

## [v0.3.0] - 2026-06-13

### Added
- `run-mutation-tests.sh`: logic injection points so a consumer with project-specific
  mutation setup (not just values) can use the generic script:
  - `BUILDCONFIG_FIELDS` — the field declarations the generated BuildConfig stub exposes
    (default: a single `PRO_FEATURES_ENABLED` flag), for code that references extra flags.
  - `EXTRA_MAIN_SOURCES` — repo-root-relative source paths the default scan excludes but the
    mutation set still needs (e.g. one presentation file the Android-free code references).
  Also adopts the consumable model (git-resolved repo root + sources `harness.config.sh`).

## [v0.2.2] - 2026-06-13

### Fixed
- `install.sh`: the ROOT path rewrite only collapsed a 2-level `/../..` to `/..`, so
  adapter scripts (3-level `/../../..`) were mis-rewritten to `/../..` (2-level) and
  broke when installed into a consumer's `scripts/` (1-level). Collapse any run of
  `/..` segments to a single `/..`, so both core (2-level) and adapter (3-level)
  scripts resolve the consumer repo root correctly. Verified by running
  `install.sh --profile standard` and checking every installed ROOT is 1-level.
  (Scripts that resolve the root via `git rev-parse` do not depend on this rewrite.)

## [v0.2.1] - 2026-06-13

Pilot of the actual consumption mechanism (ROADMAP P2), proven end-to-end with
one script before scaling to all 27 adapters.

### Added
- `templates/harness.config.sh.example`: the consumer config interface as **shell**
  (sourced, sets env vars) — the scripts read env vars, so YAML could never wire them.

### Changed
- `adapters/android-jvm/scripts/check-file-sizes.sh`: resolve the repo root with
  `git rev-parse` (fallback to the relative path), so the identical file runs both
  in this kit and when installed into a consumer's `scripts/` — no install-time path
  rewriting, which is what makes kit↔consumer sync diff-free. It now also sources
  `harness.config.sh` from the repo root if present (the config→script wiring).
  Behavior and defaults are unchanged when no config is present.

## [v0.2.0] - 2026-06-13

Upstreams genuine harness improvements made on the localmd-reader consumer since
v0.1.3, ported onto the kit's generic (parameterized) form. Consumer-form drift
(Termux shebang, consumer ROOT depth, hardcoded package IDs) was deliberately
**not** returned, so the kit stays portable.

### Fixed
- `adapters/android-jvm/scripts/emulator-smoke.sh`: crash detection in
  `assert_alive` matched `$PKG` against the `FATAL EXCEPTION` line, which never
  carries the package id (it appears on the following `Process: <pkg>` line), so
  an app crash that the process recovered from could go undetected. Now correlate
  the crash block (`grep -A3 "FATAL EXCEPTION" | grep "Process:.*$PKG"`).

### Added
- `adapters/android-jvm/scripts/version-code-bump.sh`: guard so a version-code-only
  bump is disabled for normal releases (it would leave `VERSION_NAME` unchanged,
  letting two uploads share a user-visible version). Set `ALLOW_VERSION_CODE_ONLY=true`
  only for a documented emergency rebuild.

### Changed
- `adapters/android-jvm/scripts/capture-theme-screenshots.sh`: documented why the
  launch wait uses fixed sleeps instead of a dumpsys-based foreground poll
  (the focus/resumed greps proved unreliable on CI software-renderer emulators).

## [v0.1.3] - 2026-06-09

### Fixed
- Corrected deployment paths in core scripts (`scripts/` not `core/scripts/`).

## [v0.1.2] - 2026-06-09

### Changed
- Improved code comments for clarity: glob patterns in check-no-committed-secrets.sh,
  URL formatting in run-unit-tests.sh, dependency rationale in run-mutation-tests.sh,
  R.java collection timing in build-release-aab.sh

## [v0.1.1] - 2026-06-07

### Added
- English documentation: `README.md` rewritten in English (source of truth)
- Japanese README: `README.ja.md` added as translation
- EN/JA sync rules documented in `README.md`
- `CONTRIBUTING.md` translated to English

## [v0.1.0] - 2026-06-07

### Added
- Initial release: 3-layer kit (core / adapters / project-specific)
- sync-manifest mechanism for whitelist-driven file propagation
- `install.sh` installer entry point
- Android + JVM adapter (`adapters/android-jvm/`)
- Profile definitions: minimal / standard / full
