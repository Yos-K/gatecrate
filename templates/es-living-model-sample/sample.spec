# サンプル コマンド仕様サイドカー（コマンド/プロセスの「箱の内側」: 入力→処理→出力）
# 集約の構成は .es の fields/states/transitions/invariant に持つ（ここには書かない）。

# ===== cmd_place : 注文を受け付ける =====
cmd_place in 顧客ID / 書籍ID / 数量
cmd_place step 入力検証 | 顧客ID形式・数量>0・書籍ID存在を確認。NGは入力不正で即返す
cmd_place step 在庫確認 | 在庫ビューで在庫数>=数量か確認。満たさなければ在庫切れ
cmd_place out 注文受理 / 入力不正

# ===== cmd_auth : 与信を依頼する =====
cmd_auth in 決済ID / 金額
cmd_auth step 冪等チェック | 決済IDで既存の与信を検索。与信済なら再与信しない(二重課金防止)
cmd_auth step 与信送信 | 決済ゲートウェイへ与信要求。成功→与信済、失敗→与信失敗イベント
cmd_auth out 与信済 / 与信失敗

# ===== cmd_capture : 売上を確定する =====
cmd_capture in 決済ID
cmd_capture step 前提確認 | 決済状態が与信済であること（順序の不変条件）
cmd_capture step 売上確定送信 | 決済ゲートウェイへ売上確定。成功→確定、失敗→返金補償へ
cmd_capture out 確定済 / 失敗時は返金補償へ
