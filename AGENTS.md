# AGENTS.md — gatecrate を変更する AI エージェント向け運用規則

このファイルは、gatecrate に変更を加えるエージェント（Claude Code / Codex 等）が**最初に読む**
運用規則。背景と詳細は [ROADMAP.md](./ROADMAP.md)（方針の正典）と [CONTRIBUTING.md](./CONTRIBUTING.md)
（バージョニング・upstream フロー）を参照する。

## このリポは何か（1行）

複数プロジェクトで再利用する**移植可能なハーネス（CI/リリースゲート）の供給元**。3層構造:
generic core（スタック非依存）/ stack adapters（android-jvm, python, go, ... 8スタック）/ project templates。

## 最重要の不変条件（なぜを最初に）

**kit の価値は「実消費者の数」に比例する。** 消費者が2未満なら、kit は消費側に直接スクリプトを
置くより二重管理・ドリフトの純オーバーヘッドになる。**だから、機能やアダプタを足す前に、まず
「消費ループが実消費者で実際に回る」ことを実証する。** 未実証の汎用性の上に汎用性を積むと砂上の
楼閣になる（ROADMAP 参照）。

→ 実務指針: **幅（新スタック・新機能）より深さ（実消費者での実証）を優先する。** 新機能を入れたら、
合成スモークで終わらせず**実消費者の CI 緑まで**を完了の定義とする。

## 双方向貢献ループ（consumer ⇄ kit）

改善は消費側で生まれ、kit へ還元し、他消費者へ伝播する。実際の1周（issue #25 で実走した形）:

1. **consumer → kit**: 消費者で gap を発見 → kit に issue 起票（traceability の起点）→ kit で実装 PR。
2. **kit → consumer**: 消費者が新スクリプトを採用する PR → **実消費者の CI 緑で実証**。
3. 採用過程で判明した移植性ギャップ（例: マルチモジュール、Kotlin `internal` 可視性）は kit に還元。
4. `sync-check` で消費者の採用済みファイルが kit master と **ドリフト0** であることを確認。

### ペアリング規則（逆向きドリフト防止・ROADMAP P2）

**`core/` または `adapters/` 配下のスクリプトを変更する PR は、同週に「逆向きの対」を必ず作る。**

- kit を変更したら → 少なくとも1つの実消費者で採用 PR を出し CI 緑を確認する（kit→consumer）。
- 消費者でアダプタ相当を改善したら → 同週に kit 還元 PR を出す（consumer→kit）。
- 目的: 「kit だけ変わって誰も消費していない」「消費者だけ直って kit に戻らない」の片側ドリフトを防ぐ。

## 消費者へのスクリプト配置（vendoring）規則

- **git-first でルート解決するスクリプトは「生のまま」vendoring する**（install.sh の sed 変換を
  かけない）。これらは `git rev-parse --show-toplevel` を主、相対 `cd` をフォールバックにするため、
  消費者リポでも変換なしで動く。**変換すると kit master と byte 不一致になり `sync-check` が偽の
  ドリフトを報告する。** diff-zero を保つには生コピーが正。
- install.sh の `/../../..`→`/..` 変換は、git 解決を持たない**旧スクリプト専用**の延命措置。

## 新しいスクリプトを追加したら

1. `sync-manifests/<adapter>.yaml` の `adapter_scripts`（または `core_scripts`）に**必ず追記**する
   （CI の sync-manifest 整合性チェックと、消費者への同期の前提）。
2. 該当アダプタの `README.md` のスクリプト表を更新する。
3. install.sh は `adapters/<stack>/scripts/*.sh` を glob 配布するため、通常 install.sh 変更は不要。

### スクリプト間の依存（co-dependency）に注意

スクリプトが**別のスクリプトを source する**場合、それは co-dependency になる。`consumed_scripts` は
フラットな opt-in リストで依存を自動解決しないため、**依存先も明示的に consumed に含める**必要がある。

- 例: `run-unit-tests.sh` / `run-mutation-tests.sh` は v0.8.0 から `android-kotlin-compile.sh` を source する
  （純 Java でもコンパイルは `ak_compile` 経由）。前者だけを sync した既存消費者は欠落で失敗した（localmd #194）。
