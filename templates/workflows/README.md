# consumer workflow templates — cron が仕事を生成する

「エージェントに何を任せるか」の実行の置き場をローカルPCからクラウドへ移すための、消費側向け
GitHub Actions テンプレート。**コピーして `.github/workflows/` に置き、パスを自分のリポに合わせる**だけで、
定期実行が保守の仕事（issue / ダッシュボード）を自動生成する。

| テンプレ | 周期 | 何をするか |
|---|---|---|
| `es-evidence-drift.yml` | 日次 | `.es` モデルとコードの乖離を検査し、壊れたら **issue を起票**（緑復帰で自動クローズ） |
| `harness-roi.yml` | 週次 | ゲート発火履歴から **ROI判定＋ダッシュボード**を Actions Summary に描画（剪定候補の可視化） |

前提: ゲート群が `scripts/` に vendoring 済み（`install.sh` / `gatecrate-setup`）。
gatecrate 自身も同型の `es-drift.yml` を dogfood 運用している（`.github/workflows/es-drift.yml`）。
