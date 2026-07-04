# サンプル: オンライン書店の注文・決済ドメイン（AS-IS）— gatecrate ES living-model デモ
# role= は AS-IS の「実コードでの役割＋実装の実態評価」。becomes= は TO-BE への変化と「なぜ」。
# evidence は実コード行を指す（本サンプルは説明用の架空ファイル）。
N act_cust  actor    購入者 | role=注文を出す利用者。業務の起点。 | becomes=act_cust | 変わらず。なぜ: 注文の起点は同じだから。
N cmd_order command  注文処理 | evidence=OrderService.java:40 | role=注文受付〜在庫確認〜与信〜売上確定〜確定を1メソッドで行う厚いエントリ。責務が集中。 | becomes=cmd_place,cmd_auth,cmd_capture | 受付/与信/確定に分離。なぜ: 1メソッドに複数責務が凝集し、段ごとの失敗時補償を仕様化できないため。
N agg_svc   aggregate 注文処理(OrderService) | fields=注文ID:識別; 在庫数:確認時点の値; 決済状態コード:[0|1|2](各所が部分解釈・正典定義なし) | invariant=在庫>=数量 かつ 決済成功でのみ注文確定 | evidence=OrderService.java:40 | role=注文・在庫・決済の状態が混在する手続き的サービス。決済状態が各所に散在。 | becomes=agg_order,agg_pay | 注文集約と決済集約(状態機械)に分割。なぜ: 注文と決済の状態が混ざると二重課金・順序違反を型で防げないため。
N evt_done  event    注文完了 | fields=注文ID:識別; 決済状態コード:成功を示す値(部分解釈) | evidence=OrderService.java:120 | role=注文と決済が成立した事実(成功応答)。 | becomes=evt_captured | 売上確定イベントとして明示。なぜ: 収益/価値の事実を明示しないと事業計測の起点が定まらないため。
N evt_fail  event    注文失敗 | fields=注文ID:識別; 失敗理由:与信失敗等の文字列 | evidence=OrderService.java:150 | role=与信失敗等で注文が成立しなかった事実。 | becomes=evt_authng,evt_refunded | 与信失敗と返金に分離。なぜ: 失敗の事実と補償の事実は別の関心で、別々に駆動する必要があるため。
N hs_pay    hotspot  決済状態コードの正典定義が無い（二重課金リスク） | role=決済の状態コード(0/1/2…)の正典定義が不在で各所が部分解釈する論点。誤分類が二重課金に直結する最重要hotspot。 | discuss=決めること: 決済状態コードの全定義を誰が持つか。 / なぜ重要: 誤分類が二重課金に直結。 / 決裁者: 決済設計者。 | becomes=agg_pay | 状態遷移を正典化。なぜ: 定義書の欠如で部分解釈が誤分類を生むため、状態機械で表現不能にする。
# === エッジ ===
E act_cust  issues  cmd_order
E cmd_order handles agg_svc
E agg_svc   emits   evt_done
E agg_svc   emits   evt_fail
E hs_pay    marks   agg_svc
