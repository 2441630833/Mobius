# Download YosysHQ OSS CAD Suite into tools/oss-cad-suite (Verilator + g++/perl).
#
# Chip mode's fpga_lint / fpga_simulate need a host Verilator. A Windows Verilator
# is not one exe: --cc --build needs g++ and VERILATOR_ROOT. The portable suite
# is the same class of download as Godot (tools/godot/), ~570 MB, gitignored.
#
#   .\scripts\setup-oss-cad-suite.ps1            # install if missing
#   .\scripts\setup-oss-cad-suite.ps1 -Force     # re-download even if present
param(
    [switch]$Force,
    [switch]$Detect
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $PSScriptRoot
$VersionFile = Join-Path $Root "config\oss-cad-suite.version"
$Dest = Join-Path $Root "tools\oss-cad-suite"
$Marker = Join-Path $Dest ".bundled-version"

function Read-PinnedVersion {
    if (-not (Test-Path -LiteralPath $VersionFile)) {
        throw "Missing $VersionFile"
    }
    return (Get-Content -LiteralPath $VersionFile -Raw).Trim()
}

function Test-SuiteReady([string]$dir) {
    $bin = Join-Path $dir "bin"
    $verilator = @(
        (Join-Path $bin "verilator_bin.exe"),
        (Join-Path $bin "verilator.exe"),
        (Join-Path $bin "verilator")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    return [bool]$verilator
}

function Get-AssetName([string]$version) {
    $compact = $version.Replace("-", "")
    return "oss-cad-suite-windows-x64-$compact.tgz"
}

function Get-AssetUrls([string]$version, [string]$name) {
    $github = "https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$version/$name"
    $urls = @()
    if ($env:OSS_CAD_SUITE_URL) { $urls += $env:OSS_CAD_SUITE_URL }
    # GitHub releases are often slow from CN; try a prefix proxy first.
    $urls += "https://gh-proxy.com/https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$version/$name"
    $urls += "https://ghfast.top/https://github.com/YosysHQ/oss-cad-suite-build/releases/download/$version/$name"
    $urls += $github
    return $urls | Select-Object -Unique
}

$Version = Read-PinnedVersion
Write-Host "OSS CAD Suite $Version -> $Dest" -ForegroundColor Cyan

if ($Detect) {
    if (Test-SuiteReady $Dest) {
        Write-Host "OK  bundled Verilator at $Dest\bin" -ForegroundColor Green
        exit 0
    }
    Write-Host "WARN suite not installed. Run: npm run chip:cad-suite" -ForegroundColor Yellow
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
    Write-Host "Upgrading bundled suite $have -> $Version" -ForegroundColor Yellow
}

$zipName = Get-AssetName $Version
$urls = Get-AssetUrls $Version $zipName
$tmpDir = Join-Path $Root "tools\_oss-cad-download"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$archive = Join-Path $tmpDir $zipName
if (Test-Path -LiteralPath $archive) {
    Remove-Item -LiteralPath $archive -Force
}

Write-Host "(~570 MB, once. Same idea as npm run godot:setup -- -Install.)" -ForegroundColor DarkGray
$curl = Get-Command curl.exe -ErrorAction SilentlyContinue
$downloaded = $false
foreach ($url in $urls) {
    Write-Host "Downloading $url" -ForegroundColor Cyan
    if ($curl) {
        & curl.exe -L --fail --retry 2 --retry-delay 2 --output $archive $url
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $archive)) {
            $downloaded = $true
            break
        }
    }
    else {
        try {
            Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
            if (Test-Path -LiteralPath $archive) {
                $downloaded = $true
                break
            }
        }
        catch {
            Write-Host "  failed: $_" -ForegroundColor Yellow
        }
    }
    Write-Host "  source failed, trying next mirror..." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
}

if (-not $downloaded) {
    throw "Download failed for every mirror (last: $($urls[-1]))"
}

$extractRoot = Join-Path $tmpDir "extract"
if (Test-Path -LiteralPath $extractRoot) {
    Remove-Item -LiteralPath $extractRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
Write-Host "Extracting ..." -ForegroundColor Cyan
tar -xzf $archive -C $extractRoot
if ($LASTEXITCODE -ne 0) { throw "tar extract failed (exit $LASTEXITCODE)" }

$unpacked = Join-Path $extractRoot "oss-cad-suite"
if (-not (Test-SuiteReady $unpacked)) {
    $nested = Get-ChildItem -Directory $extractRoot | Select-Object -First 1
    if ($nested) { $unpacked = $nested.FullName }
}
if (-not (Test-SuiteReady $unpacked)) {
    throw "Extracted tree has no verilator binary under bin/. Contents: $(Get-ChildItem $extractRoot | ForEach-Object Name)"
}

New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
if (Test-Path -LiteralPath $Dest) {
    Remove-Item -LiteralPath $Dest -Recurse -Force
}
Move-Item -LiteralPath $unpacked -Destination $Dest

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($Marker, $Version + "`n", $utf8NoBom)

Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Installed: $Dest" -ForegroundColor Green
exit 0
