# gatecrate ロードマップ

## このドキュメントの目的

gatecrate を**複数プロジェクトで再利用できる移植可能なハーネス**へ育てるための開発方針を、
判断の根拠とともに示す。読者はここを見れば「次に何を・なぜその順で行うか」を把握できる。

英語版・詳細設計は将来 `README.md` から参照する（本ファイルは方針の正典）。

---

## 起点スナップショット（2026-06-13・v0.2.0 時点。以降の進捗は下の各フェーズのチェックボックスが正）

| 項目 | 実態 |
|------|------|
| 構造 | 3層（generic core 9本 / stack-specific adapters: android-jvm 27本+workflow / project-specific templates+profiles） |
| 実消費者 | **実質ゼロ**。localmd-reader は core 9本のみ採用（Phase 1・#141）。**アダプタ27本は未採用＝自前のハードコード版を稼働中**（Phase 2/3 未完）。アダプタ層は「存在するが誰も実行していない」 |
| kit 自身の CI | （本ロードマップの P1 で導入）。それ以前は kit スクリプトを検証する仕組みが無く、消費側が壊れて初めて欠陥が判明する状態だった |
| アダプタ/移植性 | android-jvm 1種のみ。「portable」は未実証 |
| 貢献の向き | 改善は消費側（localmd）で先に生まれる。v0.2.0 は手作業で上流還元した（consumer→kit）。仕組み化されていない |

## 根拠となる原則（なぜこの順か）

**portable な gatecrate の価値は「実消費者の数」に比例する。** 消費者が2未満なら、kit は
消費側に直接スクリプトを置くより二重管理・ドリフト・同期コストが上回る純オーバーヘッドになる。
**だから、機能や2つ目のアダプタを足す前に、まず「消費ループが1消費者で実際に回る」ことを証明する。**
未実証の汎用性の上に汎用性を積むと砂上の楼閣になる（v0.2.0 調査で観測した「全27アダプタのドリフト」＝
Phase 2/3 未完が、まさにこの症状だった）。

方針: **複数PJ展開を目指す（オーナー決定 2026-06-13）。戦略「ループを先に証明」で P1→P2→P3。**

---

## P1 — 基盤（kit を安全に育てられる状態にする）

**なぜ最優先か**: 成長は kit を頻繁に変更することを意味するが、現状 kit には変更を検証する CI も
ブランチ保護も無い。土台が無いまま機能を積むと、壊れたスクリプトが消費者へ伝播する。

- [x] **kit 自身の CI**（`.github/workflows/ci.yml`）: 全 `*.sh` に `sh -n`（構文）+ shellcheck（まず
  `-S error`、実バグのみ・advisory から ratchet）+ sync-manifest 整合性（列挙パスが全て実在するか）。
- [x] **ブランチ保護**: `main` に `lint` と `self-harness` を required status check として設定（strict=最新必須・
  force-push/削除禁止）。CI が実績を出した後に常設、というメタハーネス原則どおり。これで「自分を gate しない
  メタハーネス」の自己矛盾を解消。
- [x] **汎用 CI ワークフローを core へ出荷**（消費者で露出した穴）: `core/workflows/` が空で、消費者は hygiene CI を
  手組みする必要があった。`core/workflows/ci.yml`（PRタイトル/ファイル行数/シークレットの3ゲート・スタック非依存）を
  追加。private 消費者で**実 pull_request 上で緑**を確認済み（fitness 5s + mutation 14s）。CI 構築が core の出荷物に。
- [x] **双方向貢献モデルの明文化**: README の「read-only references」前提は v0.2.0 の上流還元と矛盾するため、
  consumer→kit（上流還元）→ kit→other-consumers（PR 同期）の双方向モデルへ更新。CONTRIBUTING に上流還元フローを追記。
- [x] **自己ドッグフーディング**（consumer #0）: kit の CI が kit 自身の core スクリプトを消費する。
  `ci.yml` の `self-harness` ジョブが `core/scripts/check-no-committed-secrets.sh`（自リポのシークレット検査）と
  `core/scripts/check-conventional-title.sh`（自PRタイトル検査）を実行。CONTRIBUTING が掲げる規則を、kit が出荷する
  ツール自身で kit に強制する。**汎用 core スクリプトが kit リポ（非Android・shellのみ）でそのまま動くことの実証**でもある。
