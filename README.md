# D-Day Before（輕量版）

自用、輕量的 Android D-Day 日期倒數 APP，使用 Flutter + Material 3 打造，資料只存在手機本機、無帳號、無廣告。唯一的網路連線是向本專案的 GitHub Releases 檢查 APP 更新（可在設定中關閉自動檢查），不會傳送任何個人資料。

## 主要功能

- **核心倒數（v0.1）**：新增／編輯／刪除、`D-N` / `D-Day` / `D+N`、「當天算第 1 天」紀念日模式、置頂、三種排序規則、繁體中文（`zh_TW`）日期選擇器、跨午夜前景自動刷新。
- **資料安全（v0.2）**：透過 Android SAF 匯出／匯入 `.json` 備份檔，或複製／貼上 JSON，支援「合併匯入」與「覆蓋全部」。
- **每年重複（v0.3）**：生日與週年紀念日每年自動跳到下一次，自動計算週年數（2/29 於平年以 2/28 計算）。
- **外觀自訂（v0.4）**：每張 D-Day 卡片可自訂 9 種配色，支援跟隨系統／淺色／深色主題。
- **提醒通知（v0.5）**：每筆可設當天／前 1／3／7 天提醒與自訂提醒時間、通知列常駐顯示，並於重開機後自動重建排程。
- **桌面小工具（v0.6）**：Android 原生主畫面 Widget，直接讀取本機 XML `SharedPreferences` 並跨午夜自動更新。

- **外觀與照片（v1.0.1）**：珊瑚紅主題與白色卡片、12 種分類圖示、每筆可設背景照片（照片僅存本機，不含在 JSON 備份）、「模式設定」整合紀念日／每年重複、桌面小工具底部文字橫幅。
- **APP 內更新（v1.0.1）**：每天最多自動檢查一次 GitHub Releases，或在設定按「檢查更新」；下載後驗證 SHA-256，再交給 Android 安裝程式（首次需允許「安裝不明應用程式」）。

## 發佈更新

更新以 GitHub Release 發佈，每個 Release 附上 APK 與 `update.json`（`versionCode`、`versionName`、`apk`、`sha256`）。在乾淨且已 commit 的工作目錄執行：

```powershell
# 版本號 patch +1、versionCode +1，提交並推送後建置與發佈
powershell -ExecutionPolicy Bypass -File .\tool\release.ps1 -Bump -Notes "這次更新的內容"
```

腳本會檢查 `android/key.properties`（必須用同一把正式金鑰簽章，手機才能覆蓋更新）、執行 `flutter analyze` 與 `flutter test`、建置 release APK、計算 SHA-256 並用 `gh release create` 發佈。**請務必備份 keystore 與 `key.properties`，遺失後將無法再發佈可覆蓋安裝的更新。**

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
