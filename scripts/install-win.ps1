# =============================================================================
# Mobius IDE - Windows One-Line Fast Installer & Auto-Updater
# Keep this file ASCII without a BOM for both irm | iex and saved PS 5.1 scripts.
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
        Write-Warning "Mobius completed, but Windows notification failed. Keeping terminal open. $($_.Exception.Message)"
        return $false
    }
}

function Complete-MobiusInstall {
    param([string]$Title, [string]$Message, [string]$InstallPath)

    $notified = Show-MobiusToast -Title $Title -Message $Message -InstallPath $InstallPath
    $global:LASTEXITCODE = 0
    if ($notified -and -not $KeepOpen -and $env:MOBIUS_AUTO_CLOSE -ne '0') {
        Write-Host 'Success. Closing terminal in 2 seconds. Set MOBIUS_AUTO_CLOSE=0 to keep it open.' -ForegroundColor Cyan
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
        Write-Host "`n[Update Available] New release: $latestTag ($updateReason)" -ForegroundColor Yellow
    } else {
        Write-Host "`n[Up to Date] Mobius is already up to date ($latestTag)." -ForegroundColor Green
    }
    return
}

# If already up-to-date and not forced, exit gracefully without redundant multi-GB downloads
if (-not $needsUpdate) {
    Write-Host "`n[Up to Date] Mobius is already current ($latestTag)." -ForegroundColor Green
    Write-Host "  - Install path: $installedPath" -ForegroundColor DarkGray
    Write-Host "  - To force reinstallation or repair, run:" -ForegroundColor DarkGray
    Write-Host "    `$env:MOBIUS_FORCE=1; irm https://raw.githubusercontent.com/$Repo/main/scripts/install-win.ps1 | iex`n" -ForegroundColor Yellow
    Write-Host "Launch Mobius: run 'mobius' or open it from the Start Menu." -ForegroundColor Cyan
    Complete-MobiusInstall -Title 'Mobius is up to date' -Message "Current release: $latestTag. No update needed." -InstallPath $installedPath
    return
}

# 5. Handle Running Processes Before Update
if ($isInstalled) {
    Write-Host "`n=== Updating Mobius ===" -ForegroundColor Cyan
    Write-Host "Updating from $($installedVer) $($installedTag) to $latestTag..." -ForegroundColor Cyan

    $runningProcs = Get-Process Mobius -ErrorAction SilentlyContinue
    if ($runningProcs) {
        Write-Host "Mobius is running. Requesting workspace save and exit..." -ForegroundColor Yellow
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
            Write-Host "Closing remaining background processes..." -ForegroundColor DarkGray
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

    Write-Host "Running Mobius Setup (silent installation, please wait)..." -ForegroundColor Cyan
    # Suppress Inno's own launch; only start the app after a verified success.
    $installerArgs = '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /MERGETASKS="!runcode" /DIR="' + $targetDir + '"'
    $process = Start-Process -FilePath $tempInstaller -ArgumentList $installerArgs -PassThru
    try {
        $null = $process.Handle
        # Wait for the installer itself, not its entire descendant process tree.
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Mobius installation failed (exit code $($process.ExitCode)). Keep this terminal and retry."
        }
    } finally {
        $process.Dispose()
    }
    if (-not (Test-Path -LiteralPath $mobiusExe -PathType Leaf)) {
        throw "Installer exited but $mobiusExe was not found. Update was not recorded; retry installation."
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
    Write-Warning "Mobius installed, but launch failed. Open it from the Start Menu. $($_.Exception.Message)"
} finally {
    [Environment]::SetEnvironmentVariable('ELECTRON_NO_ATTACH_CONSOLE', $previousNoAttachConsole, 'Process')
}

if ($isInstalled) {
    $successTitle = 'Mobius updated successfully'
    $successMessage = "Updated to $latestTag. Extensions, settings and workspace data preserved."
    Write-Host "`n[Success] Mobius updated successfully ($latestTag)!" -ForegroundColor Green
    Write-Host "Extensions, settings and workspace data preserved." -ForegroundColor DarkGray
} else {
    $successTitle = 'Mobius installed successfully'
    $successMessage = "Installed $latestTag. Open Mobius from the Start Menu or Desktop."
    Write-Host "`n[Success] Mobius has been installed successfully ($latestTag)!" -ForegroundColor Green
    Write-Host "You can find Mobius in your Start Menu and Desktop." -ForegroundColor DarkGray
}
Write-Host "Enjoy shipping with Mobius!`n" -ForegroundColor Cyan

Complete-MobiusInstall -Title $successTitle -Message $successMessage -InstallPath $targetDir
