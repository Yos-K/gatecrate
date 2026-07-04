# 指示: ESモデルのゲート実行と不足の読み取り

対象の `.es` モデル（タスクで指定。例「path/to/model.es (code root: path/to/code)」）に対し、3つのゲートを順に回し、
残る ERROR/WARN（＝埋めるべき不足）を読み取って報告せよ。**編集はしない**。

## 実行

```sh
ROOT="$(git rev-parse --show-toplevel)"   # gatecrate のスクリプト根
M=<対象.es>                                # タスクで指定された .es
CODE=<code root>                           # evidence 解決先（複数リポなら全部含む親）

sh "$ROOT/core/scripts/es-lint.sh"      "$M"      # 文法（ERRORは即ブロック）
sh "$ROOT/core/scripts/es-lint-info.sh" "$M"      # 情報完全性 R1-R7
EVIDENCE_CODE_ROOT="$CODE" sh "$ROOT/core/scripts/check-es-evidence.sh" "$M"
sh "$ROOT/core/scripts/check-jargon.sh" "$M"      # 用語の平易さ（記号は初出で日本語併記）
```

## 判定

- 4つとも **ERROR=0 かつ es-lint-info の WARN=0** なら情報完全＝**COMPLETE**。
- いずれかに ERROR（文法 / payload等の情報欠落 / evidenceドリフト / **説明なしの裸ジャーゴン**）、
  または es-lint-info に WARN（R4 制約なし / R5 フラグ・コード臭い / R6 出所未定義 / R7 述語未定義）があれば **fill** へ。

## 報告

- 各ゲートの ERROR/WARN 件数。
- 埋めるべき不足を、ノードID・種別（R番号）・何が足りないかで列挙（fill ステップの作業リストになる）。
- 数字の出所（`evidence=` が指す file:line）も併記し、fill が読むべき箇所を示す。
