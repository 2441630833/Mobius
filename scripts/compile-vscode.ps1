# Incremental VS Code compile (client + extensions)
$ErrorActionPreference = "Stop"

# Force UTF-8 console so MSBuild / cl.exe / tsc Chinese output is not mangled
# (system default is cp936/GBK; Node and MSBuild emit UTF-8).
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$env:PYTHONIOENCODING = "utf-8"
$env:LANG = "en_US.UTF-8"
cmd /c chcp 65001 > $null 2>&1

$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"

& "$Root\scripts\sync-brand-assets.ps1"

if (-not (Test-Path (Join-Path $VsCodeDir "node_modules"))) {
    Write-Host "VS Code dependencies missing. Run: npm run build:vscode" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path (Join-Path $VsCodeDir "node_modules\gulp\bin\gulp.js"))) {
    Write-Host "VS Code install incomplete (gulp missing). Run: npm run install:vscode" -ForegroundColor Red
    exit 1
}

$selfhostDeps = Join-Path $VsCodeDir ".vscode\extensions\vscode-selfhost-test-provider\node_modules\istanbul-to-vscode\package.json"
if (-not (Test-Path $selfhostDeps)) {
    Write-Host "VS Code extension deps incomplete. Run: npm run install:vscode:js" -ForegroundColor Red
    exit 1
}

Push-Location $VsCodeDir
$env:NODE_OPTIONS = "--experimental-strip-types"
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"

Write-Host "Compiling VS Code (NODE_OPTIONS=$env:NODE_OPTIONS)..." -ForegroundColor Cyan
npm run compile-client
if ($LASTEXITCODE -ne 0) { Pop-Location; exit $LASTEXITCODE }
Write-Host "Compiling built-in extensions (git, git-base, ...)..." -ForegroundColor Cyan
npm run gulp compile-extensions
$exitCode = $LASTEXITCODE
Pop-Location
exit $exitCode
