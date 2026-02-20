# UnLimiteD MT5 + Electron 運用マニュアル（実運用版）

## 1. 目的
本ツールは次の2層で構成されます。

- **MT5側**: 描画情報と発注エンジン（`MQL5/Indicators`, `MQL5/Experts`）
- **Electron側**: 操作パネル（常に最前面オプション付き）

実運用では、**Electronパネルを主操作UI**として使い、MT5側は執行・同期に専念させます。

---

## 2. フォルダ構成（最小）

- `MQL5/Indicators/RRDrawerIndicator.mq5`
- `MQL5/Experts/RRExecutionHubEA.mq5`
- `Electron Tool/`（UIとCLI）
- `docs/operation_manual_ja.md`（本書）

---

## 3. 初期セットアップ

### 3.1 MT5側
1. `RRDrawerIndicator.mq5` をコンパイル
2. `RRExecutionHubEA.mq5` をコンパイル
3. 対象チャートにインジ・EAを配置
4. インジ設定で `InpUseExternalPanel=true`（推奨）

### 3.2 Electron側
#### かんたん起動（Windows）
- `Electron Tool/run-panel.bat` を実行

#### EXE化したい場合（Windows）
- `Electron Tool/build-exe.bat` を実行
- 出力: `Electron Tool/dist/UnLimiteD-RR-Panel-Setup-<version>.exe`

#### 手動コマンド
```bash
cd "Electron Tool"
npm install
npm start
```

- パネル上部のチェックで「**常に最前面**」をON/OFF
- 設定は次回起動時に自動復元

---

## 4. 日次運用フロー（推奨）

1. MT5起動（EA稼働確認）
2. Electronパネル起動
3. 通貨ペア・チャート状態を確認
4. エリオットまたはRR描画
5. ARM（待機）→ EXEC（実行）
6. 約定結果とCSV連携結果を確認

---

## 5. 描画ルール（エリオット）

- ボタン押下で描画モード
- チャートクリックで点追加
- 各点は**クリックYに最も近い高値/安値**へスナップ
- `12345` / `ABC` は視認性のため ±3ポイント余白付き
- 戻るボタンで1点戻す
- 同じ描画ボタンを再押下で描画モード解除

---

## 6. RR運用ルール

- `+LONG` / `+SHORT` でRR作成
- `ライン同期: ON/OFF`（同一通貨の複数チャート間でRRライン同期）
- Entry/SL/TPを調整
- 右側の `RR削除` で当該RR削除
- `全描画削除` で描画を一括クリア

---


> 補足: ライン同期を使う場合は、インジ設定 `InpSyncLinesEnabled=true` またはパネル `ライン同期:ON` を利用します。

## 7. 外部連携（CSV）

EAと外部ツールは `FILE_COMMON` を介して連携します。

- `RRAvailableSetups.csv`
- `RRExternalCommands.csv`
- `RRExternalResults.csv`

CLI実行例:
```bash
npm run cli -- place EURUSD
```

---

## 8. 実運用チェックリスト

- [ ] デモ口座で十分なリハーサル済み
- [ ] スプレッド拡大時間帯の検証済み
- [ ] EAログ・結果CSVの監視手順がある
- [ ] 誤操作時の全削除/キャンセル手順を確認済み
- [ ] 常に最前面オプションON時の画面干渉を確認済み

---

## 9. トラブル時

- ボタン反応なし: MT5側イベントログ確認、再アタッチ
- 発注されない: ARM状態、EA稼働、CSV更新確認
- パネルが前面に来ない: Electronの「常に最前面」設定確認

---

## 10. 注意事項

- 本番運用前に必ずデモ口座で検証してください。
- 外部連携中は同一アカウントでの手動介入ルールを事前に定義してください。
