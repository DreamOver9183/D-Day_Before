<#
.SYNOPSIS
  Publishes a D-Day Before update as a GitHub Release that the app's
  in-app updater picks up.

.DESCRIPTION
  1. Optionally bumps the version in pubspec.yaml (-Bump) and commits it.
  2. Requires a clean, pushed working tree so the release matches the code.
  3. Runs flutter analyze and flutter test (skip with -SkipTests).
  4. Builds the release APK signed with the key in android/key.properties.
  5. Writes update.json (versionCode, versionName, apk, sha256).
  6. Creates GitHub Release v<version> with the APK and update.json.

.EXAMPLE
  .\tool\release.ps1 -Bump -Notes "修正小工具顯示"
  .\tool\release.ps1 -Notes "第一個支援自動更新的版本"
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Notes,
    [switch]$Bump,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Fail($message) {
    Write-Host "錯誤：$message" -ForegroundColor Red
    exit 1
}

function Invoke-Checked {
    param([string]$Label, [scriptblock]$Command)
    Write-Host "==> $Label" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) { Fail "$Label 失敗 (exit $LASTEXITCODE)" }
}

# --- Preconditions -------------------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail '找不到 GitHub CLI (gh)。' }
gh auth status *> $null
if ($LASTEXITCODE -ne 0) { Fail 'gh 尚未登入，請先執行 gh auth login。' }
if (-not (Test-Path 'android\key.properties')) {
    Fail '找不到 android\key.properties。沒有正式金鑰時會用 debug 簽章，手機無法用它覆蓋更新。'
}

$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = Get-Content $pubspecPath -Raw -Encoding UTF8
$match = [regex]::Match($pubspec, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
if (-not $match.Success) { Fail 'pubspec.yaml 的 version 必須是 x.y.z+n 格式。' }
$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value
$code = [int]$match.Groups[4].Value

if (git status --porcelain) { Fail '工作目錄有未提交的變更，請先 commit。' }

if ($Bump) {
    $patch++
    $code++
    $newLine = "version: $major.$minor.$patch+$code"
    $pubspec = [regex]::Replace($pubspec, '(?m)^version:.*$', $newLine)
    [System.IO.File]::WriteAllText($pubspecPath, $pubspec, (New-Object System.Text.UTF8Encoding($false)))
    Invoke-Checked '提交版本號' { git commit -am "chore(release): v$major.$minor.$patch" }
}

$versionName = "$major.$minor.$patch"
$tag = "v$versionName"

gh release view $tag *> $null
if ($LASTEXITCODE -eq 0) { Fail "GitHub 上已經有 $tag，請加上 -Bump 產生新版本。" }

Invoke-Checked '推送到 GitHub' { git push }
$head = (git rev-parse HEAD).Trim()

# --- Verify, build, package ----------------------------------------------
if (-not $SkipTests) {
    Invoke-Checked 'flutter analyze' { flutter analyze }
    Invoke-Checked 'flutter test' { flutter test }
}
Invoke-Checked '建置 release APK' {
    flutter build apk --release --target-platform android-arm64 --split-debug-info=build/debug_info
}

$outDir = Join-Path $root 'build\release'
New-Item -ItemType Directory -Force $outDir | Out-Null
$apkName = "dday_before-$versionName.apk"
$apkPath = Join-Path $outDir $apkName
Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' $apkPath -Force

$sha256 = (Get-FileHash $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    versionCode = $code
    versionName = $versionName
    apk         = $apkName
    sha256      = $sha256
} | ConvertTo-Json
$manifestPath = Join-Path $outDir 'update.json'
[System.IO.File]::WriteAllText($manifestPath, $manifest, (New-Object System.Text.UTF8Encoding($false)))

# --- Publish -------------------------------------------------------------
# Notes go through a UTF-8 file: Windows PowerShell can mangle non-ASCII
# command-line arguments passed to native programs.
$notesPath = Join-Path $outDir 'release-notes.md'
[System.IO.File]::WriteAllText($notesPath, $Notes, (New-Object System.Text.UTF8Encoding($false)))

Invoke-Checked "建立 GitHub Release $tag" {
    gh release create $tag $apkPath $manifestPath --target $head --title "D-Day Before $tag" --notes-file $notesPath
}

Write-Host ''
Write-Host "完成：$tag (versionCode $code) 已發佈，手機上的 APP 會在下次檢查時收到更新。" -ForegroundColor Green
Write-Host "APK SHA-256：$sha256"
