# D-Day Before（輕量版）

自用、輕量、完全離線的 Android D-Day 日期倒數 APP，使用 Flutter + Material 3 打造，不要求任何網路權限、無帳號、無廣告。

## 主要功能

- **核心倒數（v0.1）**：新增／編輯／刪除、`D-N` / `D-Day` / `D+N`、「當天算第 1 天」紀念日模式、置頂、三種排序規則、繁體中文（`zh_TW`）日期選擇器、跨午夜前景自動刷新。
- **資料安全（v0.2）**：透過 Android SAF 匯出／匯入 `.json` 備份檔，或複製／貼上 JSON，支援「合併匯入」與「覆蓋全部」。
- **每年重複（v0.3）**：生日與週年紀念日每年自動跳到下一次，自動計算週年數（2/29 於平年以 2/28 計算）。
- **外觀自訂（v0.4）**：每張 D-Day 卡片可自訂 9 種配色，支援跟隨系統／淺色／深色主題。
- **提醒通知（v0.5）**：每筆可設當天／前 1／3／7 天提醒與自訂提醒時間、通知列常駐顯示，並於重開機後自動重建排程。
- **桌面小工具（v0.6）**：Android 原生主畫面 Widget，直接讀取本機 XML `SharedPreferences` 並跨午夜自動更新。

## 開發與測試

```powershell
# 靜態分析
flutter analyze

# Dart 單元測試
flutter test

# Android Kotlin 單元測試
cd android && .\gradlew.bat :app:testDebugUnitTest

# Android 模擬器 E2E 測試
flutter test integration_test/app_test.dart -d <device-id>

# 建置 arm64 Release APK（需事先準備本機 android/key.properties 與 keystore）
flutter build apk --release --target-platform android-arm64 --split-debug-info=build/debug_info
```

## 簽章說明

本專案已於 `.gitignore` 排除 `android/key.properties`、`*.jks`、`*.keystore` 與 `*.apk`。若要在新環境建置正式簽章 APK，請自行建立 `android/key.properties` 與 keystore 檔案（未提供時將自動退回 debug 簽章）。
