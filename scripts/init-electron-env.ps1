# Shared Electron download env for package / gulp / ensure-electron.
# - Prefer npmmirror in CN (GitHub releases often ETIMEDOUT)
# - Reuse any local electron-v*-win32-*.zip by seeding @electron/get's mirror cache key
#
# Override:
#   ELECTRON_MIRROR=official   → use GitHub (no mirror)
#   ELECTRON_MIRROR=<url>      → custom mirror
#   ELECTRON_CACHE=<dir>       → custom cache root

param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",

    [string]$VsCodeDir = ""
)

$ErrorActionPreference = "Stop"

if (-not $VsCodeDir) {
    $Root = Split-Path -Parent $PSScriptRoot
    $VsCodeDir = Join-Path $Root "vscode"
}

function Get-MobiusElectronVersion {
    $electronTs = Join-Path $VsCodeDir "build\lib\electron.ts"
    if (Test-Path $electronTs) {
        $m = Select-String -Path $electronTs -Pattern "const electronVersion = '([^']+)'" | Select-Object -First 1
        if ($m) {
            return $m.Matches.Groups[1].Value
        }
    }
    return "42.2.0"
}

function Set-ElectronDownloadMirror {
    if ($env:ELECTRON_MIRROR -eq "official" -or $env:ELECTRON_MIRROR -eq "github") {
        Remove-Item Env:ELECTRON_MIRROR -ErrorAction SilentlyContinue
        Write-Host "Electron mirror: official GitHub (ELECTRON_MIRROR=official)" -ForegroundColor Yellow
        return
    }
    if (-not $env:ELECTRON_MIRROR) {
        # GitHub releases often time out in CN; npmmirror hosts the same artifacts.
        $env:ELECTRON_MIRROR = "https://npmmirror.com/mirrors/electron/"
    }
    if (-not $env:ELECTRON_MIRROR.EndsWith("/")) {
        $env:ELECTRON_MIRROR = "$($env:ELECTRON_MIRROR)/"
    }
    Write-Host "Electron mirror: $env:ELECTRON_MIRROR" -ForegroundColor DarkGray
}

function Ensure-ElectronCacheRoot {
    if (-not $env:ELECTRON_CACHE) {
        $env:ELECTRON_CACHE = Join-Path $env:LOCALAPPDATA "electron\Cache"
    }
    if (-not (Test-Path $env:ELECTRON_CACHE)) {
        New-Item -ItemType Directory -Force -Path $env:ELECTRON_CACHE | Out-Null
    }
    Write-Host "Electron cache: $env:ELECTRON_CACHE" -ForegroundColor DarkGray
}

function Find-LocalElectronZip {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$ElectronArch
    )
    $zipName = "electron-v$Version-win32-$ElectronArch.zip"
    $candidates = @()

    if (Test-Path $env:ELECTRON_CACHE) {
        $candidates += Get-ChildItem -Path $env:ELECTRON_CACHE -Recurse -Filter $zipName -File -ErrorAction SilentlyContinue
    }

    $devElectronDir = Join-Path $VsCodeDir ".build\electron"
    # Unpacked tree is not a zip; still useful as a hint only.

    $found = $candidates |
        Where-Object { $_.Length -gt 1MB } |
        Sort-Object Length -Descending |
        Select-Object -First 1

    if ($found) {
        return $found.FullName
    }
    return $null
}

