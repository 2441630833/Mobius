# =============================================================================
# Mobius IDE — Windows One-Line Fast Installer
# Usage:
#   irm https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-win.ps1 | iex
# =============================================================================

$ErrorActionPreference = "Stop"
$Repo = "2441630833/Mobius"

Write-Host "`n=== Installing Mobius for Windows ===" -ForegroundColor Cyan

# 1. Detect Architecture
$arch = if ([System.Environment]::Is64BitOperatingSystem) { "x64" } else { "ia32" }
Write-Host "Architecture: $arch" -ForegroundColor DarkGray

# 2. Query Latest Release
Write-Host "Fetching latest release information..." -ForegroundColor Cyan
$downloadUrl = $null
try {
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -UseBasicParsing
    foreach ($rel in $release) {
        $asset = $rel.assets | Where-Object { $_.name -like "Mobius-Setup-*-win32-$arch.exe" -or $_.name -like "MobiusSetup.exe" } | Select-Object -First 1
        if ($asset) {
            $downloadUrl = $asset.browser_download_url
            break
        }
    }
} catch {
    # Fallback to direct latest known release
}

if (-not $downloadUrl) {
    $downloadUrl = "https://github.com/$Repo/releases/download/v1.0.4/Mobius-Setup-1.126.0-win32-x64.exe"
}

Write-Host "Download URL: $downloadUrl" -ForegroundColor DarkGray

# 3. Download Installer
$tempInstaller = Join-Path $env:TEMP "MobiusSetup.exe"
Write-Host "Downloading Mobius installer..." -ForegroundColor Cyan
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $downloadUrl -OutFile $tempInstaller -UseBasicParsing

# 4. Run Installer
Write-Host "Running Mobius Setup..." -ForegroundColor Cyan
# Silent user install by default
$process = Start-Process -FilePath $tempInstaller -ArgumentList "/SILENT /SP-" -PassThru -Wait

# 5. Clean up
Remove-Item -Path $tempInstaller -Force -ErrorAction SilentlyContinue

Write-Host "`nMobius has been installed successfully!" -ForegroundColor Green
Write-Host "You can find Mobius in your Start Menu and Desktop." -ForegroundColor Gray
Write-Host "Enjoy shipping with Mobius!`n" -ForegroundColor Cyan