- [x] **汎用ファイルサイズ検査を core へ**（自己ドッグフーディングで露出した穴）: `check-file-sizes.sh` は
  `adapters/android-jvm` 配下で `src/**.java` を走査するため、kit 自身の300行ルール（CONTRIBUTING）を shell
  スクリプトに対して強制できなかった。v0.4.2 で `core/scripts/check-file-line-limit.sh`（言語非依存・glob 指定）を
  追加し、`ci.yml` の `self-harness` が kit 自身の `*.sh`/`*.md` を300行で検査するようにした。kit が自分の規則を
  自分の出荷ツールでドッグフーディングできる状態になった。
- [~] **リリース規律**: タグ発行時の CHANGELOG エントリ必須化（v0.1.3 は欠落していた）。
  v0.8.0 で **GitHub Release を再開**（タグだけ運用で Releases が v0.1.1 に停滞し sync-propose の
  `gh release list` が壊れていた問題を解消）。残: リリース workflow 化（手動 tag+release を自動化）。

## P2 — 消費の証明（初の実 end-to-end 消費者を作る）

**なぜ**: kit のアダプタ層は誰も実行していない＝汎用化が正しいか未検証。1消費者で実際に回して初めて、
パラメータ化（harness.config.sh 方式）が機能することを示せる。

- [ ] localmd-reader の **Phase 2/3 を完成**: kit のパラメータ化アダプタ27本を採用し、固有値を
  `harness.config.sh` に外出し（移行提案書 §3 フェーズ2/3）。これで localmd が初の実消費者になる。
- [x] **sync の差分ゼロを実証 + sync-propose 自動起票を実走**（Phase 2c）: まず `scripts/sync-check.sh` を
  実消費者 vibe-coder に実走し採用済みファイルのドリフト0を確認（issue #25 ループ）。さらに **GitHub Actions の
  `harness-sync.yml`（= sync-propose）を vibe-coder で実 dispatch** し、自動で同期 PR（vibe-coder #5）が起票される
  ことを実証: `consumed_scripts` の4本のみ同期（core 3 は diff-zero でスキップ）、version を v0.7.1→v0.8.0 に bump、
  同期4本は **kit v0.8.0 master と byte 一致**。前提として古かった GitHub Release を **v0.8.0 として発行**
  （タグのみ運用で `gh release list` が v0.1.1 を返す問題を解消・ROADMAP P1 リリース規律も達成）。
  学び: 生 vendoring（git-first スクリプトは install 変換をかけない）でないと偽ドリフトが出る（AGENTS.md に明記）。
  [x] **部分採用消費者の誤検知を解消**（issue #28）: sync-check を採用集合（opt-in）モデルに変更し、
  採用済みファイルのドリフトのみを要対応とした（未採用は情報扱い）。回帰テスト `tests/test-sync-check.sh` を
  CI に追加。vibe-coder で再実走し「採用済みドリフト0・未採用32件は情報」を確認。
- [x] **AGENTS.md 運用規則**: エージェント向け運用規則を `AGENTS.md` に成文化。ペアリング規則
  「`core/`・`adapters/` 変更 PR は同週に逆向きの対（消費者採用 / kit 還元）を作る」を含む。

## 構築スキル（任意PJへ localmd 並みのハーネスを）

機械的 install では固有判断（`harness.config.sh` の値・ロジック注入・floor・どのスクリプトを採用するか）
を埋められない。これは AI エージェント（Claude Code / Codex）の仕事。`.claude/skills/gatecrate-setup/SKILL.md`
に、localmd で実証した手順（評価→プロファイル→消費→config生成→CI配線→同期設置→検証→罠回避）を
エージェント向け手順書として収録した。P3 の「2つ目の消費者を作る」はこのスキルで実行する想定。

