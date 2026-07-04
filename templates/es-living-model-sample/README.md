# ES living-model サンプル（完成品イメージ）

gatecrate のドメイン分析が最終的に生成する**学習ビューア HTML の見本**です。ドメインは中立な例
（オンライン書店の注文・決済）で、内部固有名詞は含みません。実プロジェクトでの完成イメージとして参照してください。

## 見るもの

**[`sample-es.html`](./sample-es.html)** をブラウザで開く（ダブルクリック可）。右上の **「❓ このページの見方」**で読み方が出ます。
6つのタブ：

| タブ | 内容 |
|------|------|
| AS-IS | コードの流れ（手続き的な現状。各カードに実装評価＋「🔄 TO-BEでの変化」と理由）|
| TO-BE | あるべき設計（集約の状態機械・ポリシーの述語定義・イベントの型）|
| コンテキストマップ | BC（注文/決済/在庫）と関係（CS/ACL/Conformist）|
| 用語集 | モデルから射影したユビキタス言語（種別別の用語と定義）|
| ビジネス分析 | イベントの収益/価値/UX分類・オブザーバビリティ（取得/計算）・因果ループ（強化R/バランスB）・施策 |
| 分析レポート | リファクタリング＋ハーネス計画・永続化設計 |

> 図は Mermaid を CDN から読むため、**初回表示にはインターネット接続**が要ります（データは HTML に内蔵）。

## 構成（源泉＝これらから HTML を射影）

| ファイル | 役割 |
|---|---|
| `sample.es` / `sample-tobe.es` | AS-IS / TO-BE のイベントストーミングモデル |
| `sample.spec` | コマンドの入力→処理→出力 |
| `sample.cmap` | コンテキストマップ（BC・関係）|
| `sample.cld` | 因果ループ図（システム思考）|
| `sample-refactoring-roadmap.ja.md` / `sample-persistence-design.ja.md` | 設計検討（分析レポートタブ）|

## 再生成コマンド

```sh
sh ../../core/scripts/es-render-html.sh \
  sample.es sample-tobe.es sample.cmap sample.cld \
  sample-refactoring-roadmap.ja.md sample-persistence-design.ja.md \
  > sample-es.html
```

ゲート（`es-lint` / `es-lint-info` / `es-cmap-lint` / `check-jargon`）は ERROR=0。
`es-lint-info` は助言として R6（policy 入力の出所）の WARN を出すことがあります（ブロックしない＝育成ループのワークリスト）。

## これを自分のプロジェクトで作るには

`legacy-domain-extraction` スキルに「ハーネス駆動でドメイン分析して、最後に6タブHTMLまで作って」と依頼すると、
characterization→mutation でレガシーの挙動を固めながら、上記一式を生成します（詳細はリポジトリ README）。
