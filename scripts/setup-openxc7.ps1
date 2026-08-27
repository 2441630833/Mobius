# Download FPGAwars openXC7 into tools/openxc7 (nextpnr-xilinx + prjxray on Windows).
#
# Chip mode synthesis for Arty A7-35T needs nextpnr-xilinx and xc7frames2bit.
# YosysHQ OSS CAD Suite already ships yosys.exe on Windows but NOT nextpnr-xilinx
# (only Lattice/Gowin). Docker F4PGA was the Linux workaround. This package is
# the native replacement (~621 MB toolchain + ~25 MB xc7a35tcsg324 chipdb).
#
#   .\scripts\setup-openxc7.ps1            # install if missing
#   .\scripts\setup-openxc7.ps1 -Force     # re-download even if present
param(
    [switch]$Force,
    [switch]$Detect
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $PSScriptRoot
$VersionFile = Join-Path $Root "config\openxc7.version"
$Dest = Join-Path $Root "tools\openxc7"
$Marker = Join-Path $Dest ".bundled-version"
$Chip = "xc7a35tcsg324"

function Read-PinnedVersion {
    if (-not (Test-Path -LiteralPath $VersionFile)) {
        throw "Missing $VersionFile"
    }
    return (Get-Content -LiteralPath $VersionFile -Raw).Trim()
}

function Test-SuiteReady([string]$dir) {
    $bin = Join-Path $dir "bin"
    $pnr = @(
        (Join-Path $bin "nextpnr-xilinx.exe"),
        (Join-Path $bin "nextpnr-xilinx")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    return [bool]$pnr
}

function Get-PlatformAsset([string]$compact) {
    if ($env:OS -eq "Windows_NT") {
        return "apio-openxc7-windows-amd64-$compact.tgz"
    }
    return "apio-openxc7-linux-x86-64-$compact.tgz"
}

function Get-AssetUrls([string]$version, [string]$name) {
    $github = "https://github.com/FPGAwars/tools-openxc7/releases/download/$version/$name"
    $urls = @()
    if ($env:OPENXC7_URL) { $urls += $env:OPENXC7_URL }
    $urls += "https://gh-proxy.com/$github"
    $urls += "https://ghfast.top/$github"
    $urls += $github
    return $urls | Select-Object -Unique
}

function Get-Archive([string[]]$urls, [string]$archive) {
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force
    }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    foreach ($url in $urls) {
        Write-Host "Downloading $url" -ForegroundColor Cyan
        if ($curl) {
            & curl.exe -L --fail --retry 2 --retry-delay 2 --output $archive $url
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $archive)) {
                return
            }
        }
        else {
            try {
                Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
                if (Test-Path -LiteralPath $archive) { return }
            }
            catch {
                Write-Host "  failed: $_" -ForegroundColor Yellow
            }
        }
        Write-Host "  source failed, trying next mirror..." -ForegroundColor Yellow
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    }
    throw "Download failed for every mirror (last: $($urls[-1]))"
}

function Expand-Tgz([string]$archive, [string]$extractRoot) {
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    tar -xzf $archive -C $extractRoot
    if ($LASTEXITCODE -ne 0) { throw "tar extract failed (exit $LASTEXITCODE): $archive" }
}

$Version = Read-PinnedVersion
$compact = $Version.Replace("-", "")
Write-Host "openXC7 $Version -> $Dest" -ForegroundColor Cyan

if ($Detect) {
    if (Test-SuiteReady $Dest) {
        Write-Host "OK  bundled nextpnr-xilinx at $Dest\bin" -ForegroundColor Green
        exit 0
    }
    Write-Host "WARN openXC7 not installed. Run: npm run chip:openxc7" -ForegroundColor Yellow
    exit 1
}

if (-not $Force -and (Test-SuiteReady $Dest)) {
    $have = ""
    if (Test-Path -LiteralPath $Marker) {
        $have = (Get-Content -LiteralPath $Marker -Raw).Trim()
    }
    if ($have -eq $Version) {
        Write-Host "Already bundled ($Version)." -ForegroundColor Green
        exit 0
    }
    Write-Host "Upgrading bundled openXC7 $have -> $Version" -ForegroundColor Yellow
}

$toolName = Get-PlatformAsset $compact
$chipName = "apio-xilinx-chipdb-$Chip-$compact.bin.tgz"
$tmpDir = Join-Path $Root "tools\_openxc7-download"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

Write-Host "(~621 MB toolchain + ~25 MB $Chip chipdb, once.)" -ForegroundColor DarkGray

$toolArchive = Join-Path $tmpDir $toolName
Get-Archive (Get-AssetUrls $Version $toolName) $toolArchive

$extractRoot = Join-Path $tmpDir "extract"
Write-Host "Extracting toolchain ..." -ForegroundColor Cyan
Expand-Tgz $toolArchive $extractRoot

$unpacked = $extractRoot
if (Test-SuiteReady $extractRoot) {
    $unpacked = $extractRoot
}
else {
    $nested = Get-ChildItem -Directory $extractRoot | Select-Object -First 1
    if ($nested -and (Test-SuiteReady $nested.FullName)) {
        $unpacked = $nested.FullName
    }
    elseif ($nested) {
        $unpacked = $nested.FullName
    }
}
if (-not (Test-SuiteReady $unpacked)) {
    throw "Extracted tree has no nextpnr-xilinx under bin/. Contents: $(Get-ChildItem $extractRoot | ForEach-Object Name)"
}

New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
if (Test-Path -LiteralPath $Dest) {
    Remove-Item -LiteralPath $Dest -Recurse -Force
}
Move-Item -LiteralPath $unpacked -Destination $Dest

$chipArchive = Join-Path $tmpDir $chipName
Get-Archive (Get-AssetUrls $Version $chipName) $chipArchive
$chipExtract = Join-Path $tmpDir "chipdb"
Write-Host "Extracting $Chip chipdb ..." -ForegroundColor Cyan
Expand-Tgz $chipArchive $chipExtract
$chipDest = Join-Path $Dest "chipdb"
New-Item -ItemType Directory -Force -Path $chipDest | Out-Null
Get-ChildItem -Path $chipExtract -Recurse -Filter "*.bin" | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $chipDest $_.Name) -Force
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($Marker, $Version + "`n", $utf8NoBom)

Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Installed: $Dest" -ForegroundColor Green
exit 0
