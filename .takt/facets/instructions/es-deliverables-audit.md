# 指示: ドメイン分析の成果物完全性を監査

対象の成果物ディレクトリ（タスクで指定。例「path/to/_domain-aggregate」）に対し、完成ゲートを回し、
**6タブの源泉が揃っているか**を判定せよ。**編集はしない**。

## 実行

```sh
ROOT="$(git rev-parse --show-toplevel)"   # gatecrate のスクリプト根
DIR=<対象の成果物ディレクトリ>

sh "$ROOT/core/scripts/check-es-deliverables.sh" "$DIR"   # 成果物の完全性（D1-D6）
for f in "$DIR"/*.es; do sh "$ROOT/core/scripts/es-lint-info.sh" "$f"; done  # 各.esの情報完全性(WARN)
```

## 判定

- `check-es-deliverables` が **ERROR=0**（AS-IS/TO-BE/コンテキストマップ/ビジネス分析の源泉/分析レポートが揃い、
  各 .es/.cmap が文法を通る）なら **COMPLETE**。
- 欠落（D2 TO-BE無し / D3 cmap無し / D4 biz=無し / D5 分析md無し / D6 文法違反）があれば **produce** へ。

## 報告

- check-es-deliverables の ERROR 一覧（D番号）＝**何が欠けているか**。これが produce の作業リスト。
- 各 .es の es-lint-info の WARN 件数（情報完全性の残りも併記）。
- 「TO-BEを省略している」「分析mdが無い」等の手抜きを具体的に名指しする。