- [x] **gatecrate-setup スキル**（v0.4.0）: 任意PJへの構築手順を SKILL.md 化（Codex も本文を follow 可能）。
- [ ] install.sh が consumer の `.claude/skills/` へスキルを配布するオプション。
- [x] **2つ目の実消費者でスキルを実走し精度を検証**: 2経路で実施。
  - **core 経路**: v0.4.3 で gatecrate 自身（shell-only・非Android）に実走。core 決定 3/3 自動を確認し、
    minimal プロファイルと SKILL.md の欠陥2件を修正。
  - **mutation 経路（反復ループ）**: JVM 検証消費者 `harness-probe-jvm`（4トリガーを仕込んだ pure-JVM）で実走。
    grep レシピで機械値（BUILDCONFIG_PACKAGE/FIELDS・TARGET_CLASSES/TESTS）は一発。「8→10」の反復は
    **3回の決定的ゲート実走で収束**（#1 javac未解決シンボル→EXTRA_MAIN_SOURCES、#2 triage の SURVIVED→テスト追加 /
    NO_COVERAGE→EXCLUDED_CLASSES、#3 緑100%→MUTATION_THRESHOLD）。CI でも mutation ゲート緑（temurin JDK17・floor 90）。
  - **含意（TAKT 判断材料）**: ループは「ゲート実走→決定的バケット（コンパイルエラー種別 / SURVIVED・NO_COVERAGE）を
    読む→1つの config 変数 or テストに対応付け→反復」と**規則的**で、終了条件が機械判定（javac exit / score vs floor）。
    TAKT の review→fix 形に適合する。**唯一の不可分な判断**は #2 の「SURVIVED はテスト追加 / NO_COVERAGE は低価値なら除外」
    の分岐で、これは persona（gatecrate-setup スキル）が供給する。TAKT はループを統率・ゲートを強制するが判断は代替しない。

## P3 — 移植性の証明（複数PJ展開）

**なぜ P2 の後か**: 2つ目の消費者/アダプタは「1つ目で回ったループ」を再利用するもの。P2 未完で着手すると、
未検証の土台を2倍に増やすだけになる。

- [x] **2つ目の実消費者で CI を実走**: private な JVM 消費者を kit で配線し、**実 pull_request 上で
  hygiene + mutation ゲートを緑**にした（fitness 5s / mutation 14s）。「CI 構築までできるか」に実証で回答。
- [x] **複数スタックのアダプタで core/adapter 境界の非依存性を実証**: `python`(uv) に加え `go`/`typescript`(vitest)/
  `rust`(cargo-llvm-cov) を追加し、**計5スタック**に。各々 private 消費者で **fitness + test を実 PR で緑**に。
  **決め手は、core 衛生スクリプトを全スタックで byte-identical（無改変）のまま動かせたこと**＝core はスタック非依存と実証。
  移植コストも実測: mutmut は clean な閾値 exit が無く wrapper が要る / `mutants/` が pytest collection と衝突 /
  cargo-llvm-cov は `--fail-under-lines` でクリーン、等（各 `adapters/<stack>/README.md` に記録）。
  さらに Kotlin(Gradle+kover)/Haskell(cabal)/Lean4(lake build) を追加し**計8スタック**に。**Lean4 は境界が
  例ベーステストを超えて一般化することを示す**: 定理証明系では build がそのまま証明検査なので、coverage/mutation
  でなく build ゲートを出荷した。全スタックを private 消費者の実 PR で緑検証済み。
- [x] **フル Android/Gradle ビルド CI を実走**（「CI 構築」の最後のカーブアウト）: 最小 Android プロジェクト
  （単一モジュール）を private 消費者で配線し、ci.yml を `:app:assembleDebug` + `:app:testDebugUnitTest` に
  差し替えて**実 pull_request で緑**（AGP 8.13.1 / Gradle 8.14 / Android SDK 35、約1分20秒）。**所見**: アダプタの
  ci.yml は localmd 形（billing/flavor/署名/bundleRelease）に依存し turnkey ではない＝Gradle タスクの差し替えが要る
  （`adapters/android-jvm/README.md` に明記）。**core 衛生 CI は turnkey、Android ビルド CI は要カスタマイズ**が結論。
- [x] `install.sh --profile auto`（スタック自動判定）の実装: `pyproject.toml`→python /
  `settings.gradle`・`build.gradle`・`pom.xml`→standard / それ以外→minimal を判定して profile を選ぶ。
  Python プロファイル（`profiles/python.yaml.example`）と install での Python アダプタ配置も追加。
  併せて minimal が存在しない `check-file-sizes.sh` を入れようとして毎回 SKIP していたバグ（汎用
  `check-file-line-limit.sh` に修正）も解消。

