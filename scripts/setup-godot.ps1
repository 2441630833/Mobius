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

function Test-GodotExe([string]$path) {
    return ($null -ne $path -and (Test-Path -LiteralPath $path -PathType Leaf))
}

function Find-Godot {
    if ($env:GODOT_BIN -and (Test-GodotExe $env:GODOT_BIN)) { return $env:GODOT_BIN }
    if (Test-GodotExe $GodotExe) { return $GodotExe }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $cmd = Get-Command godot4 -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $local = Join-Path $env:LOCALAPPDATA "Programs\Godot\Godot.exe"
    if (Test-GodotExe $local) { return $local }
    $pf = Join-Path $env:ProgramFiles "Godot\Godot.exe"
    if (Test-GodotExe $pf) { return $pf }
    $scoop = Join-Path $env:USERPROFILE "scoop\apps\godot\current\godot.exe"
    if (Test-GodotExe $scoop) { return $scoop }
    return $null
}

function Install-Godot {
    if (Test-GodotExe $GodotExe) {
        Write-Host "Godot already installed at $GodotExe" -ForegroundColor Green
        return
    }
    New-Item -ItemType Directory -Force -Path $ToolsGodot | Out-Null
    $zip = Join-Path $ToolsGodot $ZipName
    Write-Host "Downloading Godot $Version ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $zip -UseBasicParsing
    Write-Host "Extracting ..." -ForegroundColor Cyan
    Expand-Archive -Path $zip -DestinationPath $ToolsGodot -Force
    $extracted = Join-Path $ToolsGodot "Godot_v$Version-stable_win64.exe"
    if (Test-GodotExe $extracted) {
        Move-Item -LiteralPath $extracted -Destination $GodotExe -Force
    }
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
    Write-Host "Installed: $GodotExe" -ForegroundColor Green
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
