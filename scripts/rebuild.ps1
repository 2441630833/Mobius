# Clean rebuild -- remove VS Code deps and run full build
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"
$NodeModules = Join-Path $VsCodeDir "node_modules"

Write-Host "`n=== Clean Rebuild Mobius ===" -ForegroundColor Cyan
Write-Host "Close any running Code/Electron windows first.`n" -ForegroundColor Yellow

if (Test-Path $NodeModules) {
    Write-Host "Removing vscode\node_modules..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $NodeModules -ErrorAction SilentlyContinue
    if (Test-Path $NodeModules) {
        Write-Host "Could not remove vscode\node_modules. Close Code/Electron and retry." -ForegroundColor Red
        exit 1
    }
}

& "$Root\scripts\build-vscode.ps1"
exit $LASTEXITCODE