---

## P4 — 二階ループ（ハーネス自己評価）の自動化

**問題（なぜ要るか）**: 現状のハーネスは「対象を縛る一階ループ」（テスト/ゲートがコードを評価し直させる）は
持つが、「**ハーネス自体が効いているかを計測し、効かない/過剰な層を剪定する二階ループ**」が自動化されていない。
二階が無いと制約は単調増加し、死荷重（コストだけ残り効いていない層）が累積して本当に効く層への投資を圧迫する。
これは mutation testing がテストの検出力を測るのと同じ「ハーネスのハーネス」の関係である。方法論は
[`docs/harness-roi-evaluation.md`](./docs/harness-roi-evaluation.md) に既にあるが、**人/エージェントが手で回す前提**で、
計測も剪定提案も自動化されていない。

**なぜ P3 の後か**: ROI 評価は「運用履歴が溜まった層を再判定する」もので、発火実績・プローブ結果・コスト履歴という
**データを前提**にする。消費ループが回る前（P2/P3 未完）に自動化を作っても判断材料が無く空回りする。
ROADMAP の大原則「ループを先に証明」どおり、データが溜まってから着手する。

**何を作るか**（3層。P2「構築スキル」と対称＝構築スキルが導入判断を担うように、評価スキルが剪定判断を担う）:

- [x] **計測スクリプト**（`core/scripts/`）: 2本に分割して出荷。決定論的・テスト可能。
  - **生存証明プローブ**（`probe-gate-liveness.sh`・v0.9 / #42）: 予防型ゲートに合成違反を注入し「落ちるか＝
    生存証明」を機械判定（ROI手順③）。`self-harness` ジョブで kit 自身に dogfood 済み。
  - **発火・コスト集計**（`collect-gate-history.sh`）: CI 実行履歴（`gh`）から各ゲートの runs/fires/CI秒を
    集計（ROI手順①②）。fetch層（gh依存・非決定論）と aggregate層（stdin TSV・純POSIX・`tests/test-collect-gate-history.sh`
    でゲート）を分離。出力は `gate / runs / fires / fire_rate / total_seconds / avg_seconds` の TSV で、評価スキルが消費する。
    なお doc churn 等の axis-2 維持負荷シグナルは git 履歴ベースで評価スキルが直接測る（CI履歴とは別ソースのため本script外）。
- [x] **評価スキル**（`.claude/skills/gatecrate-evaluate/`）: 計測結果を roi-evaluation.md の2軸・removal の
  3条件論理積・consolidate シグナル・5判定にかけ、**剪定/統合候補を根拠つきで提示**。「発火ゼロ＝無駄」の罠回避
  （安価な予防層は keep）など、exit code に出ない判断を persona が担う。**初回実走済み**（2026-06-14・対象 gatecrate
  自身）: 計測（全層 fires=0・ShellCheck が CI 秒の約60%）＋生存証明（予防3ゲート ALIVE）から、**removal=0
  ／consolidate-candidate 1件（EN/JA ドキュメント手動同期）** を根拠つきで導出。axis-1 だけでは空振りし axis-2 が
  唯一の actionable を炙り出す、という方法論を gatecrate 自身で実証。レポート: `docs/evaluations/2026-06-14.md`。
  検出した consolidate を**実際に閉じた**: `check-doc-currency.sh`（EN/JA 対の片側編集を STALE 検知）を core に追加し
  self-harness CI に配線＝二階ループ（計測→評価→是正）が一周完結。
- [x] **TAKT ワークフロー（外側ループ全体を実行可能に）**: `harness-evaluate-cycle`
  （`.claude/skills/gatecrate-evaluate/takt/`）。外側ループ（4計測→5評価→6ルーティング）を**1起動で回す
  シーケンス型ワークフロー**。判断は `harness-auditor` persona（2軸・5判定・反事実の罠回避）、TAKT は順序付け・
  監査を担い**撤去は自動実行しない**。修理は `harness-liveness-converge` へ、撤去/統合は人間承認の提案に回す。
  **gatecrate 自身で実走実証**: measure→evaluate→route が1起動で完走（2反復・~14m）、全12層 keep・全 ALIVE で
  「nothing to act on」。**二階ループの収束を実証**——Cycle 1（手動評価）が見つけた consolidate-candidate
  （EN/JA手動同期）を PR #46 が閉じ、Cycle 2 が「候補ゼロ・全 keep」を確認（レポート `docs/evaluations/2026-06-14-2.md`）。
  正直な所見: TAKT/Claude サンドボックスで `sh`/`gh` がブロックされ measure が静的解析に退避、新ゲートは
  `unconfirmed (needs gh)` と明記（推測しない＝憶測禁止ルールが実働）。shell+gh が自由な環境で最も信頼できる。