function Seed-ElectronMirrorCache {
    param(
        [Parameter(Mandatory = $true)][string]$Version,
        [Parameter(Mandatory = $true)][string]$ElectronArch
    )

    if (-not $env:ELECTRON_MIRROR) {
        # Official GitHub path -- existing cache hash already matches; nothing to seed.
        $existing = Find-LocalElectronZip -Version $Version -ElectronArch $ElectronArch
        if ($existing) {
            Write-Host "Electron zip cache hit: $existing" -ForegroundColor DarkGray
        } else {
            Write-Host "No local Electron zip found; gulp will download from GitHub" -ForegroundColor Yellow
        }
        return
    }

    $nodeModulesGet = Join-Path $VsCodeDir "node_modules\@electron\get\dist"
    if (-not (Test-Path (Join-Path $nodeModulesGet "artifact-utils.js"))) {
        Write-Host "[WARN] @electron/get not found; skip cache seed" -ForegroundColor Yellow
        return
    }

    $sourceZip = Find-LocalElectronZip -Version $Version -ElectronArch $ElectronArch
    # @electron/get is ESM-only -- use a temp .mjs seeder that matches its cache key exactly.
    $seedMjs = @"
import path from 'node:path';
import fs from 'node:fs';
import { pathToFileURL } from 'node:url';

const getRoot = process.argv[2];
const version = process.argv[3];
const arch = process.argv[4];
const sourceZip = process.argv[5] || '';

const { getArtifactRemoteURL, getArtifactFileName, getArtifactVersion } = await import(
  pathToFileURL(path.join(getRoot, 'artifact-utils.js')).href
);
const { Cache } = await import(pathToFileURL(path.join(getRoot, 'Cache.js')).href);

const details = {
  version,
  platform: 'win32',
  arch,
  artifactName: 'electron',
  mirrorOptions: process.env.ELECTRON_MIRROR ? { mirror: process.env.ELECTRON_MIRROR } : undefined,
};
details.version = getArtifactVersion(details);
const fileName = getArtifactFileName(details);
const url = await getArtifactRemoteURL(details);
const cache = new Cache(process.env.ELECTRON_CACHE);
const dest = cache.getCachePath(url, fileName);

if (fs.existsSync(dest) && fs.statSync(dest).size > 1024 * 1024) {
  console.log('CACHE_HIT=' + dest);
  process.exit(0);
}
if (!sourceZip || !fs.existsSync(sourceZip)) {
  console.log('CACHE_MISS_NO_SOURCE=' + dest);
  process.exit(0);
}
fs.mkdirSync(path.dirname(dest), { recursive: true });
fs.copyFileSync(sourceZip, dest);
console.log('CACHE_SEEDED=' + dest);
"@

    $tmp = Join-Path $env:TEMP "mobius-seed-electron-cache.mjs"
    Set-Content -Path $tmp -Value $seedMjs -Encoding UTF8

    $nodeDir = $null
    if (Get-Command Resolve-NodeDirectory -ErrorAction SilentlyContinue) {
        $nodeDir = Resolve-NodeDirectory
    }
    $nodeExe = if ($nodeDir -and (Test-Path (Join-Path $nodeDir "node.exe"))) {
        Join-Path $nodeDir "node.exe"
    } else {
        "node"
    }

    # IDE "JavaScript Debug Terminal" sets NODE_OPTIONS=--inspect*; node then writes
    # "Debugger attached." to stderr. With $ErrorActionPreference=Stop, PowerShell
    # treats that stderr as a terminating NativeCommandError and aborts packaging.
    $savedNodeOptions = $env:NODE_OPTIONS
    $savedEap = $ErrorActionPreference
    try {
        if ($env:NODE_OPTIONS) {
            $cleaned = ($env:NODE_OPTIONS -split '\s+' |
                Where-Object { $_ -and $_ -notmatch '^--inspect' -and $_ -notmatch '^--debug' }) -join ' '
            if ($cleaned) { $env:NODE_OPTIONS = $cleaned } else { Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue }
        }
        $ErrorActionPreference = "Continue"
        $output = & $nodeExe $tmp $nodeModulesGet $Version $ElectronArch $(if ($sourceZip) { $sourceZip } else { "" }) 2>&1
        $seedExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedEap
        if ($null -ne $savedNodeOptions) { $env:NODE_OPTIONS = $savedNodeOptions }
        else { Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue }
    }

    if ($seedExit -ne 0) {
        Write-Host "[WARN] Electron cache seed failed: $output" -ForegroundColor Yellow
        return
    }

    $line = (($output | ForEach-Object { "$_" }) -join "`n").Trim()
    if ($line -match 'CACHE_HIT=(.+)$') {
        Write-Host "Electron zip cache hit (mirror key): $($Matches[1])" -ForegroundColor DarkGray
    } elseif ($line -match 'CACHE_SEEDED=(.+)$') {
        Write-Host "Seeded Electron zip into mirror cache: $($Matches[1])" -ForegroundColor Green
        if ($sourceZip) {
            Write-Host "  from: $sourceZip" -ForegroundColor DarkGray
        }
    } elseif ($line -match 'CACHE_MISS_NO_SOURCE=') {
        Write-Host "No local Electron zip to seed; first gulp download will use mirror (~once)" -ForegroundColor Yellow
    } elseif ($line -and $line -notmatch 'Debugger attached|Waiting for the debugger') {
        Write-Host $line
    }
}

# --- main ---
$electronArch = if ($Arch -eq "arm64") { "arm64" } else { "x64" }
$version = Get-MobiusElectronVersion

Write-Host "`n=== Electron download env (v$version win32-$electronArch) ===" -ForegroundColor Cyan
Set-ElectronDownloadMirror
Ensure-ElectronCacheRoot
Seed-ElectronMirrorCache -Version $version -ElectronArch $electronArch
Write-Host "Note: @electron/get still fetches SHASUMS256.txt each run; mirror keeps that fast." -ForegroundColor DarkGray
