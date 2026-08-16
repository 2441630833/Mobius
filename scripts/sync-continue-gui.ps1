# Build Continue GUI and copy dist into the VS Code extension (no sqlite / native downloads).
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$GuiDir = Join-Path $Root "continue\gui"
$DistDir = Join-Path $GuiDir "dist"
$ExtGuiDir = Join-Path $Root "continue\extensions\vscode\gui"

Write-Host "Building Continue GUI..." -ForegroundColor Cyan
Push-Location $GuiDir
npm run build
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location

if (-not (Test-Path (Join-Path $DistDir "assets\index.js"))) {
    Write-Host "ERROR: continue/gui/dist/assets/index.js not found after build" -ForegroundColor Red
    exit 1
}

Write-Host "Copying GUI dist -> continue/extensions/vscode/gui" -ForegroundColor Cyan
if (Test-Path $ExtGuiDir) {
    Remove-Item $ExtGuiDir -Recurse -Force
}
New-Item -ItemType Directory -Path $ExtGuiDir -Force | Out-Null
Copy-Item -Path (Join-Path $DistDir "*") -Destination $ExtGuiDir -Recurse -Force

Write-Host "[ OK ] Continue GUI synced. Reload the IDE window to pick up changes." -ForegroundColor Green
