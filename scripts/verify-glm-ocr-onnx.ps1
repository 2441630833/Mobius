# Fast asset validation, without downloads, npm installs, or inference.
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
& node "$Root\continue\extensions\vscode\scripts\package-glm-ocr.js" --verify $env:CONTINUE_VSCODE_TARGET
exit $LASTEXITCODE
