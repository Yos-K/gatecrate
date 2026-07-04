model-hash: 94f278540d0530b1f78a1756cef39bb68c19a343

# 反証記録 — harness-meta.es（AS-IS）

- 実施日: 2026-07-02〜03 / refuter: 独立エージェント（Explore・refute 指示）+ メンテナ確認
- 方式: 全ノードの evidence 行を実コードと突合・全エッジ列を制御フローと突合・取りこぼし探索

## 指摘（反映済み）

1. 【高】pol_triage の因果逆流 — escalation-only の除外は DEAD 後の分岐でなく **probe 前のマーカー分割**
   （probe-gate-liveness.sh:362。converge ループは人間所有ゲートを一度も見ない=exp3対策の本体）。
   decide/role/evidence を実装に合わせ再構成し、既定モードの DEAD→人間 の直行エッジを追加。
2. 【高】evt_hist の evidence 意味ズレ（反事実の罠の docstring 行を指していた）→ collect-gate-history.sh:123 へ。
3. 【中】agg_hist / cmd_collect / evt_verdict / cmd_probe / agg_gate / cmd_verdict / pol_verdict の evidence を
   docstring・関数ヘッダ行からロジック本体行へ（:69 / :203 / :57 / :247 / :79 / :47 / :56）。
4. 【中】メタゲート能力（check-gate-classified / check-gate-tests / probe --audit）の取りこぼし →
   cmd_enforce / evt_incomplete として追加。
5. 【低】cmd_repair の decide 不正確（停滞=max_steps 打切り・ABORT=弱体化提案時）→ 文言修正。
6. 【低】pol_verdict の decide に detection コスト不明(NA)分岐を補足。

## 反証を試みたが正しかった項目

- cmd_probe の exit 解釈（:247-252 と一致・setup error は ALIVE を騙らない）— 第1層 assertion でピン留め済み
- evt_alive=:249 / evt_dead=:248（出力行にピンポイント一致）
- agg_gate の invariant（レジストリ在籍→必ず prevention・マーカー偽装不能。判定順 :79→:83）— assertion でピン留め済み
- pol_verdict の型別ROI判定表（gate-roi-verdict.sh:56-70 と一致）— assertion でピン留め済み
- cmd_repair の権威（TAKT が probe --repairable-only の exit 0 を権威に反復）
- feeds 3本（alive/hist/verdict → dashboard が実際に消費）・rm_dash のコミット先・Conformist ext_gha

## 残置（別スライスで扱う）

- dashboard 自動PR再生成フロー・harness-history トレンド readmodel（本モデルは可読性優先で 23 ノード）

## 検出力の実測（第4層 probe・2026-07-03）

probe-semantic-liveness --inject retarget-evidence で cmd_probe↔agg_gate の evidence を入替えた変異モデル
（es-lint / check-es-evidence は通過＝文法非可視）を独立 refuter に流した結果、**両方の注入違反を名指しで
検出（入替とまで診断）→ --verify 判定 ALIVE**。本記録の refute 工程は計測能力を持つことを確認済み。

## 更新（2026-07-03・hash更新）

- 前回レビュー内容からの差分は test= 属性の追加（pol_triage/cmd_collect/agg_hist/cmd_verdict/cmd_enforce）と
  when=常時 修正のみ＝意味主張の変更なし。追加された test= は第1層 assertion として実行され green。
