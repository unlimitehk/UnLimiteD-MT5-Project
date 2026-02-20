# Electron Tool

MT5描画/発注運用を外部UIで行うためのElectronパネルです。

## 機能
- RR / エリオット操作パネル
- 「常に最前面」オプション（保存・復元）
- 既存CLI（CSVブリッジ）互換
- **BAT起動** / **Windows EXEビルド**対応

## すぐ使う（Windows）
- `run-panel.bat` を実行

初回は `npm install` を自動実行してからパネルを起動します。

## EXE化（Windows）
- `build-exe.bat` を実行

または手動コマンド:
```bash
cd "Electron Tool"
npm install
npm run dist:win
```

生成物:
- `Electron Tool/dist/UnLimiteD-RR-Panel-Setup-<version>.exe`

## 開発起動
```bash
cd "Electron Tool"
npm install
npm start
```

## CLI（従来互換）
```bash
npm run cli -- place EURUSD
```

## 運用マニュアル
詳細手順は `../docs/operation_manual_ja.md` を参照してください。
