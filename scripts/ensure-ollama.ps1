# Ensure bundled Ollama is running before IDE launch (OCR only).
# Embeddings are in-process transformers.js — do not pull or warm nomic-embed-text.
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ollama-common.ps1"

if (-not (Test-OllamaBundled)) {
    $arch = Get-WindowsCpuArch
    Write-Host "[WARN] Bundled Ollama ($arch) not found -- OCR disabled." -ForegroundColor Yellow
    Write-Host "       Run once: npm run bundle:ollama (amd64 ~1.4 GB + arm64 ~15 MB)" -ForegroundColor Gray
    return
}

Initialize-OllamaDirectories

if (-not (Test-OllamaServer)) {
    Start-BundledOllamaServer | Out-Null
    Remove-OllamaRetiredModels -Quiet
}

if (-not (Test-OllamaOcrModel)) {
    Write-Host "Ollama is running but $script:OllamaOcrModel is missing -- pulling..." -ForegroundColor Yellow
    Ensure-OllamaOcrModel -Quiet
}

Write-Host "[ OK ] Bundled Ollama ready for OCR only (embeddings are in-process)" -ForegroundColor Green
