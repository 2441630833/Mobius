# =============================================================================
# Mobius IDE — Windows One-Line Fast Installer & Auto-Updater
# Usage:
#   irm https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-win.ps1 | iex
#
# Flags / Options:
#   $env:MOBIUS_FORCE = "1"     # Force re-download and reinstall even if already latest
#   $env:MOBIUS_CHECK = "1"     # Check version only without downloading
# =============================================================================

[CmdletBinding()]
param(
    [switch]$Force = $false,
    [switch]$CheckOnly = $false
)

$ErrorActionPreference = "Stop"
$Repo = "2441630833/Mobius"

try {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
} catch {}

# Check environment variables for piped execution
if ($env:MOBIUS_FORCE -eq "1" -or $env:MOBIUS_FORCE_UPDATE -eq "1") {
    $Force = $true
}
if ($env:MOBIUS_CHECK -eq "1") {
    $CheckOnly = $true
}

# 1. Detect Architecture
$arch = if ([System.Environment]::Is64BitOperatingSystem) { "x64" } else { "ia32" }

# 2. Detect Local Installation
$installedPath = $null
$installedExe = $null
$installedVer = $null
$installedTag = $null
$installedDate = $null

$candidatePaths = @(
    (Join-Path $env:LOCALAPPDATA "Programs\Mobius"),
    (Join-Path $env:ProgramFiles "Mobius")
)
if ($env:SystemDrive) {
    $candidatePaths += "${env:SystemDrive}\Program Files (x86)\Mobius"
}

# Also inspect PATH for installed mobius
$cmdMobius = Get-Command mobius -ErrorAction SilentlyContinue
if ($cmdMobius -and $cmdMobius.Source) {
    $binDir = Split-Path $cmdMobius.Source -Parent
    $parentDir = Split-Path $binDir -Parent
    if ($parentDir -and ($candidatePaths -notcontains $parentDir)) {
        $candidatePaths = @($parentDir) + $candidatePaths
    }
}

foreach ($p in $candidatePaths) {
    if ($p -and (Test-Path (Join-Path $p "Mobius.exe"))) {
        $installedPath = $p
        $installedExe = Join-Path $p "Mobius.exe"
        break
    }
}

if ($installedExe) {
    try {
        $installedVer = (Get-Item $installedExe).VersionInfo.ProductVersion
    } catch {}

    $tagFile = Join-Path $installedPath ".mobius-installed-tag"
    if (Test-Path $tagFile) {
        $installedTag = (Get-Content $tagFile -Raw -ErrorAction SilentlyContinue).Trim()
    }

    $productJson = Join-Path $installedPath "resources\app\product.json"
    if (Test-Path $productJson) {
        try {
            $pj = Get-Content $productJson -Raw | ConvertFrom-Json
            if (-not $installedVer -and $pj.version) { $installedVer = $pj.version }
            if ($pj.date) { $installedDate = $pj.date }
        } catch {}
    }
}

$isInstalled = [bool]$installedExe
if ($isInstalled) {
    Write-Host "`n=== Mobius: Local Install & Update Check ===" -ForegroundColor Cyan
    Write-Host "  - Install Path: $installedPath" -ForegroundColor DarkGray
    $tagDisplay = if ($installedTag) { "[$installedTag]" } else { "" }
    $verDisplay = if ($installedVer) { $installedVer } else { "Installed" }
    Write-Host "  - Current Version: $verDisplay $tagDisplay" -ForegroundColor DarkGray
    if ($installedDate) {
        Write-Host "  - Local Build Date: $installedDate" -ForegroundColor DarkGray
    }
} else {
    Write-Host "`n=== Installing Mobius for Windows ===" -ForegroundColor Cyan
    Write-Host "Architecture: $arch" -ForegroundColor DarkGray
}

# 3. Query Latest Release Information
Write-Host "`nFetching latest release information from GitHub..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$downloadUrl = $null
$latestTag = $null
$latestReleaseName = $null
$latestPublishDate = $null

try {
    $headers = @{ "User-Agent" = "Mobius-Installer-Windows" }
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Headers $headers -UseBasicParsing
    foreach ($rel in $releases) {
        $asset = $rel.assets | Where-Object { $_.name -like "Mobius-Setup-*-win32-$arch.exe" -or $_.name -like "MobiusSetup.exe" } | Select-Object -First 1
        if ($asset) {
            $downloadUrl = $asset.browser_download_url
            $latestTag = $rel.tag_name
            $latestReleaseName = $rel.name
            $latestPublishDate = $rel.published_at
            break
        }
    }
} catch {
    # If GitHub API is rate-limited, fallback gracefully
}

if (-not $downloadUrl) {
    # Default fallback to latest known release with Windows binary
    $latestTag = "v1.0.2"
    $latestReleaseName = "v1.0.2"
    $latestPublishDate = "2026-09-13T06:11:02Z"
    $downloadUrl = "https://github.com/$Repo/releases/download/v1.0.2/MobiusSetup.exe"
}