- [x] **TAKT ワークフロー（修理の部分ループ）**: `harness-liveness-converge`（`.claude/skills/gatecrate-evaluate/takt/`）。
  生存証明プローブ（`probe-gate-liveness.sh`）を `type: command` ゲートにし、**DEAD ゲートを persona が
  修理して全 ALIVE へ収束**させる。mutation-config loop（P2 構築スキル Phase 4）と同型。前提として probe を
  消費者対応に拡張（`harness.config.sh` の `PROBE_GATES` で消費者のゲートを probe・未設定なら kit 既定に
  フォールバック）。**仮消費者で端から端まで実走実証済み**: 単一破損ゲートを1反復で修理（~2m20s）、
  異なるバグ型の2ゲートを one-change-per-turn で2反復収束（~3m5s）、いずれも弱体化・ゲート削除なし。
  剪定は機械判定できないため本ループは**修理のみ**で、撤去は ABORT で人間承認の提案に回す（設計の見切りどおり）。
  **実験で構造的限界を発見し、決定論的に解決した**: ガバナンス保護ゲート（人間専有）を converge ループに入れると、
  persona は正しく ABORT するが command ループが exit code 駆動のため圧力をかけ続け、最終的に編集してしまう
  （規則6「ABORT 堅持」を入れても反復3で折れた＝prompt では直らない）。→ **決定論的 pre-loop triage を実装**:
  ゲートに `# gatecrate-scope: escalation-only` マーカーを置き、`probe-gate-liveness.sh --repairable-only`
  （converge ループの command ゲート）が**マシン判定で除外**する。ループは human-owned ゲートを構造的に見ないので
  圧力ゼロ。exp3b で実証（マーカー付きで1反復完了・governed ゲート無編集・既定モードの probe は human 向けに surface）。
  **prompt で直らなかったものを決定論的除外で根絶**した、という二階ループ自身の自己改善例。
- [x] **拡充ループ（外側ループの加える半分）**: ここまでの外側ループは **剪定**（lean に保つ）に偏っていた、という
  非対称性を是正する。設計 `docs/design/expansion-loop.md`：入口シグナルで2サブモードに分割——**Deepen**（mutation
  survivor を入口に「殺すテストを足す」converge ループ）と **Broaden**（変更クラスタのリスク形状→新技法を提案する
  判断シーケンス）。**Deepen を先行実装**: `harness-coverage-deepen`（TAKT converge）+ `coverage-deepener` persona。
  **仮 rust 消費者（cargo-mutants）で実走実証**: 弱いテストが残した4 survivor を、殺すテスト追加で 8/8 caught・exit 0
  に収束（2反復・~3m45s・除外ゼロ・floor 下げなし）。剪定が機械的シグナルから刈るように、拡充は機械的シグナルから
  成長する鏡。**釣り合いの原則**: 拡充は気前よくてよい（剪定が後で刈る）／追加は安全なので拡充は剪定より自律的でよい。
  **Broaden も実装**: `harness-coverage-expand`（TAKT scan→assess→propose）+ `coverage-scout` persona。変更クラスタの
  リスク形状を test-selection-roi の手順（persona に自己完結）で判定し、未カバーなら新技法を提案（提案のみ・人間の
  意図vs欠陥分類ゲート付き・自動追加しない）。**仮 rust 消費者で実走実証**: TabSet 状態機械（順序/状態・trivial テストのみ）を
  EXPAND-CANDIDATE と判定し**ステートフルPBT を提案**、無ロジックの mod 宣言は「pure noise」と明示スキップ、TLA+ は
  状態空間が小さく過剰と正しく却下（3反復・~3m45s・自動追加なし）。これで拡充は Deepen（機械的）+ Broaden（判断）の両輪。
