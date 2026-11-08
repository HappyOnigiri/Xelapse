# Xelapse アーキテクチャ
macOS メニューバー常駐タイムトラッカー。SwiftUI, SwiftData, SwiftCharts。App Sandbox 有効。ビルド: XcodeGen。

## 動作確認
- 動作確認を目的とした Xelapse 実アプリの起動は禁止する。ビルド成果物と `/Applications` のインストール版のどちらも起動しない。
- GUI 自動操作、ウィンドウの前面化、フォーカスやマウスポインターを奪う操作も行わない。
- 変更の検証には `make test` と `make ci` を使用する。

## エントリ/設定
- [XelapseApp.swift](Sources/XelapseApp.swift): エントリ, MenuBarExtra, SwiftDataセットアップ
- [project.yml](project.yml): XcodeGen設定, Sandbox権限
- [README.md](README.md): 仕様, ビルド手順

## Models
- [Project.swift](Sources/Models/Project.swift): プロジェクト(SwiftData)
- [TimeLog.swift](Sources/Models/TimeLog.swift): 記録ログ(SwiftData)

## Core
- [TimerEngine.swift](Sources/Core/TimerEngine.swift): タイマー状態管理
- [IdleDetector.swift](Sources/Core/IdleDetector.swift): アイドル検知(CGEventSource, 権限不要)
- [ReportAggregator.swift](Sources/Core/ReportAggregator.swift): データ集計
- [CSVExporter.swift](Sources/Core/CSVExporter.swift), [CSVExportService.swift](Sources/Core/CSVExportService.swift): CSV出力, NSSavePanel
- [AppSettings.swift](Sources/Core/AppSettings.swift): 設定管理
- [AppNavigation.swift](Sources/Core/AppNavigation.swift): 画面遷移/ウィンドウ制御
- [LoginItemService.swift](Sources/Core/LoginItemService.swift): ログイン自動起動設定
- [DurationFormatter.swift](Sources/Core/DurationFormatter.swift), [Color+Hex.swift](Sources/Core/Color+Hex.swift): ユーティリティ

## Views
- [MenuBarContentView.swift](Sources/Views/MenuBarContentView.swift): メイン画面(ポップオーバー)
- [MenuBarIcon.swift](Sources/Views/MenuBarIcon.swift): アイコン/アニメーション
- [DashboardView.swift](Sources/Views/DashboardView.swift): グラフ(Swift Charts)
- [ProjectManagementView.swift](Sources/Views/ProjectManagementView.swift): プロジェクトCRUD
- [SettingsView.swift](Sources/Views/SettingsView.swift): 設定画面
- [MainWindowView.swift](Sources/Views/MainWindowView.swift): 独立ウィンドウ
