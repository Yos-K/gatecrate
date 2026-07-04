---
name: modularity-review
description: |
  Balanced Coupling（strength×distance×volatility）の判断層を担う。measure-modularity.sh が
  機械計測できない Integration Strength の4段階（contract<model<functional<intrusive）を
  コードの証拠つきで分類し modularity-strength.tsv を保守、RED エッジの是正案（弱める/近づける/
  台帳へ）を提示し、check-modularity-ratchet.sh のベースライン運用を支援する。
  「モジュール性レビュー」「結合度の分類」「modularity review」「バランス違反を直したい」
  「strength を分類して」で起動。
  Do NOT use for: distance/volatility の計測やゲート実行（measure-modularity.sh /
  check-modularity-ratchet.sh が決定論で行う）。ベースラインへの自動追記（負債の受入は
  人間がレビューで承認する）。複雑度の計測（measure-complexity.sh を使う）。
argument-hint: "[target-project-path]"
allowed-tools: Read, Grep, Glob, Bash, Edit, Write
metadata:
  author: Yos-K
---

# modularity-review — Balanced Coupling の判断層

## 分業（このスキルの立ち位置）

決定論は機械・判断はエージェント・承認は人間。

| 層 | 担当 | 成果物 |
|----|------|--------|
| 計測（機械） | `measure-modularity.sh`: distance=パッケージ木距離、volatility=git履歴、バランス式判定 | `build/quality/modularity-all.tsv` / `modularity-red.tsv` |
| **判断（このスキル）** | strength の意味論的分類・RED の是正案・分類の再検証 | `modularity-strength.tsv`（証拠つき） |
| 強制（機械） | `check-modularity-ratchet.sh`: ベースライン外の新規 RED を reject | CI exit code |
| 承認（人間） | 負債の受入（`modularity-baseline.tsv` への追記）・是正方針の裁可 | PR レビュー |

バランス式は `BALANCE = (STRENGTH XOR DISTANCE) OR NOT VOLATILITY`。
強い結合は近くに置き、遠い結合は弱くする。このバランスが破れていても、依存先が変動しないなら実害はない。

## 手順

### 1. 計測を回し、作業キューを得る

```sh
sh scripts/measure-modularity.sh   # 消費側。kit 自身なら core/scripts/
```

レポートの「unclassified strength」一覧が分類の作業キュー、「RED」一覧が是正の作業キュー。
load（strength×distance×volatility）の大きい順に処理する。

### 2. Integration Strength を証拠つきで分類する

エッジ（src_pkg → dst_pkg）ごとに **src 側のコードを実際に読み**、共有されている知識の量で判定する:

| level | 判定基準（何を知っているか） | 典型的な証拠 |
|-------|------------------------------|--------------|
| `contract` | 公開API・イベント契約だけ | インターフェース/DTO のみ import、実装型に触れない |
| `model` | 相手のドメインモデル（型・概念） | エンティティ/値オブジェクトの型を共有 |
| `functional` | 相手のビジネスルールの実装知識 | ルールの複製・呼出順序への依存・相手の仕様変更で必ず壊れる |
| `intrusive` | 相手の内部実装（実装都合・内部状態） | 内部パッケージへの import、リフレクション、内部状態の直接操作 |

判定したら `modularity-strength.tsv` に1行追記する（形式は `templates/modularity-strength.tsv.example`）:

```
src_pkg<TAB>dst_pkg<TAB>level<TAB>根拠 (file:line)
```

**規律（憶測記載の全面禁止）**:
- コードを読まずに分類しない。証拠（file:line）の無い行を書かない。
- 迷ったら**強い側に倒す**（弱く誤分類すると RED を取り逃がし、ゲートが黙る。強く誤分類しても
  advisory レポートと人間レビューで修正される——予防ゲートの偽陰性の方が高くつく）。
- import 数の多寡は strength ではない（幅であって深さではない）。知識の質で判定する。

### 3. RED エッジの是正案を出す

RED（強い×遠い×変動）ごとに、バランス式のどの項を動かすかで選択肢を整理して提示する:

1. **strength を下げる**（→ contract）: 内部知識の共有をやめ、公開API/イベント経由にする。
   ACL/Gateway パターン（G3: 外部レイヤ抽象化と同じ手筋）。
2. **distance を下げる**: 一緒に変わるものを同じモジュール境界へ移す（凝集の回復）。
   移動先の候補は、その依存先との間に YELLOW（弱い×近い×変動）が出ているモジュール——
   すでに近くで同じ変動源と付き合っている場所が、自然な引っ越し先になりやすい。
3. **分類の再検証**: 実は contract 結合なら手順2で証拠つきで分類（RED が消える）。
4. **意識的な負債**: 今は直さないと人間が判断したら `modularity-baseline.tsv` へ——
   **ただし追記はこのスキルが行わず、根拠を添えて人間に提案する**（承認は人間の層）。

### 4. ベースラインの運用を支援する

- brownfield 導入時: `sh scripts/check-modularity-ratchet.sh --emit-baseline` を提案し、
  凍結された負債一覧に「なぜ許容するか」の短い根拠を付けて PR 説明に載せる。
- ゲートが NOTE で「debt repaid」を報告したら、該当行の削除（ラチェット締め）を提案する。
- 分類を変更した場合は計測を回し直し、RED 集合の変化（増えたか減ったか）を必ず報告する。

## 完了条件（機械判定）

- `measure-modularity.sh` のレポートで unclassified が 0、または残りが低 load で明示的に後回しと記録済み
- `check-modularity-ratchet.sh` が exit 0（新規 RED なし）
- `modularity-strength.tsv` の全行に evidence が付いている

## 限界（正直に）

- 分類はコードが含意する事実のみ。チーム境界・実行時依存（vladikk の distance が含む社会技術的
  要素）は見えない——必要なら人間が distance 閾値/分類を上書きする。
- 分類の正しさ自体を機械は検証できない（ratchet は分類を信じて判定する）。だから evidence 必須・
  強い側に倒す・人間レビューの三重で誤分類を抑える。
