# Rebuild VS Code root @vscode/* native addons (called from install/launch scripts)
$ErrorActionPreference = "Stop"

# Force UTF-8 console so MSBuild / cl.exe / node-gyp Chinese output is not mangled
# (system default is cp936/GBK; MSBuild and cl.exe emit UTF-8).
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$env:PYTHONIOENCODING = "utf-8"
cmd /c chcp 65001 > $null 2>&1

$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"
$NodeGyp = Join-Path $Root "scripts\node-gyp-win.js"

$Packages = @(
    "@vscode\policy-watcher",
    "@vscode\windows-registry",
    "@vscode\spdlog",
    "@vscode\windows-mutex",
    "@vscode\windows-process-tree",
    "@vscode\deviceid",
    "@vscode\native-watchdog",
    "@vscode\sqlite3",
    "@vscode\windows-ca-certs",
    "@parcel\watcher",
        "native-is-elevated",
    "native-keymap",
    "node-pty",
    "windows-foreground-love",
    "kerberos"
)

function Import-NpmrcEnv {
    param([string]$NpmrcPath)
    if (-not (Test-Path $NpmrcPath)) { return }
    foreach ($line in Get-Content $NpmrcPath) {
        if ($line -match '^\s*([^#=]+?)=(.*)$') {
            $key = $matches[1].Trim().Replace('-', '_')
            $value = $matches[2].Trim().Trim('"')
            Set-Item -Path "env:npm_config_$key" -Value $value
        }
    }
}
function Test-DelayimpLib {
    if (-not $env:LIB) { return $false }
    foreach ($dir in ($env:LIB -split ';')) {
        if ($dir -and (Test-Path (Join-Path $dir.Trim() "delayimp.lib"))) {
            return $true
        }
    }
    return $false
}

. "$Root\scripts\vs-dev-env.ps1"
if (-not (Import-VsDevEnvironment)) {
    Write-Host "[FAIL] Could not load Visual Studio environment (vcvars64)." -ForegroundColor Red
    Write-Host "       Open 'Developer PowerShell for VS' or install Desktop development with C++." -ForegroundColor Yellow
    exit 1
}

$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPath) { $env:vs2022_install = $vsPath }
}

if (-not (Test-DelayimpLib)) {
    Write-Host "[FAIL] delayimp.lib not found on LIB path." -ForegroundColor Red
    Write-Host "       LIB=$($env:LIB.Substring(0, [Math]::Min(120, $env:LIB.Length)))..." -ForegroundColor Gray
    Write-Host "       Re-open terminal after installing Windows SDK, then run: npm run install:vscode" -ForegroundColor Yellow
    exit 1
}

$env:NODE_OPTIONS = "--experimental-strip-types"
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"
$env:npm_config_msvs_version = "2026"
$env:npm_config_node_gyp = $NodeGyp
$env:MOBIUS_NODE_GYP_BIN = Join-Path $VsCodeDir "build\npm\gyp\node_modules\node-gyp\bin\node-gyp.js"
$env:npm_command = "ci"
Import-NpmrcEnv (Join-Path $VsCodeDir ".npmrc")

Push-Location $VsCodeDir
node build/npm/preinstall.ts
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }

$failed = @()
foreach ($pkg in $Packages) {
    $pkgDir = Join-Path $VsCodeDir "node_modules\$pkg"
    if (-not (Test-Path (Join-Path $pkgDir "binding.gyp"))) { continue }

    Write-Host "Rebuilding $pkg..." -ForegroundColor Cyan
    Push-Location $pkgDir
    node $NodeGyp rebuild
    if ($LASTEXITCODE -ne 0) {
        $failed += $pkg
    } elseif ($pkg -eq "node-pty") {
        node scripts/post-install.js
        if ($LASTEXITCODE -ne 0) { $failed += $pkg }
    }
    Pop-Location
}
Pop-Location

if ($failed.Count -gt 0) {
    Write-Host "[FAIL] Native rebuild failed for: $($failed -join ', ')" -ForegroundColor Red
    exit 1
}

Write-Host "[ OK ] Native modules rebuilt" -ForegroundColor Green
