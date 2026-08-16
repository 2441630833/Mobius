# Install or repair VS Code root dependencies (gulp, native modules, postinstall)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$env:PYTHONIOENCODING = "utf-8"
cmd /c chcp 65001 > $null 2>&1
$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"

. "$Root\scripts\vs-dev-env.ps1"
Import-VsDevEnvironment | Out-Null

$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if ($vsPath) { $env:vs2022_install = $vsPath }
}

Push-Location $VsCodeDir
$env:NODE_OPTIONS = "--experimental-strip-types"
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"
$env:npm_config_msvs_version = "2026"
$env:npm_config_node_gyp = (Join-Path $Root "scripts\node-gyp-win.js")
$env:MOBIUS_NODE_GYP_BIN = (Join-Path $VsCodeDir "build\npm\gyp\node_modules\node-gyp\bin\node-gyp.js")

Write-Host "Installing VS Code dependencies..." -ForegroundColor Cyan
npm install --ignore-scripts
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }

if (-not (Test-Path "node_modules\gulp\bin\gulp.js")) {
    Write-Host "[FAIL] gulp still missing after npm install --ignore-scripts" -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host "[ OK ] gulp and devDependencies installed" -ForegroundColor Green

Write-Host "Running postinstall (extensions, build/, remote/)..." -ForegroundColor Cyan
$env:VSCODE_FORCE_INSTALL = "1"
node build/npm/postinstall.ts
if ($LASTEXITCODE -ne 0) {
    Write-Host "[WARN] postinstall failed (often remote native modules) -- installing JS deps only..." -ForegroundColor Yellow
    Pop-Location
    & "$Root\scripts\install-vscode-js-deps.ps1"
    if ($LASTEXITCODE -ne 0) { exit 1 }
    Push-Location $VsCodeDir
}
Remove-Item Env:VSCODE_FORCE_INSTALL -ErrorAction SilentlyContinue

# Native modules: install Electron headers then rebuild root @vscode/* addons
Write-Host "Installing Electron headers + rebuilding native modules..." -ForegroundColor Yellow
$env:VSCODE_FORCE_INSTALL = "1"
node build/npm/preinstall.ts
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] preinstall (Electron headers) failed -- see errors above." -ForegroundColor Red
    Pop-Location
    exit 1
}
Pop-Location
& "$Root\scripts\rebuild-native-modules.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }
Push-Location $VsCodeDir
Remove-Item Env:VSCODE_FORCE_INSTALL -ErrorAction SilentlyContinue

if (-not (Test-Path "node_modules\gulp\bin\gulp.js")) {
    Write-Host "[FAIL] gulp still missing after npm install" -ForegroundColor Red
    Pop-Location
    exit 1
}

Write-Host "[ OK ] VS Code dependencies ready (gulp found)" -ForegroundColor Green
Pop-Location
