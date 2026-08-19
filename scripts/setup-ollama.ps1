# Mobius -- verify / refresh bundled Ollama OCR (embeddings are MiniLM ONNX)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ollama-common.ps1"

Write-Host "`n=== Ollama OCR Setup ===" -ForegroundColor Cyan

Assert-OllamaBundled

Write-Host "Bundled Ollama: $(Get-OllamaExe) ($(Get-WindowsCpuArch))" -ForegroundColor Green
Write-Host "Models dir    : $(Get-OllamaModelsDir)" -ForegroundColor Gray

Start-BundledOllamaServer | Out-Null
Remove-OllamaRetiredModels
Ensure-OllamaOcrModel

if (-not (Test-OllamaOcrModel)) {
    Write-Host "[FAIL] OCR model $script:OllamaOcrModel not available" -ForegroundColor Red
    exit 1
}
Write-Host "[ OK ] Local OCR model: $script:OllamaOcrModel" -ForegroundColor Green

$Root = Get-ProjectRoot
& (Join-Path $PSScriptRoot "ensure-minilm.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "sync-continue-config.ps1")

Write-Host "`n=== Ollama Setup Complete ===" -ForegroundColor Green
Write-Host "Embeddings     : built-in MiniLM ONNX (transformers.js)" -ForegroundColor White
Write-Host "Local OCR model: $script:OllamaOcrModel" -ForegroundColor White
Write-Host "Next: reload Continue config in IDE, then re-index codebase`n" -ForegroundColor Cyan
