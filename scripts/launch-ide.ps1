# Launch Mobius (VS Code fork)
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$env:PYTHONIOENCODING = "utf-8"
cmd /c chcp 65001 > $null 2>&1
$Root = Split-Path -Parent $PSScriptRoot
$CodeBat = Join-Path $Root "vscode\scripts\code.bat"
$ExtJs = Join-Path $Root "continue\extensions\vscode\out\extension.js"
$MainJs = Join-Path $Root "vscode\out\main.js"
$ElectronExe = Join-Path $Root "vscode\.build\electron\Mobius.exe"

if (-not (Test-Path $CodeBat)) {
    Write-Host "VS Code source not found. Expected directory: vscode/" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $ExtJs)) {
    Write-Host "Continue extension not built. Run: npm run install:continue" -ForegroundColor Yellow
    npm run install:continue
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

if (-not (Test-Path $MainJs)) {
    Write-Host "VS Code is not compiled (missing vscode/out/main.js)." -ForegroundColor Red
    Write-Host "Run: npm run build:vscode" -ForegroundColor Yellow
    exit 1
}

# Model config is persisted in .env + ~/.continue/config.yaml after saving in Settings.
# Run `npm run sync:config` manually if you edit .env by hand.
& "$Root\scripts\sync-brand-assets.ps1"
& "$Root\scripts\ensure-electron.ps1"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& "$Root\scripts\ensure-native-modules.ps1"
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& "$Root\scripts\ensure-glm-ocr-onnx.ps1"
& "$Root\scripts\ensure-minilm.ps1"
if ($LASTEXITCODE) { exit $LASTEXITCODE }

Write-Host "Launching Mobius..." -ForegroundColor Cyan
Push-Location (Join-Path $Root "vscode")
# NODE_OPTIONS is for Node build scripts only -- Electron rejects most NODE_OPTIONs at runtime.
Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue
# Leftover from `ELECTRON_RUN_AS_NODE=1` (e.g. ad-hoc Electron-as-Node probes) breaks normal IDE launch.
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"
# Agent tool superset needs GitHub.copilot-chat languageModelTools (read_file, replace_string_in_file, …).
# Keep skipping GitHub.copilot (inline completions) to avoid clashing with Continue autocomplete.
# Set MOBIUS_SKIP_COPILOT=1 to skip both and force Continue-only tool fallback.
if ($env:MOBIUS_SKIP_COPILOT -eq "1") {
    Write-Host "MOBIUS_SKIP_COPILOT=1 -- skipping GitHub.copilot-chat and GitHub.copilot" -ForegroundColor Yellow
    $env:VSCODE_SKIP_BUILTIN_EXTENSIONS = "GitHub.copilot-chat,GitHub.copilot"
} else {
    $env:VSCODE_SKIP_BUILTIN_EXTENSIONS = "GitHub.copilot"
}
# Avoid re-downloading Electron on every launch (rimraf fails if IDE is still running).
if (Test-Path $ElectronExe) {
    $env:VSCODE_SKIP_PRELAUNCH = "1"
}
& .\scripts\code.bat --agents --disable-workspace-trust @args
$exitCode = $LASTEXITCODE
Remove-Item Env:VSCODE_SKIP_PRELAUNCH -ErrorAction SilentlyContinue
Pop-Location
exit $exitCode