Write-Host "Remote Release: $latestTag" -ForegroundColor DarkGray
Write-Host "Download URL: $downloadUrl" -ForegroundColor DarkGray

# 4. Compare Version & Determine Action
$needsUpdate = $false
$updateReason = ""

if (-not $isInstalled) {
    $needsUpdate = $true
    $updateReason = "FreshInstall"
} elseif ($Force) {
    $needsUpdate = $true
    $updateReason = "ForceReinstall"
} else {
    # Compare installed tag vs latest release tag
    if ($installedTag -and $latestTag -and ($installedTag -eq $latestTag)) {
        $needsUpdate = $false
    } elseif ($installedTag -and $latestTag -and ($installedTag -ne $latestTag)) {
        $needsUpdate = $true
        $updateReason = "TagMismatch ($installedTag -> $latestTag)"
    } else {
        # No tag recorded previously. Compare dates if available.
        if ($installedDate -and $latestPublishDate) {
            try {
                $locD = [datetime]::Parse($installedDate)
                $remD = [datetime]::Parse($latestPublishDate)
                if ($remD -gt $locD) {
                    $needsUpdate = $true
                    $updateReason = "NewerReleaseFound"
                } else {
                    $needsUpdate = $false
                }
            } catch {
                $needsUpdate = $true
                $updateReason = "InitialTagSync"
            }
        } else {
            $needsUpdate = $true
            $updateReason = "InitialTagSync"
        }
    }
}

if ($CheckOnly) {
    if ($needsUpdate) {
        Write-Host "`n[Update Available] 发现新版本: $latestTag ($updateReason)" -ForegroundColor Yellow
    } else {
        Write-Host "`n[Up to Date] Mobius is already up to date ($latestTag)." -ForegroundColor Green
    }
    return
}

# If already up-to-date and not forced, exit gracefully without redundant multi-GB downloads
if (-not $needsUpdate) {
    Write-Host "`n[Up to Date] 本地 Mobius 已是最新版本 ($latestTag)，无需重复下载更新。" -ForegroundColor Green
    Write-Host "  - 当前安装路径: $installedPath" -ForegroundColor DarkGray
    Write-Host "  - 若需强制重新下载安装/覆盖修复，可运行:" -ForegroundColor DarkGray
    Write-Host "    `$env:MOBIUS_FORCE=1; irm https://raw.githubusercontent.com/$Repo/main/scripts/install-win.ps1 | iex`n" -ForegroundColor Yellow
    Write-Host "启动 Mobius: 终端运行 'mobius' 或在开始菜单直接打开即可。" -ForegroundColor Cyan
    return
}

# 5. Handle Running Processes Before Update
if ($isInstalled) {
    Write-Host "`n=== 正在同步更新 Mobius ===" -ForegroundColor Cyan
    Write-Host "准备从 $($installedVer) $($installedTag) 同步更新至最新发布版 $latestTag..." -ForegroundColor Cyan

    $runningProcs = Get-Process Mobius -ErrorAction SilentlyContinue
    if ($runningProcs) {
        Write-Host "检测到 Mobius 正在运行，正在关闭以防止安装文件锁定..." -ForegroundColor Yellow
        $runningProcs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

# 6. Download Installer
$tempInstaller = Join-Path $env:TEMP "MobiusSetup-$latestTag.exe"
Write-Host "Downloading Mobius installer ($latestTag)..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $downloadUrl -OutFile $tempInstaller -UseBasicParsing

# 7. Run Installer
Write-Host "Running Mobius Setup..." -ForegroundColor Cyan
# Silent user install by default (/SILENT /SP-)
$process = Start-Process -FilePath $tempInstaller -ArgumentList "/SILENT /SP-" -PassThru -Wait

# 8. Record tag file into installation directory
$targetDir = if ($installedPath) { $installedPath } else { Join-Path $env:LOCALAPPDATA "Programs\Mobius" }
if (Test-Path $targetDir) {
    Set-Content -Path (Join-Path $targetDir ".mobius-installed-tag") -Value $latestTag -Force -ErrorAction SilentlyContinue
}

# 9. Clean up
Remove-Item -Path $tempInstaller -Force -ErrorAction SilentlyContinue

if ($isInstalled) {
    Write-Host "`n[Success] Mobius 已成功同步更新至最新版本 ($latestTag)！" -ForegroundColor Green
    Write-Host "您的扩展插件、用户配置与工作区数据均完整保留。" -ForegroundColor DarkGray
} else {
    Write-Host "`n[Success] Mobius has been installed successfully ($latestTag)!" -ForegroundColor Green
    Write-Host "You can find Mobius in your Start Menu and Desktop." -ForegroundColor DarkGray
}
Write-Host "Enjoy shipping with Mobius!`n" -ForegroundColor Cyan
