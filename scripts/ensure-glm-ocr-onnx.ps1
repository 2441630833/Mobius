# Ensure the same target-specific local OCR bundle used by desktop packaging.
param([switch]$Strict)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$target = $env:CONTINUE_VSCODE_TARGET
if (-not $target) { $target = & node -p "process.platform + '-' + process.arch" }
& node "$Root\continue\extensions\vscode\scripts\package-glm-ocr.js" $target
if ($LASTEXITCODE -ne 0) {
    if ($Strict) { exit 1 }
    Write-Warning 'Local OCR setup failed. Run npm run ensure:glm-ocr to retry.'
    exit 0
}
