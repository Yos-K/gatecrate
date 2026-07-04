# gatecrate 二階ループ（ハーネス自己評価）AS-IS — consumer #0 ドッグフード
# 源泉ルール: evidence は実コード行（check-es-evidence が実在を機械検証）。becomes= は TO-BE への対応。
N act_maint  actor    メンテナ | role=ハーネスを保守する人間。生存証明・ROI評価を起動し、剪定提案を承認する最終決裁者。 | becomes=act_maint | 変わらず。なぜ: 剪定の承認は人間、という分業は TO-BE でも不変だから。
N cmd_probe  command  合成違反を注入して生存を証明する | in=ゲート;注入kind | out=ALIVE|DEAD|setup-error | decide="ゲートが exit 1=違反を棄却=ALIVE。exit 0=受理=DEAD。他は setup error（ALIVE と報告しない＝偽の生存証明を作らない）" | evidence=core/scripts/probe-gate-liveness.sh:247 | test=docs/model/assertions/probe-exit-mapping.sh | role=使い捨てgitリポにゲートを複製し、kind別の合成違反を注入して棄却を確認する。発火0の予防ゲートは壊れていても見えない、への回答。 | becomes=cmd_probe | 変わらず。なぜ: 生存証明の機構自体は完成しているから。
N agg_gate   aggregate ゲート | fields=ゲート名:一意キー(スクリプトbasename); 型:分類結果; escalation-onlyマーカー:人間所有の宣言(ゲート自身のファイル内コメント) | states=untyped|prevention|detection|advisory|not-a-gate | transitions=分類する:untyped->prevention|detection|advisory | invariant=reject型レジストリ在籍なら必ず prevention（レジストリが単一ソース・マーカーでの偽装は効かない） | evidence=core/scripts/classify-gate-type.sh:79 | test=docs/model/assertions/classify-registry-priority.sh | role=評価対象の1ゲート。型は手貼りでなく構造（レジストリ在籍→prevention）から導出される。 | becomes=agg_gate | 変わらず。なぜ: 型の構造導出は確立済みだから。
N evt_alive  event    生存が証明された | fields=ゲート名:一意キー; 注入kind:合成違反の種類 | evidence=core/scripts/probe-gate-liveness.sh:249 | role=ゲートが合成違反を棄却した事実。予防ゲートの価値証明（発火履歴では証明できない）。 | becomes=evt_alive | 変わらず。なぜ: 生存証明の事実は TO-BE でも同じだから。
N evt_dead   event    生存証明に失敗した | fields=ゲート名:一意キー; 注入kind:合成違反の種類; 実行モード:全数生存証明|収束ループ(repairable-only) | evidence=core/scripts/probe-gate-liveness.sh:248 | role=ゲートが合成違反を受理した事実＝棄却経路が壊れている。修理を駆動する。 | becomes=evt_dead | 変わらず。なぜ: DEAD の検出と修理駆動は TO-BE でも核だから。
N pol_triage policy   修理先を判定する | in=実行モード;escalation-onlyマーカー | out=収束ループで修理|人間が対応  | decide="収束ループ(repairable-only)は escalation-only を probe の前にマーカーで構造的に除外して回る＝ループが観測する DEAD はすべて修理可。人間所有ゲートの DEAD は既定モード(全数生存証明)でのみ現れ、人間へ直接届く——ループ圧での書き換え(exp3)を信頼でなく構造で防ぐ" | evidence=core/scripts/probe-gate-liveness.sh:362 | test=docs/model/assertions/triage-pre-probe.sh | role=修理の所有者を決める事前トリアージ。DEAD 後の分岐でなく probe 前のマーカー分割が本体。 | becomes=pol_triage | 変わらず。なぜ: exp3 対策の構造的トリアージは維持するから。
N cmd_repair command  棄却経路を修理する | in=ゲート名;プローブ出力 | out=修理済|ABORT(人間差し戻し) | decide="TAKT収束ループが probe --repairable-only の exit 0 を権威に反復（上限 max_steps で打切り）。ゲートの弱体化・削除を提案した時は ABORT して人間へ（無理に緑にしない）" | evidence=.claude/skills/gatecrate-evaluate/takt/harness-liveness-converge.yaml | note=意図的に test= 未付与＝検証に TAKT 実行が要り安価なマイクロ検証に降ろせない（唯一の未ピン主張）。 | role=エージェントによる修理。終了条件は機械判定（ゲートのexit code）なので自走できる。 | becomes=cmd_repair | 変わらず。なぜ: 修理ループは実証済みだから。
N evt_fixed  event    棄却経路が修理された | fields=ゲート名:一意キー | evidence=.claude/skills/gatecrate-evaluate/takt/harness-liveness-converge.yaml | role=DEAD だったゲートが再び違反を棄却できるようになった事実。 | becomes=evt_fixed | 変わらず。なぜ: 修理完了の事実は同じだから。
N cmd_collect command 発火履歴を集計する | in=CI実行履歴;期間 | out=ゲート別の発火数とCI秒 | decide="fetch(gh・非決定論)と aggregate(純POSIX awk・テスト可)を分離。取得失敗は空履歴と偽らず伝播" | evidence=core/scripts/collect-gate-history.sh:203 | test=docs/model/assertions/collect-aggregate-pure.sh | role=ROI評価の入力を作る計測。 | becomes=cmd_collect | 変わらず。なぜ: 計測層は安定しているから。
N agg_hist   aggregate 発火履歴 | fields=ゲート名:一意キー; 発火数:回; CI秒:コスト | invariant=集計は取得済み履歴の純関数（同一入力なら同一出力＝テスト可能） | evidence=core/scripts/collect-gate-history.sh:69 | test=docs/model/assertions/collect-aggregate-pure.sh | role=期間内のゲート別発火実績。ROI 判定の唯一の機械的入力。 | becomes=agg_hist | 変わらず。なぜ: 履歴の性質は変わらないから。
N evt_hist   event    発火履歴が集計された | fields=ゲート名:一意キー; 発火数:回; CI秒:コスト | evidence=core/scripts/collect-gate-history.sh:123 | role=ROI 判定を駆動できる状態になった事実。 | becomes=evt_hist | 変わらず。なぜ: 同上。
N pol_verdict policy  型別にROIを判定する | in=型;発火数;CI秒 | out=keep|removal-candidate|人間判断 | decide="prevention は発火0でも keep（反事実の罠回避・価値は生存証明で立つ）。detection は安価なら keep、コスト不明(NA)は keep 固定、高コスト×発火0のみ removal-candidate。advisory は機械判定不能＝人間判断" | evidence=core/scripts/gate-roi-verdict.sh:56 | test=docs/model/assertions/verdict-type-table.sh | role=発火0の意味が型で反転する、を機械化した判定表。 | becomes=pol_verdict | 変わらず。なぜ: 判定表は正典（harness-roi-evaluation.md）に固定済みだから。
N cmd_verdict command 剪定候補を提案する | in=ROI判定;ゲート | out=提案(PR/レポート) | decide="提案のみ。安全制約（secrets等）はメトリクスで自動撤去しない——削除は常に人間が PR で行う" | evidence=core/scripts/gate-roi-verdict.sh:47 | test=docs/model/assertions/verdict-proposal-only.sh | role=機械判定を人間への提案に変換する。自動剪定はしない。 | becomes=cmd_verdict | 変わらず。なぜ: 「提案のみ・実行は人間」は安全原則だから。
N evt_verdict event   剪定候補が提案された | fields=ゲート名:一意キー; 判定:keep|removal-candidate|人間判断 | evidence=core/scripts/gate-roi-verdict.sh:57 | role=人間の承認を待つ提案が出た事実。承認・削除はメンテナが行う。 | becomes=evt_verdict | 変わらず。なぜ: 同上。
N rm_dash    readmodel ハーネスダッシュボード | fields=型:分類; 生存:ALIVE|DEAD|未プローブ; ROI判定:提案 | evidence=core/scripts/render-harness-dashboard.sh:49 | role=型・生存・ROIの照会ビュー（docs/harness-status.md にコミットされリポから見える）。分類・照会はイベントでなくリードモデル、の規律(R10)の適用先。 | becomes=rm_dash | 変わらず。なぜ: ビューは維持し、鮮度の監視だけ TO-BE で足すから。
N hs_ci      hotspot  自動リフレッシュPRのCIが起動しない | role=GITHUB_TOKEN が push したブランチは GitHub の再帰防止で workflow を起動できず、自動PRの required checks が永遠に pending（毎回、空コミットで手動起動が要る）。 | discuss=決めること: fine-grained PAT / GitHub App トークンを使うか、required checks を条件免除するか。 / なぜ重要: 自動経路の「自動」が完結しない。 / 決裁者: メンテナ。 | becomes=hs_ci | 未解決のまま持ち越し。なぜ: 方式（PAT/App/免除）の裁定が人間待ちだから。
N hs_watch   hotspot  定期workflowの失敗を誰も監視していない | role=dashboard.yml が6/27から5日間 failure し続けても気づかれなかった実績。失敗の通知機構が無い。 | discuss=決めること: failure 時の Issue 自動起票を入れるか。 / なぜ重要: 「生成は成功・公開だけ失敗」型の劣化が沈黙する。 / 決裁者: メンテナ。 | becomes=evt_wf_failed,pol_alert,cmd_alert | 失敗検知→起票判定→Issue起票の通知フローとして解消。なぜ: 沈黙する劣化は人間の注意でなく機械の通知で塞ぐべきだから。
N cmd_enforce command 台帳の完備を強制する（メタゲート） | in=ゲート名;型;挙動テストの有無;probe登録 | out=pass|reject | decide="untyped のゲート・挙動テストの無い reject 型ゲート・probe 未登録の注入可能ゲートを PR ごとに reject（check-gate-classified / check-gate-tests / probe --audit）" | evidence=core/scripts/check-gate-classified.sh:53, core/scripts/check-gate-tests.sh:53, core/scripts/probe-gate-liveness.sh:293 | test=docs/model/assertions/enforce-completeness.sh | role=モデル全体の前提（全ゲートに型とテストと生存証明の登録がある）を出荷前に守る、ゲートを検査するゲート。 | becomes=cmd_enforce | 変わらず。なぜ: 台帳完備の機械強制は確立済みだから。
N evt_incomplete errorevent 不完備なゲートの出荷が差し止められた | fields=ゲート名:一意キー; 欠落:untyped|テスト無し|probe未登録 | evidence=core/scripts/check-gate-classified.sh:53 | role=分類・テスト・生存証明登録のどれかを欠くゲートが PR で棄却された事実（終端＝人間が欠落を埋めて再提出）。 | becomes=evt_incomplete | 変わらず。なぜ: 同上。
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
E evt_alive  feeds    rm_dash
E evt_hist   feeds    rm_dash
E evt_verdict feeds   rm_dash
E hs_ci      marks    rm_dash
E hs_watch   marks    rm_dash
E act_maint  issues   cmd_enforce
E cmd_enforce handles agg_gate
E agg_gate   emits    evt_incomplete
E evt_dead   triggers act_maint
