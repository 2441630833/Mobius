# Build Continue VS Code extension for Mobius (Windows-friendly)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$env:PYTHONIOENCODING = "utf-8"
cmd /c chcp 65001 > $null 2>&1
$Root = Split-Path -Parent $PSScriptRoot
$ContinueDir = Join-Path $Root "continue"
$ExtDir = Join-Path $ContinueDir "extensions\vscode"

if (-not (Test-Path $ExtDir)) {
    Write-Host "Continue not found. Expected directory: continue/extensions/vscode" -ForegroundColor Red
    exit 1
}

Write-Host "`n=== Building Continue for Mobius (Windows) ===" -ForegroundColor Cyan
Write-Host "Skips cross-platform binary/pkg build that fails on Windows.`n" -ForegroundColor Yellow

. "$Root\scripts\vs-dev-env.ps1"
Import-VsDevEnvironment | Out-Null

$env:CONTINUE_VSCODE_TARGET = "win32-x64"
$env:npm_config_msvs_version = "2026"
$env:npm_config_node_gyp = (Join-Path $Root "scripts\node-gyp-win.js")
# SKIP_INSTALLS set to true before prepackage after ensure-sqlite.ps1 runs

Push-Location $ContinueDir

Write-Host "[1/5] Root dependencies..." -ForegroundColor White
# husky prepare is for git hooks only; skip so packaging works without a local husky binary
$env:HUSKY = "0"
npm install --ignore-scripts
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }

Write-Host "[2/5] Packages (fetch, openai-adapters, config-yaml)..." -ForegroundColor White
node ./scripts/build-packages.js
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }

$isRelease = $env:CONTINUE_RELEASE -eq "1"

Write-Host "[3/5] Core..." -ForegroundColor White
Push-Location core
npm install
if ($LASTEXITCODE -ne 0) {
    Write-Host "Core npm install failed (often sharp/libvips GitHub timeout). Retrying with --ignore-scripts..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force node_modules -ErrorAction SilentlyContinue
    npm install --ignore-scripts
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Core dependencies failed to install" -ForegroundColor Red
        Pop-Location
        Pop-Location
        exit 1
    }
}
if ($isRelease) {
    npm run build
    if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }
} else {
    npm link
    if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }
}
Pop-Location

& "$Root\scripts\ensure-sqlite.ps1"
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }

Write-Host "[4/5] GUI..." -ForegroundColor White
Push-Location gui
npm install
if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }
if ($isRelease) {
    npm install file:../core --no-save --ignore-scripts
    if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }
} else {
    npm link @continuedev/core
    if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }
}
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: GUI build failed -- fixes were NOT packaged into the extension" -ForegroundColor Red
    Pop-Location
    Pop-Location
    exit 1
}
Pop-Location

Write-Host "[5/5] VS Code extension (prepackage + esbuild)..." -ForegroundColor White
Push-Location extensions/vscode
npm install --ignore-scripts
if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }
if ($isRelease) {
    # Release: drop npm link artifact; keep devDependencies for prepackage/esbuild (rimraf, esbuild, …)
    if (Test-Path "node_modules/@continuedev/core") {
        Remove-Item -Recurse -Force "node_modules/@continuedev/core"
    }
} else {
    npm link @continuedev/core
    if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }
}

# Ensure sqlite3 binary in extension tree (npm install --ignore-scripts skips native build)
Pop-Location  # back to continue/
& "$Root\scripts\ensure-sqlite.ps1"
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
& "$Root\scripts\ensure-ripgrep.ps1"
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
$env:SKIP_INSTALLS = "true"
Push-Location extensions/vscode

# prepackage: copies GUI, native modules, wasm -- skips remote sqlite when SKIP_INSTALLS=true
npm run prepackage
if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }

# esbuild: creates out/extension.js (required for VS Code to load the extension)
New-Item -ItemType Directory -Force -Path "build" | Out-Null
& "$Root\scripts\ensure-minilm.ps1"
if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }
if ($env:CONTINUE_RELEASE -eq "1") {
    npm run esbuild-base -- --minify
} else {
    npm run esbuild
}
if ($LASTEXITCODE -ne 0) { Pop-Location; Pop-Location; exit 1 }

if (-not (Test-Path "out\extension.js")) {
    Write-Host "ERROR: out/extension.js was not created" -ForegroundColor Red
    Pop-Location; Pop-Location; exit 1
}
if (-not (Test-Path "out\transformersJsEmbedWorker.js")) {
    Write-Host "ERROR: out/transformersJsEmbedWorker.js was not created" -ForegroundColor Red
    Pop-Location; Pop-Location; exit 1
}

Write-Host "Continue extension built: out/extension.js" -ForegroundColor Green
Pop-Location  # extensions/vscode
Pop-Location  # continue/

# Link into VS Code extensions folder
$TargetExt = Join-Path $Root "vscode\extensions\continue"
if (Test-Path $TargetExt) {
    Remove-Item $TargetExt -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Linking Continue -> vscode/extensions/continue" -ForegroundColor Yellow
New-Item -ItemType Junction -Path $TargetExt -Target $ExtDir -Force | Out-Null

# Sync .env -> Continue config
& "$Root\scripts\sync-continue-config.ps1"

Write-Host "`nContinue ready for VS Code fork." -ForegroundColor Green