- [x] **仕様ルールの文書化（1ルール=2反映）**: テストとモデル検査が**同じルール**を検証するなら、ルールを単一ソース化すれば
  両方が一緒に育つ。方法論 `docs/spec-rules.md`（ミニ言語 invariant/policy・ID・トレーサビリティ・意図vs欠陥ゲート）。
  実装 `harness-rule-reflect`（TAKT specify→reflect）+ `spec-author` persona: リスク/不変条件を `docs/spec/<area>.md` に
  ルール（ID付き）で書き、実装テスト+（順序/状態なら）Alloy assert に反映。提案/scaffold・自動 canonize しない。
  **仮 rust 消費者で実走実証（Broaden と統合）**: TabSet の active-tab 不変条件を R-1 として確定、ステートフルPBT
  （`tests/tabset_pbt.rs`・**コンパイル&pass 確認**）と Alloy assert（`spec/tabset.als`）に反映、R-1→test→assert を記録、
  隣接4挙動は DRAFT（意図/欠陥分類待ち）で canonize せず（2反復・~10m45s）。**1クラスタからルール+テスト+モデルが一緒に育つ**
  ことを実証＝「テストとモデルが乖離せず一緒に育つ」を成立させた。
- [x] **点A 統合デモ（実装を進めながら自律的に育つ）**: 仮 rust 消費者に2機能目（`Percent` 入力空間不変条件）を実装し
  Broaden→rule-reflect をもう一周。**ルール累積**（`docs/spec/` に tabset.md + percent.md）＋**技法の正しい差別化**——
  TabSet（順序/状態）=ステートフルPBT+Alloy／Percent（入力空間）=Plain PBT のみ・モデル却下。pending は `#[ignore]`。
  **デモが実バグを発見し還元**: `#[ignore]` でもコンパイルはされるため scaffold のコンパイルエラーでビルドが赤に＝skip だけでは
  不十分→「scaffold はコンパイルも通ること」を必須化（persona/workflow/spec-rules）。実装が進むとルール+テスト+モデルが
  一緒に育つことを多クラスタで実証＝二階ループの「増やす力」が実装フローと噛み合うことの確認。

**設計上の難所（mutation-config loop との違い・先に直視する）**: mutation-config loop は終了条件が機械判定
（score vs floor）で綺麗に TAKT に乗った。ROI 評価は「この層を消すか」が機械判定しにくく（3条件論理積・過大判定の罠）、
判断の比重が大きい。**分解すると、生存証明プローブ（mutation と同型・機械判定可）だけが自動ループ化でき、
剪定/統合の最終判定は persona 主導になる**。TAKT に「素直に乗るのはプローブ部分だけ」と見切ることが設計の出発点。

**この見切りを2つの具体ケースに展開した設計判断**（[`docs/probe-scope-and-gate-classification-decision.md`](./docs/probe-scope-and-gate-classification-decision.md)）:
(1) 生存証明プローブを correctness（正常入力→受理）に拡張する案は**却下**——correctness は挙動テスト層の責務で消費者環境も既に再現済み、
かつ誤爆は「沈黙する故障」ではない（即顕在化する）ためプローブの守備範囲外。(2) ROI 剪定に要る予防型/検出型の分類は**手貼りラベルではなく
導出**する（`REJECT_GATES` 在籍＋clean-accept テスト＝予防型／`collect-gate-history` が測る＝検出型）。メタゲートは「未分類」の可視化だけを
担い、**意味的誤分類の検出は称さない**（空虚テスト検出と同じ壁・是正は人間へ escalation）。背景原理は「**存在の強制は機械化できるが、
意味的正しさの強制はできず人間信頼に着地する**」——既存の `escalation-only` マーカー（`grep` のみで意味検証なし）と同じ設計姿勢。

---

## 完了の判定

- P1: kit の全 PR が CI を通り、ブランチ保護が効き、双方向モデルが文書化されている。
- P2: localmd が kit のアダプタ層を実際に実行し、sync-propose が差分ゼロを出す。
- P3: localmd 以外の最低1 PJ が kit を消費して CI を回している。
- P4: 計測スクリプトが各ゲートの発火実績と生存証明を出力し、評価スキルがそれを根拠に剪定/統合候補を提示できる。

各フェーズは独立した小さな PR で進め、CI 全 green を確認してからマージする。
