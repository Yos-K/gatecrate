# gatecrate へのコントリビュート

English: [CONTRIBUTING.md](./CONTRIBUTING.md)（正文書）。本書はその日本語補足訳。

## バージョニング（SemVer）

本リポジトリはリリースタグで管理する **Semantic Versioning** に従う。sync-manifest 機構が
タグ比較で更新を検知するため、バージョニングは同期パイプラインの中核。

| バージョン | 変更種別 | 例 |
|---|---|---|
| **PATCH**（x.y.**Z**） | バグ修正・軽微なスクリプト修正（挙動変更なし） | shell 構文エラー修正・コメント修正 |
| **MINOR**（x.**Y**.0） | ハーネス追加・アダプタ追加 | `adapters/python/` 追加・新スクリプト追加 |
| **MAJOR**（**X**.0.0） | ラチェット閾値の引き下げ・破壊的インタフェース変更 | `FITNESS_MAX_LINES` の既定を 300→200 に下げる |

### 重要: MAJOR 変更

**ラチェット閾値の引き下げ**（品質ゲートの締め付け）は常に **MAJOR** リリース。これにより
同期 PR が無断で閾値を下げ、消費側 CI を予期せず壊すことを防ぐ。

## 消費側からの還元（consumer → kit）

ハーネス改善はたいてい消費側で先に生まれ（実際に動くのは消費側だから）、ここへ還元される。還元時:

- **消費側の形でなく、kit の汎用形へ移植する。** パラメータ化（`$BUILDCONFIG_PACKAGE`・
  `$APP_THEMES`・env var デフォルト・`#!/bin/sh`・消費可能スクリプトが使う git 解決の repo root）を保つ。
  消費側固有のドリフト（ハードコード パッケージID・ホスト固有 shebang/パス・ハードコード値リスト）は
  **還元しない** — 移植性が退行する。消費モデルは [docs/structure.ja.md](./docs/structure.ja.md) 参照。
- **kit が既に持つものは飛ばす。** 消費側は kit が汎用化済みのものを再ハードコードして乖離しがちで、
  それは還元すべき改善ではない。
- バージョンを bump し `CHANGELOG.md` エントリを追加（上記バージョニング参照）。

逆方向（kit → 消費側）は `sync-propose.yml` で自動化される。

## PR ルール

- **ハーネス PR はアプリ挙動を変えてはならない**
  - `src/**` をホワイトリストに含めることは禁止（マニフェストのスキーマ制約）
  - スクリプト変更が消費側の build/test/release パイプラインに影響しないことを PR 前に確認

### ホワイトリスト規則

**`src/**`・`harness.config.sh`（消費側のシェル設定・YAML ではない）・`profiles/` は絶対にホワイトリストへ含めない。** 含めると
消費側の固有設定を上書きする恐れがある。ホワイトリストは `core/` と `adapters/` 配下のみ。
（manifest のスキーマレベル検証は未実装。列挙パスの実在は CI の「sync-manifest integrity」ステップが検証する。）

- **シークレット・keystore・サービスアカウント鍵をコミットしない**
  - `check-no-committed-secrets.sh` を CI で自己適用
  - PR 前にローカルで `sh core/scripts/check-no-committed-secrets.sh` を実行
- **全スクリプトの shebang は `#!/bin/sh`**
  - Termux（Android）・macOS・Linux で `sh script.sh` として動くこと
  - `#!/bin/bash` や `#!/usr/bin/env zsh` は禁止

## ファイルサイズ制約

- 1ファイル最大 300 行（`check-file-line-limit.sh` を CI で自己適用）
- 超過時はカテゴリごとに分割

## ブランチ戦略

- `main`: リリースブランチ — 直 push 禁止（CI 必須・会話解決必須で保護）
- feature ブランチ → PR → CI 全 green → main へマージ → リリースタグ

## 日英ドキュメント同期

README.md が正文書（英語）、README.ja.md がその日本語補足。README.md 更新時は README.ja.md を
同時に更新して同期を保つ。同様に CONTRIBUTING.md / docs 配下も EN を正、`*.ja.md` を訳とする。
