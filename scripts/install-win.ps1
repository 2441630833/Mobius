# =============================================================================
# Mobius IDE — Windows One-Line Fast Installer & Auto-Updater
# Usage:
#   irm https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-win.ps1 | iex
#
# Flags / Options:
#   $env:MOBIUS_FORCE = "1"     # Force re-download and reinstall even if already latest
#   $env:MOBIUS_CHECK = "1"     # Check version only without downloading
#   $env:MOBIUS_AUTO_CLOSE = "0" # Keep this terminal open after success
#   .\install-win.ps1 -KeepOpen # Same override when running a saved script
# =============================================================================

[CmdletBinding()]
param(
    [switch]$Force = $false,
    [switch]$CheckOnly = $false,
    [switch]$KeepOpen = $false
)

$ErrorActionPreference = "Stop"
$Repo = "2441630833/Mobius"

function Show-MobiusToast {
    param([string]$Title, [string]$Message, [string]$InstallPath)

    try {
        # Inno Setup registers this ID on the Mobius Start Menu shortcut.
        $appId = 'Mobius'
        $productFile = Join-Path $InstallPath 'resources\app\product.json'
        if (Test-Path -LiteralPath $productFile) {
            $product = Get-Content -LiteralPath $productFile -Raw | ConvertFrom-Json
            if ($product.win32AppUserModelId) { $appId = $product.win32AppUserModelId }
        }
        $titleXml = [System.Security.SecurityElement]::Escape($Title)
        $messageXml = [System.Security.SecurityElement]::Escape($Message)
        $xml = '<toast><visual><binding template="ToastGeneric"><text>' + $titleXml +
            '</text><text>' + $messageXml + '</text></binding></visual></toast>'
        $xmlBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($xml))

        # Windows PowerShell provides WinRT on both PS 5.1 and PS 7 hosts,
        # without installing a notification module or leaving a helper window.
        $toastScript = @'
$ErrorActionPreference = 'Stop'
try {
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
    $document = New-Object Windows.Data.Xml.Dom.XmlDocument
    $document.LoadXml([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__XML__')))
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('__APPID__')
    if ($notifier.Setting -ne 'Enabled') { throw 'Windows notifications are disabled.' }
    $toast = [Windows.UI.Notifications.ToastNotification]::new($document)
    $notifier.Show($toast)
} catch {
    exit 1
}
'@
        $toastScript = $toastScript.Replace('__XML__', $xmlBase64).Replace('__APPID__', $appId.Replace("'", "''"))
        $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($toastScript))
        $windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $notificationProcess = Start-Process -FilePath $windowsPowerShell -WindowStyle Hidden -PassThru `
            -ArgumentList "-NoProfile -NonInteractive -EncodedCommand $encoded"
        try {
            # Cache the handle so Windows PowerShell 5.1 retains the exit code.
            $null = $notificationProcess.Handle
            if (-not $notificationProcess.WaitForExit(10000)) {
                $notificationProcess.Kill()
                throw 'Windows notification timed out.'
            }
            if ($notificationProcess.ExitCode -ne 0) { throw 'Windows could not show the notification.' }
        } finally {
            $notificationProcess.Dispose()
        }
        return $true
    } catch {
        Write-Warning "Mobius 已完成操作，但无法显示 Windows 通知，将保留终端结果。$($_.Exception.Message)"
        return $false
    }
}

function Complete-MobiusInstall {
    param([string]$Title, [string]$Message, [string]$InstallPath)

    $notified = Show-MobiusToast -Title $Title -Message $Message -InstallPath $InstallPath
    $global:LASTEXITCODE = 0
    if ($notified -and -not $KeepOpen -and $env:MOBIUS_AUTO_CLOSE -ne '0') {
        Write-Host '操作成功，终端将在 2 秒后自动关闭。设置 MOBIUS_AUTO_CLOSE=0 可保留终端。' -ForegroundColor Cyan
        Start-Sleep -Seconds 2
        exit 0
    }
}

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
    Complete-MobiusInstall -Title 'Mobius 已是最新版本' -Message "当前版本 $latestTag，无需重复更新。" -InstallPath $installedPath
    return
}

# 5. Handle Running Processes Before Update
if ($isInstalled) {
    Write-Host "`n=== 正在同步更新 Mobius ===" -ForegroundColor Cyan
    Write-Host "准备从 $($installedVer) $($installedTag) 同步更新至最新发布版 $latestTag..." -ForegroundColor Cyan

    $runningProcs = Get-Process Mobius -ErrorAction SilentlyContinue
    if ($runningProcs) {
        Write-Host "检测到 Mobius 正在运行，正在请求安全保存工作区并退出..." -ForegroundColor Yellow
        foreach ($p in $runningProcs) {
            try { $null = $p.CloseMainWindow() } catch {}
        }
        $waitCount = 0
        while ((Get-Process Mobius -ErrorAction SilentlyContinue) -and ($waitCount -lt 10)) {
            Start-Sleep -Milliseconds 500
            $waitCount++
        }
        $stillRunning = Get-Process Mobius -ErrorAction SilentlyContinue
        if ($stillRunning) {
            Write-Host "清理残留后台进程..." -ForegroundColor DarkGray
            $stillRunning | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
}

# 6-9. Install, verify the result, and always clean up the download.
$targetDir = if ($installedPath) { $installedPath } else { Join-Path $env:LOCALAPPDATA "Programs\Mobius" }
$mobiusExe = Join-Path $targetDir 'Mobius.exe'
$tempInstaller = Join-Path $env:TEMP ("MobiusSetup-{0}.exe" -f [guid]::NewGuid())
try {
    Write-Host "Downloading Mobius installer ($latestTag)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempInstaller -UseBasicParsing

    Write-Host "Running Mobius Setup (正在静默安装，请稍候)..." -ForegroundColor Cyan
    # Suppress Inno's own launch; only start the app after a verified success.
    $installerArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /MERGETASKS="!runcode" /DIR="' + $targetDir + '"'
    $process = Start-Process -FilePath $tempInstaller -ArgumentList $installerArgs -PassThru
    try {
        $null = $process.Handle
        # Wait for the installer itself, not its entire descendant process tree.
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Mobius 安装失败（退出码 $($process.ExitCode)）。请保留此终端并重试。"
        }
    } finally {
        $process.Dispose()
    }
    if (-not (Test-Path -LiteralPath $mobiusExe -PathType Leaf)) {
        throw "安装器已退出，但未找到 $mobiusExe。未记录更新成功，请重试安装。"
    }
    Set-Content -LiteralPath (Join-Path $targetDir '.mobius-installed-tag') -Value $latestTag -Encoding UTF8 -Force
} catch {
    $global:LASTEXITCODE = 1
    throw
} finally {
    Remove-Item -LiteralPath $tempInstaller -Force -ErrorAction SilentlyContinue
}

# 10. Match VS Code's CLI launch: Electron must not attach to this console.
$previousNoAttachConsole = [Environment]::GetEnvironmentVariable('ELECTRON_NO_ATTACH_CONSOLE', 'Process')
try {
    $env:ELECTRON_NO_ATTACH_CONSOLE = '1'
    Start-Process -FilePath $mobiusExe -WorkingDirectory $targetDir
} catch {
    Write-Warning "Mobius 安装成功，但自动启动失败。请从开始菜单打开。$($_.Exception.Message)"
} finally {
    [Environment]::SetEnvironmentVariable('ELECTRON_NO_ATTACH_CONSOLE', $previousNoAttachConsole, 'Process')
}

if ($isInstalled) {
    $successTitle = 'Mobius 更新成功'
    $successMessage = "已更新至 $latestTag，扩展、配置与工作区数据已保留。"
    Write-Host "`n[Success] Mobius 已成功同步更新至最新版本 ($latestTag)！" -ForegroundColor Green
    Write-Host "您的扩展插件、用户配置与工作区数据均完整保留。" -ForegroundColor DarkGray
} else {
    $successTitle = 'Mobius 安装成功'
    $successMessage = "已安装 $latestTag，可从开始菜单或桌面打开 Mobius。"
    Write-Host "`n[Success] Mobius has been installed successfully ($latestTag)!" -ForegroundColor Green
    Write-Host "You can find Mobius in your Start Menu and Desktop." -ForegroundColor DarkGray
}
Write-Host "Enjoy shipping with Mobius!`n" -ForegroundColor Cyan

Complete-MobiusInstall -Title $successTitle -Message $successMessage -InstallPath $targetDir
