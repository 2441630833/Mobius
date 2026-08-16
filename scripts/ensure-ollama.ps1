# Ensure bundled Ollama is running before IDE launch (embed + OCR only)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ollama-common.ps1"

if (-not (Test-OllamaBundled)) {
    $arch = Get-WindowsCpuArch
    Write-Host "[WARN] Bundled Ollama ($arch) not found -- @codebase indexing / OCR disabled." -ForegroundColor Yellow
    Write-Host "       Run once: npm run bundle:ollama (amd64 ~1.4 GB + arm64 ~15 MB)" -ForegroundColor Gray
    return
}

Initialize-OllamaDirectories

if (-not (Test-OllamaServer)) {
    Start-BundledOllamaServer | Out-Null
    Remove-OllamaRetiredModels -Quiet
}

if (-not (Test-OllamaEmbedModel)) {
    Write-Host "Ollama is running but $script:OllamaEmbedModel is missing -- pulling..." -ForegroundColor Yellow
    Ensure-OllamaEmbedModel -Quiet
}
if (-not (Test-OllamaOcrModel)) {
    Write-Host "Ollama is running but $script:OllamaOcrModel is missing -- pulling..." -ForegroundColor Yellow
    Ensure-OllamaOcrModel -Quiet
}

# Always warm the embed runner -- even when ollama serve was already up.
# Cold starts otherwise refuse the embed endpoint.
$null = Wait-OllamaEmbedReady -Quiet:$false
