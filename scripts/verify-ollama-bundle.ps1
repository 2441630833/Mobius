# Verify bundled Ollama is present for both architectures (release / CI)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ollama-common.ps1"

Write-Host "`n=== Verify Bundled Ollama ===" -ForegroundColor Cyan

$expected = Get-OllamaVersion
$marker = Get-OllamaBundledVersionFile
if (-not (Test-Path $marker)) {
    Write-Host "[FAIL] Missing .bundled-version marker" -ForegroundColor Red
    Write-Host "       Run: npm run bundle:ollama" -ForegroundColor Yellow
    exit 1
}
$bundled = (Get-Content $marker -Raw).Trim()
if ($bundled -ne $expected) {
    Write-Host "[FAIL] Bundled Ollama v$bundled does not match config/ollama.version ($expected)" -ForegroundColor Red
    Write-Host "       Run: npm run bundle:ollama" -ForegroundColor Yellow
    exit 1
}

foreach ($arch in $script:OllamaSupportedArches) {
    if (-not (Test-OllamaArchBundled -Arch $arch)) {
        Write-Host "[FAIL] Missing $(Get-OllamaExe -Arch $arch)" -ForegroundColor Red
        Write-Host "       Run: npm run bundle:ollama" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[ OK ] Ollama v$bundled ($arch) at $(Get-OllamaBinDir -Arch $arch)" -ForegroundColor Green
}

if (-not (Test-Path (Join-Path (Get-OllamaModelsDir) "manifests"))) {
    Write-Host "[FAIL] No models in $(Get-OllamaModelsDir)" -ForegroundColor Red
    Write-Host "       Run: npm run setup:ollama" -ForegroundColor Yellow
    exit 1
}
Write-Host "[ OK ] Models directory populated" -ForegroundColor Green

foreach ($relPath in $script:OllamaRetiredManifestDirs) {
    $retired = Join-Path (Get-OllamaModelsDir) "manifests\registry.ollama.ai\$relPath"
    if (Test-Path $retired) {
        Write-Host "[FAIL] Retired model still bundled: $relPath" -ForegroundColor Red
        Write-Host "       Run: npm run bundle:ollama" -ForegroundColor Yellow
        exit 1
    }
}

$currentArch = Get-WindowsCpuArch
Write-Host "This machine: $currentArch (used for live API checks)" -ForegroundColor Gray

if (-not (Test-OllamaServer)) {
    Start-BundledOllamaServer | Out-Null
}

if (-not (Test-OllamaEmbedModel)) {
    Write-Host "[FAIL] $script:OllamaEmbedModel not available" -ForegroundColor Red
    exit 1
}
Write-Host "[ OK ] Embedding model: $script:OllamaEmbedModel" -ForegroundColor Green

if (-not (Test-OllamaOcrModel)) {
    Write-Host "[FAIL] $script:OllamaOcrModel not available" -ForegroundColor Red
    exit 1
}
Write-Host "[ OK ] Local OCR model: $script:OllamaOcrModel" -ForegroundColor Green

if (-not (Test-OllamaEmbedApi)) {
    Write-Host "[FAIL] Embed API check failed" -ForegroundColor Red
    exit 1
}
Write-Host "[ OK ] Embed API at $script:OllamaApiBase ($currentArch)" -ForegroundColor Green

Write-Host "`nBundled Ollama is ready for release (amd64 + arm64).`n" -ForegroundColor Green
