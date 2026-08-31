# Detect / install the Godot engine used by the Mobius Game Dev mode.
# The Continue agent reaches Godot through scripts/godot-mcp-server.js, which
# resolves the binary in this order: GODOT_BIN -> tools/godot/godot.exe ->
# PATH -> common install dirs.
#
# Usage:
#   .\scripts\setup-godot.ps1            # detect + print guidance
#   .\scripts\setup-godot.ps1 -Install   # download Godot 4 into tools/godot/
param([switch]$Install)

$ErrorActionPreference = "Stop"
# GitHub requires TLS 1.2+; Windows PowerShell 5.1 defaults to TLS 1.0.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$Root = Split-Path -Parent $PSScriptRoot
$ToolsGodot = Join-Path $Root "tools\godot"
$GodotExe = Join-Path $ToolsGodot "godot.exe"
$Version = "4.4.1"
$ZipName = "Godot_v$Version-stable_win64.exe.zip"
$DownloadUrl = "https://github.com/godotengine/godot/releases/download/$Version-stable/$ZipName"
# Official win64 zip is tens of MB; a few-MB file is a truncated IWR failure.
$MinZipBytes = 20MB
$MinExeBytes = 40MB

function Test-GodotExe([string]$path) {
    if ($null -eq $path -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $false
    }
    return ((Get-Item -LiteralPath $path).Length -ge $MinExeBytes)
}

function Find-Godot {
    if ($env:GODOT_BIN -and (Test-GodotExe $env:GODOT_BIN)) { return $env:GODOT_BIN }
    if (Test-GodotExe $GodotExe) { return $GodotExe }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd -and (Test-GodotExe $cmd.Source)) { return $cmd.Source }
    $cmd = Get-Command godot4 -ErrorAction SilentlyContinue
    if ($cmd -and (Test-GodotExe $cmd.Source)) { return $cmd.Source }
    $local = Join-Path $env:LOCALAPPDATA "Programs\Godot\Godot.exe"
    if (Test-GodotExe $local) { return $local }
    $pf = Join-Path $env:ProgramFiles "Godot\Godot.exe"
    if (Test-GodotExe $pf) { return $pf }
    $scoop = Join-Path $env:USERPROFILE "scoop\apps\godot\current\godot.exe"
    if (Test-GodotExe $scoop) { return $scoop }
    return $null
}

function Get-GodotZip([string]$url, [string]$archive) {
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
    }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    Write-Host "Downloading $url" -ForegroundColor Cyan
    if ($curl) {
        # Prefer curl: Invoke-WebRequest has truncated this zip to a few MB on Windows.
        & curl.exe -L --fail --retry 3 --retry-delay 2 --connect-timeout 30 --output $archive $url
        if ($LASTEXITCODE -ne 0) {
            throw "curl.exe failed downloading Godot (exit $LASTEXITCODE)"
        }
    }
    else {
        Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing -TimeoutSec 600
    }
    if (-not (Test-Path -LiteralPath $archive)) {
        throw "Download produced no file: $archive"
    }
    $len = (Get-Item -LiteralPath $archive).Length
    if ($len -lt $MinZipBytes) {
        Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue
        throw "Downloaded zip is too small ($([math]::Round($len / 1MB, 1)) MB) — likely truncated. Retry with curl.exe available, or download manually from $url"
    }
    Write-Host "  zip OK ($([math]::Round($len / 1MB, 1)) MB)" -ForegroundColor DarkGray
}

function Install-Godot {
    if (Test-GodotExe $GodotExe) {
        Write-Host "Godot already installed at $GodotExe" -ForegroundColor Green
        return
    }
    # Drop undersized leftovers from a previous failed Invoke-WebRequest.
    if ((Test-Path -LiteralPath $GodotExe) -and -not (Test-GodotExe $GodotExe)) {
        Write-Host "Removing undersized leftover: $GodotExe" -ForegroundColor Yellow
        Remove-Item -LiteralPath $GodotExe -Force
    }
    Get-ChildItem -LiteralPath $ToolsGodot -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Length -lt $MinZipBytes) {
            try { Remove-Item -LiteralPath $_.FullName -Force }
            catch { Write-Host "[WARN] Could not remove leftover $($_.Name) (in use)" -ForegroundColor Yellow }
        }
    }

    New-Item -ItemType Directory -Force -Path $ToolsGodot | Out-Null
    $zip = Join-Path $ToolsGodot $ZipName
    Get-GodotZip -url $DownloadUrl -archive $zip
    Write-Host "Extracting ..." -ForegroundColor Cyan
    Expand-Archive -Path $zip -DestinationPath $ToolsGodot -Force
    $extracted = Join-Path $ToolsGodot "Godot_v$Version-stable_win64.exe"
    if (-not (Test-Path -LiteralPath $extracted)) {
        throw "Zip extracted but missing $extracted"
    }
    Move-Item -LiteralPath $extracted -Destination $GodotExe -Force
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    if (-not (Test-GodotExe $GodotExe)) {
        $len = if (Test-Path -LiteralPath $GodotExe) { (Get-Item -LiteralPath $GodotExe).Length } else { 0 }
        throw "Installed godot.exe is too small ($len bytes) — install incomplete"
    }
    Write-Host "Installed: $GodotExe ($([math]::Round((Get-Item $GodotExe).Length / 1MB, 1)) MB)" -ForegroundColor Green
}

if ($Install) {
    Install-Godot
}

$godot = Find-Godot
if ($godot) {
    # Persist the resolved path so the MCP server (which gets a restricted
    # environment from Continue) can find it even when Godot is not on PATH.
    New-Item -ItemType Directory -Force -Path $ToolsGodot | Out-Null
    $pointer = Join-Path $ToolsGodot "godot.path"
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($pointer, $godot, $utf8NoBom)
    Write-Host "Godot found: $godot" -ForegroundColor Green
    & $godot --version 2>&1 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
} else {
    Write-Host "Godot not found." -ForegroundColor Yellow
    Write-Host "Run:  npm run godot:setup -- -Install   (downloads Godot $Version into tools/godot/)" -ForegroundColor Cyan
    Write-Host "Or set GODOT_BIN to an existing Godot 4 executable, then restart the IDE." -ForegroundColor Cyan
}
