# Ensure Xenova all-MiniLM-L6-v2 ONNX weights exist for transformers.js embeddings.
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$OnnxDir = Join-Path $Root "continue\extensions\vscode\models\all-MiniLM-L6-v2\onnx"
$OnnxPath = Join-Path $OnnxDir "model_quantized.onnx"
$MinBytes = 10MB

function Test-MiniLmOnnx {
    if (-not (Test-Path $OnnxPath)) {
        return $false
    }
    return ((Get-Item $OnnxPath).Length -ge $MinBytes)
}

if (Test-MiniLmOnnx) {
    $mb = [math]::Round((Get-Item $OnnxPath).Length / 1MB, 1)
    Write-Host "[ OK ] MiniLM ONNX ready ($mb MB) at $OnnxPath" -ForegroundColor Green
} else {
    New-Item -ItemType Directory -Force -Path $OnnxDir | Out-Null
    $urls = @(
        "https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx",
        "https://hf-mirror.com/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model_quantized.onnx"
    )

    $tmp = Join-Path $OnnxDir "model_quantized.onnx.download"
    Write-Host "Downloading all-MiniLM-L6-v2 ONNX (quantized)..." -ForegroundColor Yellow
    $downloaded = $false
    foreach ($url in $urls) {
        try {
            Write-Host "  $url" -ForegroundColor Gray
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 180
            if ((Test-Path $tmp) -and ((Get-Item $tmp).Length -ge $MinBytes)) {
                Move-Item -Force $tmp $OnnxPath
                $downloaded = $true
                break
            }
        } catch {
            Write-Host "  download failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not $downloaded -or -not (Test-MiniLmOnnx)) {
        Write-Host "[FAIL] Could not download MiniLM ONNX to $OnnxPath" -ForegroundColor Red
        exit 1
    }

    $mb = [math]::Round((Get-Item $OnnxPath).Length / 1MB, 1)
    Write-Host "[ OK ] MiniLM ONNX downloaded ($mb MB)" -ForegroundColor Green
}

# MiniLM worker requires onnxruntime-node with its real napi-v3 layout.
$coreNm = Join-Path $Root "continue\core\node_modules"
$extNm = Join-Path $Root "continue\extensions\vscode\node_modules"
New-Item -ItemType Directory -Force -Path $extNm | Out-Null
foreach ($pkg in @("onnxruntime-node", "onnxruntime-web", "onnxruntime-common")) {
    $from = Join-Path $coreNm $pkg
    $to = Join-Path $extNm $pkg
    if (-not (Test-Path (Join-Path $from "package.json"))) {
        continue
    }
    if (Test-Path (Join-Path $to "package.json")) {
        continue
    }
    Write-Host "Copying $pkg into Continue extension (MiniLM worker)..." -ForegroundColor Yellow
    Copy-Item -Path $from -Destination $to -Recurse -Force
}
Write-Host "[ OK ] onnxruntime-node available to MiniLM worker" -ForegroundColor Green
exit 0
