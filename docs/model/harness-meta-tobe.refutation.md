model-hash: 9961bbab7005f1a855d2d7e0279c24decdeb946d

# 反証記録 — harness-meta-tobe.es（TO-BE）

- 実施日: 2026-07-02〜03 / refuter: 独立エージェント（Explore・refute 指示）+ メンテナ確認
- AS-IS と共通のノードは harness-meta.refutation.md の指摘・反証と同一（同時に修正反映済み）。

## 指摘（反映済み）

- AS-IS 側の指摘 1〜6 を同時反映（pol_triage 再構成・evidence 修正・cmd_enforce 追加・decide 補正）。

## TO-BE 固有の検証

- 追加3ノード（evt_wf_failed / pol_alert / cmd_alert）は**意図的に evidence 無し**＝未実装ギャップ
  （es-coverage が missing と報告するのが正・5日間の沈黙 failure 実績が導入根拠）。
- ext_gha emits evt_wf_failed / cmd_alert handles ext_gha は es-lint 文法の許可トリプル内であることを確認。

## 反証を試みたが正しかった項目

- AS-IS 共通項目に同じ（evidence 行は AS-IS と同一値を維持）。

## 更新（2026-07-03・hash更新）

- 前回レビュー内容からの差分は test= 属性の追加（pol_triage/cmd_collect/agg_hist/cmd_verdict/cmd_enforce）と
  when=常時 修正のみ＝意味主張の変更なし。追加された test= は第1層 assertion として実行され green。
