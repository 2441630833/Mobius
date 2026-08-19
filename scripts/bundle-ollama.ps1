# Mobius -- bundle Ollama runtime (amd64 + arm64) + GLM-OCR (no embeddings)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ollama-common.ps1"

Write-Host "`n=== Bundle Ollama (Mobius) ===" -ForegroundColor Cyan

$version = Get-OllamaVersion
$versionMarker = Get-OllamaBundledVersionFile

Initialize-OllamaDirectories

$versionMismatch = $false
if (Test-Path $versionMarker) {
    $bundledVersion = (Get-Content $versionMarker -Raw).Trim()
    if ($bundledVersion -ne $version) {
        Write-Host "Upgrading bundled Ollama $bundledVersion -> $version" -ForegroundColor Yellow
        $versionMismatch = $true
    }
} else {
    $versionMismatch = $true
}

if ($versionMismatch) {
    foreach ($arch in $script:OllamaSupportedArches) {
        $binDir = Get-OllamaBinDir -Arch $arch
        if (Test-Path $binDir) {
            Remove-Item -Recurse -Force $binDir
        }
    }
}

foreach ($arch in $script:OllamaSupportedArches) {
    if ((Test-OllamaArchBundled -Arch $arch) -and -not $versionMismatch) {
        Write-Host "[ OK ] Ollama v$version ($arch) already bundled at $(Get-OllamaBinDir -Arch $arch)" -ForegroundColor Green
        continue
    }

    Write-Host "`n--- Bundling Windows $arch ---" -ForegroundColor Cyan
    Install-OllamaArchBundle -Arch $arch -Version $version
}

Set-Content -Path $versionMarker -Value $version -NoNewline

Write-Host "`nStarting bundled Ollama ($(Get-WindowsCpuArch)) to pull OCR model..." -ForegroundColor Cyan
Start-BundledOllamaServer | Out-Null
Remove-OllamaRetiredModels
Ensure-OllamaOcrModel

if (-not (Test-OllamaOcrModel)) {
    Write-Host "[FAIL] OCR model $script:OllamaOcrModel not available" -ForegroundColor Red
    exit 1
}
Write-Host "[ OK ] Local OCR model ready ($script:OllamaOcrModel)" -ForegroundColor Green

$Root = Get-ProjectRoot
& (Join-Path $PSScriptRoot "ensure-minilm.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $PSScriptRoot "sync-continue-config.ps1")

Write-Host "`n=== Ollama Bundle Complete ===" -ForegroundColor Green
foreach ($arch in $script:OllamaSupportedArches) {
    Write-Host "Runtime ($arch): $(Get-OllamaBinDir -Arch $arch)" -ForegroundColor White
}
Write-Host "Models  : $(Get-OllamaModelsDir) (OCR only; nomic-embed-text retired)" -ForegroundColor White
Write-Host "OCR     : $script:OllamaOcrModel @ $script:OllamaApiBase" -ForegroundColor White
Write-Host "Embed   : built-in MiniLM ONNX (transformers.js)" -ForegroundColor White
Write-Host "Launch  : npm start (auto-picks bin-$(Get-WindowsCpuArch))`n" -ForegroundColor Cyan
