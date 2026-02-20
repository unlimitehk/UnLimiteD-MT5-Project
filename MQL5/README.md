# MQL5 構成

- `Indicators/RRDrawerIndicator.mq5`
  - RR描画とエリオット描画のデータ連携ロジック。
  - `InpUseExternalPanel=true`（既定）で、チャート内パネルを無効化しElectron運用を前提化。

- `Experts/RRExecutionHubEA.mq5`
  - GlobalVariablesの ARM/EXEC 要求を監視し、リスク計算ロットで実行。
  - `FILE_COMMON` のCSVで外部ツールと連携。

- `../Electron Tool/`
  - 実運用用の操作パネル（常に最前面オプションあり）。

- `../docs/operation_manual_ja.md`
  - 実運用手順、日次フロー、チェックリスト。
