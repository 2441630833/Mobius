# Ensure VS Code root native modules are built (required for dev launch)
$ErrorActionPreference = "Stop"

# Force UTF-8 console so MSBuild / cl.exe / node-gyp Chinese output is not mangled
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$env:PYTHONIOENCODING = "utf-8"
cmd /c chcp 65001 > $null 2>&1

$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"

$RequiredNodes = @(
    (Join-Path $VsCodeDir "node_modules\@vscode\policy-watcher\build\Release\vscode-policy-watcher.node"),
    (Join-Path $VsCodeDir "node_modules\@vscode\windows-registry\build\Release\winregistry.node"),
    (Join-Path $VsCodeDir "node_modules\@vscode\spdlog\build\Release\spdlog.node"),
    (Join-Path $VsCodeDir "node_modules\@vscode\sqlite3\build\Release\vscode-sqlite3.node"),
    (Join-Path $VsCodeDir "node_modules\native-keymap\build\Release\keymapping.node"),
    (Join-Path $VsCodeDir "node_modules\node-pty\build\Release\conpty.node")
)

function Test-NativeModulesReady {
    foreach ($node in $RequiredNodes) {
        if (-not (Test-Path $node)) { return $false }
    }
    return $true
}

if (Test-NativeModulesReady) { exit 0 }

Write-Host "Native modules missing -- rebuilding (requires VS C++ + Windows SDK)..." -ForegroundColor Yellow

. "$Root\scripts\vs-dev-env.ps1"
if (-not (Import-VsDevEnvironment)) {
    Write-Host "[FAIL] Could not load Visual Studio environment (vcvars64)." -ForegroundColor Red
    Write-Host "       Install VS 2022/2026 with 'Desktop development with C++'." -ForegroundColor Yellow
    exit 1
}

$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPath) { $env:vs2022_install = $vsPath }
}

$sdkLib = "${env:ProgramFiles(x86)}\Windows Kits\10\Lib"
if (-not (Test-Path $sdkLib)) {
    Write-Host "[FAIL] Windows 10/11 SDK not found (delayimp.lib required for native modules)." -ForegroundColor Red
    Write-Host "       Install: winget install Microsoft.WindowsSDK.10.0.22621" -ForegroundColor Yellow
    Write-Host "       Or via VS Installer: Desktop development with C++ -> Windows 10/11 SDK" -ForegroundColor Yellow
    Write-Host "       Then run: npm run install:vscode" -ForegroundColor Yellow
    exit 1
}

Push-Location $VsCodeDir
$env:NODE_OPTIONS = "--experimental-strip-types"
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"
$env:VSCODE_FORCE_INSTALL = "1"
$env:npm_config_msvs_version = "2026"
$env:npm_config_node_gyp = (Join-Path $Root "scripts\node-gyp-win.js")
$env:MOBIUS_NODE_GYP_BIN = (Join-Path $VsCodeDir "build\npm\gyp\node_modules\node-gyp\bin\node-gyp.js")
$env:npm_command = "ci"

node build/npm/preinstall.ts
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location
& "$Root\scripts\rebuild-native-modules.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }

if (-not (Test-NativeModulesReady)) {
    Write-Host "[FAIL] Native module rebuild incomplete." -ForegroundColor Red
    Write-Host "       Check linker errors above (LNK1181 delayimp.lib = VS env not loaded)." -ForegroundColor Yellow
    Write-Host "       Run: npm run install:vscode" -ForegroundColor Yellow
    exit 1
}

Write-Host "[ OK ] Native modules ready" -ForegroundColor Green
