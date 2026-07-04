# gatecrate 二階ループ（ハーネス自己評価）TO-BE — AS-IS の核は維持し、「沈黙する劣化」への通知フローを追加
# 実装済みノードは evidence を持つ（es-coverage が implemented と判定）。evidence の無いノードが未実装ギャップ。
N act_maint  actor    メンテナ | role=ハーネスを保守する人間。剪定提案と失敗通知の最終決裁者。
N ext_gha    external GitHub Actions | role=CI実行・スケジュール・PR/Issue 作成を担う外部実行基盤。定期実行の失敗という事実の発生源。
N cmd_probe  command  合成違反を注入して生存を証明する | in=ゲート;注入kind | out=ALIVE|DEAD|setup-error | decide="ゲートが exit 1=棄却=ALIVE。exit 0=受理=DEAD。他は setup error（偽の生存証明を作らない）" | evidence=core/scripts/probe-gate-liveness.sh:247 | test=docs/model/assertions/probe-exit-mapping.sh | role=発火0の予防ゲートの価値を証明する survival proof。
N agg_gate   aggregate ゲート | fields=ゲート名:一意キー(スクリプトbasename); 型:分類結果; escalation-onlyマーカー:人間所有の宣言(ゲート自身のファイル内コメント) | states=untyped|prevention|detection|advisory|not-a-gate | transitions=分類する:untyped->prevention|detection|advisory | invariant=reject型レジストリ在籍なら必ず prevention（レジストリが単一ソース） | evidence=core/scripts/classify-gate-type.sh:79 | test=docs/model/assertions/classify-registry-priority.sh | role=評価対象の1ゲート。型は構造から導出。
N evt_alive  event    生存が証明された | fields=ゲート名:一意キー; 注入kind:合成違反の種類 | evidence=core/scripts/probe-gate-liveness.sh:249 | role=ゲートが合成違反を棄却した事実。
N evt_dead   event    生存証明に失敗した | fields=ゲート名:一意キー; 注入kind:合成違反の種類; 実行モード:全数生存証明|収束ループ(repairable-only) | evidence=core/scripts/probe-gate-liveness.sh:248 | role=棄却経路が壊れている事実。修理を駆動する。
N pol_triage policy   修理先を判定する | in=実行モード;escalation-onlyマーカー | out=収束ループで修理|人間が対応  | decide="収束ループは escalation-only を probe の前に構造的に除外して回る＝ループ内の DEAD はすべて修理可。人間所有の DEAD は既定モードでのみ現れ人間へ届く（exp3 を構造で防ぐ）" | evidence=core/scripts/probe-gate-liveness.sh:362 | test=docs/model/assertions/triage-pre-probe.sh | role=修理の所有者を決める事前トリアージ（probe 前のマーカー分割）。
N cmd_repair command  棄却経路を修理する | in=ゲート名;プローブ出力 | out=修理済|ABORT(人間差し戻し) | decide="TAKT収束ループが probe --repairable-only の exit 0 を権威に反復（max_steps 打切り・弱体化提案時は ABORT）" | evidence=.claude/skills/gatecrate-evaluate/takt/harness-liveness-converge.yaml | note=意図的に test= 未付与＝検証に TAKT 実行が要る（唯一の未ピン主張）。 | role=エージェントによる修理。
N evt_fixed  event    棄却経路が修理された | fields=ゲート名:一意キー | evidence=.claude/skills/gatecrate-evaluate/takt/harness-liveness-converge.yaml | role=修理完了の事実。
N cmd_collect command 発火履歴を集計する | in=CI実行履歴;期間 | out=ゲート別の発火数とCI秒 | decide="fetch(非決定論)と aggregate(純関数)を分離。取得失敗は空履歴と偽らない" | evidence=core/scripts/collect-gate-history.sh:203 | test=docs/model/assertions/collect-aggregate-pure.sh | role=ROI評価の入力を作る計測。
N agg_hist   aggregate 発火履歴 | fields=ゲート名:一意キー; 発火数:回; CI秒:コスト | invariant=集計は取得済み履歴の純関数（同一入力なら同一出力） | evidence=core/scripts/collect-gate-history.sh:69 | test=docs/model/assertions/collect-aggregate-pure.sh | role=ROI 判定の唯一の機械的入力。
N evt_hist   event    発火履歴が集計された | fields=ゲート名:一意キー; 発火数:回; CI秒:コスト | evidence=core/scripts/collect-gate-history.sh:123 | role=ROI 判定を駆動できる状態になった事実。
N pol_verdict policy  型別にROIを判定する | in=型;発火数;CI秒 | out=keep|removal-candidate|人間判断 | decide="prevention は発火0でも keep。detection は安価なら keep、コスト不明(NA)は keep 固定、高コスト×発火0のみ removal-candidate。advisory は人間判断" | evidence=core/scripts/gate-roi-verdict.sh:56 | test=docs/model/assertions/verdict-type-table.sh | role=発火0の意味が型で反転する判定表。
N cmd_verdict command 剪定候補を提案する | in=ROI判定;ゲート | out=提案(PR/レポート) | decide="提案のみ。安全制約はメトリクスで自動撤去しない" | evidence=core/scripts/gate-roi-verdict.sh:47 | test=docs/model/assertions/verdict-proposal-only.sh | role=機械判定を人間への提案に変換する。
N evt_verdict event   剪定候補が提案された | fields=ゲート名:一意キー; 判定:keep|removal-candidate|人間判断 | evidence=core/scripts/gate-roi-verdict.sh:57 | role=人間の承認を待つ提案が出た事実。
N rm_dash    readmodel ハーネスダッシュボード | fields=型:分類; 生存:ALIVE|DEAD|未プローブ; ROI判定:提案; 鮮度:最終更新 | evidence=core/scripts/render-harness-dashboard.sh:49 | role=型・生存・ROIの照会ビュー。TO-BE では鮮度（自動更新が生きているか）も一目で分かる。
N evt_wf_failed event 定期実行が失敗した | fields=workflow名:識別; 連続失敗数:回 | role=ダッシュボード更新などの定期 workflow が失敗した事実。5日間の沈黙放置（実績）を二度と起こさないための起点。
N pol_alert  policy   放置を検知して起票するか判定する | in=workflow名;連続失敗数 | out=Issue起票|静観 | decide="同一 workflow の失敗が閾値回数を超えて続いたら起票。単発の flaky は静観" | role=沈黙する劣化を人間の注意でなく機械の通知に変える関門。
N cmd_alert  command  失敗Issueを起票する | in=workflow名;失敗ログ要約 | out=Issue | decide="既存の未クローズ同種 Issue があれば重複起票しない（冪等）" | role=GitHub Issue として失敗を可視化し、メンテナの作業キューに載せる。
N hs_ci      hotspot  自動リフレッシュPRのCIが起動しない | role=GITHUB_TOKEN の再帰防止により自動PRの checks が起動しない。方式（PAT/App/免除）の裁定待ち。 | discuss=決めること: PAT/App トークン導入か checks の条件免除か。 / なぜ重要: 自動経路の「自動」が完結しない。 / 決裁者: メンテナ。
N cmd_enforce command 台帳の完備を強制する（メタゲート） | in=ゲート名;型;挙動テストの有無;probe登録 | out=pass|reject | decide="untyped・テスト無し reject 型・probe 未登録を PR ごとに reject" | evidence=core/scripts/check-gate-classified.sh:53, core/scripts/check-gate-tests.sh:53, core/scripts/probe-gate-liveness.sh:293 | test=docs/model/assertions/enforce-completeness.sh | role=台帳完備を出荷前に守るメタゲート。
N evt_incomplete errorevent 不完備なゲートの出荷が差し止められた | fields=ゲート名:一意キー; 欠落:untyped|テスト無し|probe未登録 | evidence=core/scripts/check-gate-classified.sh:53 | role=完備を欠くゲートが PR で棄却された事実（終端）。
# === エッジ ===
E act_maint  issues   cmd_probe
E cmd_probe  handles  agg_gate
E agg_gate   emits    evt_alive
E agg_gate   emits    evt_dead
E evt_dead   triggers pol_triage
E pol_triage issues   cmd_repair | when=収束ループで修理（escalation-onlyマーカー無し）
E cmd_repair handles  agg_gate
E agg_gate   emits    evt_fixed
E act_maint  issues   cmd_collect
E cmd_collect handles agg_hist
E agg_hist   emits    evt_hist
E evt_hist   triggers pol_verdict
E pol_verdict issues  cmd_verdict | when=常時（keep|removal-candidate|人間判断 の判定結果を提案に添える）
E cmd_verdict handles agg_gate
E agg_gate   emits    evt_verdict
E evt_verdict triggers act_maint
E ext_gha    emits    evt_wf_failed
E evt_wf_failed triggers pol_alert
E pol_alert  issues   cmd_alert | when=Issue起票（連続失敗が閾値超え）
E cmd_alert  handles  ext_gha
E evt_alive  feeds    rm_dash
E evt_hist   feeds    rm_dash
E evt_verdict feeds   rm_dash
E hs_ci      marks    rm_dash
E act_maint  issues   cmd_enforce
E cmd_enforce handles agg_gate
E agg_gate   emits    evt_incomplete
E evt_dead   triggers act_maint