- **だから**: source 依存を増やす変更では (a) 依存先スクリプトの欠落を**明示エラーで落とす**ガードを入れ、
  (b) アダプタ README と本ファイルに co-dependency を記し、(c) 消費者へは依存先も同時に採用させる。
- sync 機構は co-dependency を扱う（issue #34）: `sync-check.sh` は採用済みスクリプトが source する
  未採用 kit スクリプトを `[DEP]` として検出し、`sync-propose.yml` は consumed の依存を**推移的に取り込む**
  （`$ROOT/scripts/<x>` の静的抽出。依存宣言がコード自体に在るのでドリフトしない）。それでも source 依存を
  増やす変更では (a) 欠落時の明示エラーガード、(b) README/本ファイルへの記載、を併せて行うこと。

## PR を出す前に必ずローカルで通すゲート（CI パリティ）

```sh
# 構文
find . -name '*.sh' -not -path './.git/*' -exec sh -n {} \;
# 実バグ（CI は -S error が必須ゲート）
find . -name '*.sh' -not -path './.git/*' -print0 | xargs -0 shellcheck -S error
# sync-manifest が指すパスが全て実在するか
# （CI の "sync-manifest integrity" ジョブ相当）
# 300行ルール（CHANGELOG は scripts/file-line-exceptions.txt で例外登録済み）
sh core/scripts/check-file-line-limit.sh
```

## 禁止事項（CONTRIBUTING より要点）

- `managed_files`（sync-manifest）に `src/**` / `templates/` / `profiles/` / `harness-config.*` を
  含めない（消費者の固有設定を上書きする危険）。ホワイトリスト方式が保証の核。
- シークレット・keystore・サービスアカウント鍵をコミットしない（`check-no-committed-secrets.sh` を自己適用）。
- **所属企業名・内部固有名詞・内部識別子を、コミットログ／コミット作者メタデータ／ドキュメント／ソース／PR に残さない**
  （下記「機密情報・固有名詞の禁止」参照）。公開リポは push 後の完全消去が困難。
- シバンは `#!/bin/sh` のみ（Termux/macOS/Linux で `sh script.sh` 実行可能であること）。`bash`/`zsh` 禁止。
- 1ファイル300行以内。超える場合はカテゴリ分割、または本質的に分割不能なら例外ファイルに理由付きで登録。
- 品質ゲートの**閾値引き下げ（ratchet を緩める）は MAJOR リリース**。sync PR が黙って閾値を下げないため。

## 機密情報・固有名詞の禁止（公開プロジェクト）

**gatecrate は公開・再配布される kit である。** 所属企業名・内部プロジェクト/システム名・内部の
クラス/モジュール/パッケージ名・内部ホスト名・業務用メールアドレスといった**固有名詞や内部識別子を、
以下のいずれにも残さない**:

- コミットメッセージ、**コミット作者メタデータ（author/committer の name・email）**
- ドキュメント（`docs/`・`CHANGELOG.md`・`docs/handover/*` を含む）
- ソースコード・コメント・テストデータ
- PR のタイトル・本文、Issue

**なぜ**: 公開リポに push された時点で外部へ露出し、履歴を書き換えても旧コミットは SHA や PR refs
経由で残存する（GitHub の GC は非制御で、完全消去には Support 依頼が要る）。一度公開された分は回収できない。

**だから**:

- 非公開コードに対して検証・実証する場合も、成果物には**汎用表現**で書く
  （例: 具体的な内部モジュール名・実クラス名 → 「実運用の Java プロジェクト」「あるクラスタ」）。
  固有名詞が無くても、設計判断・実証の事実という価値は十分に伝わる。
- 公開リポ（github.com）のコミット作者 email は**公開用 ID**（GitHub の `…@users.noreply.github.com`）にする。
  業務用(企業内Git)のemail をグローバル既定にしている場合は、**公開リポごとに `git config user.email` で上書き**する。
- 迷ったら**書かない／伏せる**側に倒す。

## ドキュメント更新義務

- コード/設計/構成を変更したら `docs/handover/CURRENT.md` をインクリメンタルに更新する。
- 機能追加・バグ修正は `CHANGELOG.md` の `[Unreleased]` に追記する（リリース時にタグ節へ移す）。
