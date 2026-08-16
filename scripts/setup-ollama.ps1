# Mobius -- verify / refresh bundled Ollama embed + OCR models
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ollama-common.ps1"

Write-Host "`n=== Ollama Embedding + OCR Setup ===" -ForegroundColor Cyan

Assert-OllamaBundled

Write-Host "Bundled Ollama: $(Get-OllamaExe) ($(Get-WindowsCpuArch))" -ForegroundColor Green
Write-Host "Models dir    : $(Get-OllamaModelsDir)" -ForegroundColor Gray

Start-BundledOllamaServer | Out-Null
Remove-OllamaRetiredModels -Quiet
Ensure-OllamaEmbedModel
Ensure-OllamaOcrModel

Write-Host "Verifying embed API..." -ForegroundColor Yellow
if (-not (Test-OllamaEmbedApi)) {
    Write-Host "WARNING: Embed API check failed. Is Ollama still running?" -ForegroundColor Yellow
    exit 1
}
Write-Host "Embed API OK" -ForegroundColor Green

$Root = Get-ProjectRoot
& (Join-Path $PSScriptRoot "sync-continue-config.ps1")

Write-Host "`n=== Ollama Setup Complete ===" -ForegroundColor Green
Write-Host "Embeddings model: local-embed ($script:OllamaEmbedModel)" -ForegroundColor White
Write-Host "Local OCR model : $script:OllamaOcrModel" -ForegroundColor White
Write-Host "Next: reload Continue config in IDE, then re-index codebase`n" -ForegroundColor Cyan
