# サンプル: オンライン書店の注文・決済ドメイン（TO-BE）— gatecrate ES living-model デモ
# 命名規約: コマンド=現在形動詞 / イベント=過去形 / ポリシー=条件判定 / 集約=名詞。ドメイン中立の例。
N act_cust    actor    購入者 | is=role | role-of=人 | role=書籍を選び注文を出す利用者。業務の起点（誰が何を求めるか）。
N ext_pay     external 決済ゲートウェイ | role=与信・売上確定・返金を実行する外部決済サービス。本系はこれに順応する。
N cmd_place   command  注文を受け付ける | in=顧客ID;書籍ID;数量 | out=受理|入力不正 | decide="顧客ID形式・数量>0・在庫>=数量 を満たせば受理" | role=注文要求を検証し受理/不正を返す入口。
N agg_order   aggregate 注文 | is=relator | alias=オーダー | fields=注文ID:一意キー(同一性キー); 顧客ID:利用者識別; 明細:書籍IDと数量の組 | states=受付 // 注文を受け取り、成立がまだ確定していない局面|確定 // 注文として成立した終端|取消 // 成立せず打ち消された終端 | transitions=確定する:受付->確定 // 決済成立を受けて注文を確定させる; 取消する:受付->取消 // 在庫切れ・決済失敗時に注文を打ち消す | invariant=明細は1件以上 かつ 数量は正 | role=1件の注文の明細と進行状態を持つ実体。
N evt_placed  event    注文された | fields=注文ID:一意キー; 顧客ID:利用者識別 | role=注文が受理された事実。 | biz=value | measure=受理率(受理/要求)。ファネル入口の健全性(ここで弾かれると価値に到達しない)。 | capture=注文イベント発火点で構造化ログ(注文ID,顧客ID,発生時刻)を出力。 | compute=受理率＝集計期間(例5分間)あたりの 受理件数÷要求件数。
N pol_gate    policy   決済可否を判定 | in=在庫数;明細 | out=決済可|在庫切れ | decide="在庫数>=明細の数量 なら決済可、満たさなければ在庫切れ" | role=在庫を確認して決済へ進めるか判定する関門。決済可のときだけ与信へ。
N rm_inv      readmodel 在庫ビュー | fields=書籍ID:識別; 在庫数:0以上の整数 | role=書籍の在庫数を参照するビュー。決済可否判定の入力。
N cmd_auth    command  与信を依頼する | in=決済ID;金額 | out=与信済|与信失敗 | decide="決済IDで冪等(何度実行しても結果が同じ)に与信要求を送る" | role=決済の与信を外部へ要求し、決済の最初の遷移を起こすコマンド。
N agg_pay     aggregate 決済 | is=relator | fields=決済ID:一意キー(同一性キー); 金額:通貨額 | states=受信 // 決済要求を受け取り、与信がまだの初期局面|与信済 // 支払い枠を確保済み(金銭は未確定)|売上確定 // 請求が確定し売上計上された終端|返金済 // 支払いを打ち消した終端 | transitions=与信する:受信->与信済|与信失敗 // 決済手段に支払い枠を確保する(まだ金銭は動かない); 売上確定する:与信済->売上確定 // 確保した枠の請求を確定し売上として計上する; 返金する:与信済->返金済 // 確保した枠を解放し支払いを打ち消す(補償) | invariant=遷移は定義された矢印のみ かつ 決済IDで冪等(何度実行しても結果が同じ) | role=1回の決済の進行状態(受信→与信→売上確定/返金)を持ち、二重課金と順序違反を防ぐ中核。
N evt_authed  event    与信した | fields=決済ID:一意キー | role=与信(支払い枠の確保)ができた事実。次の売上確定へ進める。 | biz=revenue | measure=与信成功率(収益への前進・ファネル中間)。
N evt_authng  event    与信が失敗した | fields=決済ID:一意キー; 理由:失敗コード | role=与信が取れなかった事実。返金補償を起こす。 | biz=degrade | measure=与信失敗率・理由別内訳。UX毀損の主因・収益漏れ点。
N pol_settle  policy   売上確定の要否を判定 | in=決済状態 | out=確定|補償 | decide="決済状態が与信済なら売上確定。それ以外は返金補償へ" | role=与信済の決済を売上計上(確定)してよいか判断するルール。確定のときだけ確定コマンドへ。
N cmd_capture command  売上を確定する | in=決済ID | out=確定済 | decide="状態=与信済のみ確定可" | role=決済ゲートウェイへ売上確定を要求し、決済を確定状態へ進めるコマンド。
N evt_captured event   売上が確定した | fields=注文ID:一意キー; 決済ID:一意キー; 金額:通貨額 | role=売上計上と注文確定が成立した事実。 | biz=revenue;value | measure=確定率(確定÷要求)・確定までの所要時間(中央値p50・遅い方1%p99)・売上額。サービス品質の中心指標。 | capture=確定イベント発火点で構造化ログ(注文ID,決済ID,金額,発生時刻)を出力。注文イベントと注文IDで突合し受付→確定の所要時間を計測。 | compute=確定率＝集計期間あたりの 確定件数÷受理件数; 所要時間＝(確定時刻−受付時刻)の分布の中央値(p50)と遅い方1%(p99); 売上＝金額合計。
N pol_comp    policy   返金補償の要否を判定 | in=決済状態 | out=返金|不要 | decide="状態=与信済で後続が失敗したら返金(二重課金防止)。それ以外は不要" | role=与信後の失敗時に支払いを打ち消し二重課金を防ぐ補償ルール。返金のときだけ返金コマンドへ。
N cmd_refund  command  返金する | in=決済ID | out=返金済 | decide="状態=与信済のみ返金・返金は冪等(何度実行しても結果が同じ)" | role=決済ゲートウェイへ返金を要求する補償コマンド。
N evt_refunded event   返金した | fields=決済ID:一意キー | role=決済が打ち消され、収益にならなかった事実。 | biz=degrade | measure=返金率(返金/与信)。発生＝価値未提供。
# === エッジ（policy→command は when= でどの出力か明示）===
E act_cust    issues   cmd_place
E cmd_place   handles  agg_order
E agg_order   emits    evt_placed
E evt_placed  triggers pol_gate
E pol_gate    issues   cmd_auth | when=決済可
E cmd_auth    handles  agg_pay
E agg_pay     emits    evt_authed
E agg_pay     emits    evt_authng
E evt_authed  triggers pol_settle
E pol_settle  issues   cmd_capture | when=確定
E cmd_capture handles  agg_pay
E agg_pay     emits    evt_captured
E evt_captured feeds   rm_inv
E evt_authng  triggers pol_comp
E pol_comp    issues   cmd_refund | when=返金
E cmd_refund  handles  agg_pay
E agg_pay     emits    evt_refunded
