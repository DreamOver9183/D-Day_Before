<#
.SYNOPSIS
  Publishes a D-Day Before update as a GitHub Release that the app's
  in-app updater picks up.

.DESCRIPTION
  1. Optionally bumps the version in pubspec.yaml (-Bump) and commits it.
  2. Requires a clean working tree so the release matches the code.
  3. Runs flutter analyze and flutter test (skip with -SkipTests).
  4. Builds the release APK signed with the key in android/key.properties.
  5. Writes update.json (versionCode, versionName, apk, sha256).
  6. Pushes and creates GitHub Release v<version> with the APK and update.json.

  -DryRun does every check and the build but does not commit, push or publish.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\tool\release.ps1 -Bump -Notes "修正小工具顯示"
  powershell -ExecutionPolicy Bypass -File .\tool\release.ps1 -Bump -NotesFile notes.md
  powershell -ExecutionPolicy Bypass -File .\tool\release.ps1 -Notes "x" -DryRun
#>
param(
    [string]$Notes,
    [string]$NotesFile,
    [switch]$Bump,
    [switch]$SkipTests,
    [switch]$DryRun
)

# Native tools (gh, git, flutter) write progress to stderr. Under 'Stop',
# Windows PowerShell 5.1 turns that into a fatal error, so failures are
# detected through exit codes instead.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$utf8 = New-Object System.Text.UTF8Encoding($false)

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

# --- Release notes -------------------------------------------------------
if ($NotesFile) {
    if (-not (Test-Path $NotesFile)) { Fail "找不到說明檔 $NotesFile" }
    $Notes = [System.IO.File]::ReadAllText((Resolve-Path $NotesFile), $utf8)
}
if ([string]::IsNullOrWhiteSpace($Notes)) { Fail '請用 -Notes 或 -NotesFile 提供更新說明。' }

# --- Preconditions -------------------------------------------------------
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail '找不到 GitHub CLI (gh)。' }
gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Fail 'gh 尚未登入，請先執行 gh auth login。' }
if (-not (Test-Path 'android\key.properties')) {
    Fail '找不到 android\key.properties。沒有正式金鑰時會用 debug 簽章，手機無法用它覆蓋更新。'
}

$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = [System.IO.File]::ReadAllText($pubspecPath, $utf8)
$match = [regex]::Match($pubspec, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$')
if (-not $match.Success) { Fail 'pubspec.yaml 的 version 必須是 x.y.z+n 格式。' }
$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value
$code = [int]$match.Groups[4].Value

$dirty = git status --porcelain
if ($dirty) { Fail '工作目錄有未提交的變更，請先 commit。' }

if ($Bump) {
    $patch++
    $code++
}
$versionName = "$major.$minor.$patch"
$tag = "v$versionName"

gh release view $tag 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { Fail "GitHub 上已經有 $tag，請加上 -Bump 產生新版本。" }

if ($Bump -and -not $DryRun) {
    $newLine = "version: $versionName+$code"
    $pubspec = [regex]::Replace($pubspec, '(?m)^version:.*$', $newLine)
    [System.IO.File]::WriteAllText($pubspecPath, $pubspec, $utf8)
    Invoke-Checked '提交版本號' { git commit -am "chore(release): $tag" }
}

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
Copy-Item 'build\app\outputs\flutter-apk\app-release.apk' $apkPath -Force -ErrorAction Stop

$sha256 = (Get-FileHash $apkPath -Algorithm SHA256).Hash.ToLowerInvariant()
$manifest = [ordered]@{
    versionCode = $code
    versionName = $versionName
    apk         = $apkName
    sha256      = $sha256
} | ConvertTo-Json
$manifestPath = Join-Path $outDir 'update.json'
[System.IO.File]::WriteAllText($manifestPath, $manifest, $utf8)

# Notes go through a UTF-8 file: Windows PowerShell can mangle non-ASCII
# command-line arguments passed to native programs.
$notesPath = Join-Path $outDir 'release-notes.md'
[System.IO.File]::WriteAllText($notesPath, $Notes, $utf8)

if ($DryRun) {
    Write-Host ''
    Write-Host "DryRun 完成，未推送也未發佈：$tag (versionCode $code)" -ForegroundColor Yellow
    Write-Host "APK：$apkPath"
    Write-Host "APK SHA-256：$sha256"
    Write-Host "update.json：$manifestPath"
    exit 0
}

# --- Publish -------------------------------------------------------------
Invoke-Checked '推送到 GitHub' { git push }
$head = (git rev-parse HEAD).Trim()
Invoke-Checked "建立 GitHub Release $tag" {
    gh release create $tag $apkPath $manifestPath --target $head --title "D-Day Before $tag" --notes-file $notesPath
}

Write-Host ''
Write-Host "完成：$tag (versionCode $code) 已發佈，手機上的 APP 會在下次檢查時收到更新。" -ForegroundColor Green
Write-Host "APK SHA-256：$sha256"
