# Ensure onnx-community/GLM-OCR-ONNX (q4f16) weights exist for Agents OCR preprocess.
param(
    [switch]$Strict
)
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ModelDir = Join-Path $Root "continue\extensions\vscode\models\onnx-community\GLM-OCR-ONNX"
$OnnxDir = Join-Path $ModelDir "onnx"

$RootFiles = @(
    "config.json",
    "generation_config.json",
    "preprocessor_config.json",
    "processor_config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "chat_template.jinja"
)

$OnnxFiles = @(
    "vision_encoder_q4f16.onnx",
    "vision_encoder_q4f16.onnx_data",
    "embed_tokens_q4f16.onnx",
    "embed_tokens_q4f16.onnx_data",
    "decoder_model_merged_q4f16.onnx",
    "decoder_model_merged_q4f16.onnx_data"
)

function Test-GlmOcrOnnx {
    foreach ($rel in $RootFiles) {
        $p = Join-Path $ModelDir $rel
        if (-not (Test-Path $p)) { return $false }
    }
    foreach ($rel in $OnnxFiles) {
        $p = Join-Path $OnnxDir $rel
        if (-not (Test-Path $p)) { return $false }
        if ($rel -like "*.onnx_data" -and (Get-Item $p).Length -lt 10MB) { return $false }
    }
    return $true
}

function Download-ModelFile {
    param(
        [string]$RelativePath,
        [string]$Destination
    )
    $urls = @(
        "https://huggingface.co/onnx-community/GLM-OCR-ONNX/resolve/main/$RelativePath",
        "https://hf-mirror.com/onnx-community/GLM-OCR-ONNX/resolve/main/$RelativePath"
    )
    $destDir = Split-Path -Parent $Destination
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
    $tmp = "$Destination.download"
    foreach ($url in $urls) {
        try {
            Write-Host "  $url" -ForegroundColor Gray
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 600
            if ((Test-Path $tmp) -and (Get-Item $tmp).Length -gt 0) {
                Move-Item -Force $tmp $Destination
                return $true
            }
        } catch {
            Write-Host "  download failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        }
    }
    return $false
}

if (Test-GlmOcrOnnx) {
    $decoder = Join-Path $OnnxDir "decoder_model_merged_q4f16.onnx_data"
    $mb = [math]::Round((Get-Item $decoder).Length / 1MB, 1)
    Write-Host "[ OK ] GLM-OCR ONNX ready (~$mb MB decoder weights) at $ModelDir" -ForegroundColor Green
} else {
    Write-Host "Downloading GLM-OCR ONNX (q4f16, ~650 MB total)..." -ForegroundColor Yellow
    foreach ($rel in $RootFiles) {
        $dest = Join-Path $ModelDir $rel
        if (Test-Path $dest) { continue }
        Write-Host "  $rel" -ForegroundColor Cyan
        if (-not (Download-ModelFile -RelativePath $rel -Destination $dest)) {
            Write-Host "[FAIL] Could not download $rel" -ForegroundColor Red
            if ($Strict) { exit 1 }
            Write-Host "[WARN] GLM-OCR ONNX incomplete -- Agents OCR disabled until: npm run ensure:glm-ocr" -ForegroundColor Yellow
            exit 0
        }
    }
    foreach ($rel in $OnnxFiles) {
        $dest = Join-Path $OnnxDir $rel
        if (Test-Path $dest) { continue }
        Write-Host "  onnx/$rel" -ForegroundColor Cyan
        if (-not (Download-ModelFile -RelativePath "onnx/$rel" -Destination $dest)) {
            Write-Host "[FAIL] Could not download onnx/$rel" -ForegroundColor Red
            if ($Strict) { exit 1 }
            Write-Host "[WARN] GLM-OCR ONNX incomplete -- Agents OCR disabled until: npm run ensure:glm-ocr" -ForegroundColor Yellow
            exit 0
        }
    }
    if (-not (Test-GlmOcrOnnx)) {
        Write-Host "[FAIL] GLM-OCR ONNX verification failed under $ModelDir" -ForegroundColor Red
        if ($Strict) { exit 1 }
        Write-Host "[WARN] GLM-OCR ONNX incomplete -- Agents OCR disabled until: npm run ensure:glm-ocr" -ForegroundColor Yellow
        exit 0
    }
    Write-Host "[ OK ] GLM-OCR ONNX downloaded" -ForegroundColor Green
}

# GLM-OCR worker requires native deps beside the Continue extension.
$coreNm = Join-Path $Root "continue\core\node_modules"
$extNm = Join-Path $Root "continue\extensions\vscode\node_modules"
New-Item -ItemType Directory -Force -Path $extNm | Out-Null

function Invoke-Npm {
    param(
        [string]$Directory,
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$NpmArgs
    )
    Push-Location $Directory
    try {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & npm @NpmArgs 2>&1 | ForEach-Object {
            $line = "$_"
            if ($line -match '^\s*npm warn\b') {
                Write-Host $line -ForegroundColor DarkYellow
            } else {
                Write-Host $line
            }
        }
        if ($LASTEXITCODE -ne 0) {
            throw "npm $($NpmArgs -join ' ') failed with exit code $LASTEXITCODE"
        }
    } finally {
        $ErrorActionPreference = $prevEap
        Pop-Location
    }
}

Invoke-Npm (Join-Path $Root "continue\core") install --include=optional "@img/sharp-win32-x64@0.34.5" --no-save
Invoke-Npm (Join-Path $Root "continue\core") rebuild sharp onnxruntime-node "@huggingface/transformers"

function Sync-NativePackage {
    param([string]$Name)
    $from = Join-Path $coreNm $Name
    $to = Join-Path $extNm $Name
    if (-not (Test-Path (Join-Path $from "package.json"))) {
        return
    }
    if (Test-Path $to) {
        Remove-Item -Recurse -Force $to
    }
    Write-Host "Syncing $Name into Continue extension (GLM-OCR worker)..." -ForegroundColor Yellow
    Copy-Item -Path $from -Destination $to -Recurse -Force
}

function Sync-SharpPlatformPackages {
    $imgFrom = Join-Path $coreNm "@img"
    if (-not (Test-Path $imgFrom)) {
        return
    }
    foreach ($targetRoot in @(
        (Join-Path $extNm "@img"),
        (Join-Path $extNm "@huggingface\transformers\node_modules\@img")
    )) {
        New-Item -ItemType Directory -Force -Path $targetRoot | Out-Null
        foreach ($pkg in @("sharp-win32-x64", "colour")) {
            $from = Join-Path $imgFrom $pkg
            $to = Join-Path $targetRoot $pkg
            if (-not (Test-Path (Join-Path $from "package.json"))) {
                continue
            }
            if (Test-Path $to) {
                Remove-Item -Recurse -Force $to
            }
            Write-Host "Syncing @img/$pkg -> $targetRoot (GLM-OCR sharp)..." -ForegroundColor Yellow
            Copy-Item -Path $from -Destination $to -Recurse -Force
        }
    }
}

foreach ($pkg in @("@huggingface/transformers")) {
    Sync-NativePackage $pkg
}
Sync-SharpPlatformPackages

$extTransformers = Join-Path $extNm "@huggingface\transformers\package.json"
$sharpPkg = Join-Path $extNm "@huggingface\transformers\node_modules\sharp\package.json"
$sharpPlatform = Join-Path $extNm "@img\sharp-win32-x64\package.json"
$sharpPlatformVersion = $null
if (Test-Path $sharpPlatform) {
    $sharpPlatformVersion = (Get-Content $sharpPlatform | ConvertFrom-Json).version
}
$sharpVersion = $null
if (Test-Path $sharpPkg) {
    $sharpVersion = (Get-Content $sharpPkg | ConvertFrom-Json).version
}
$ortNative = Get-ChildItem -Path (Join-Path $extNm "@huggingface\transformers\node_modules\onnxruntime-node\bin") -Filter "*.node" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not (Test-Path $extTransformers)) {
    Write-Host "[WARN] @huggingface/transformers missing in Continue extension after sync" -ForegroundColor Yellow
    if ($Strict) { exit 1 }
} elseif (-not (Test-Path $sharpPkg)) {
    Write-Host "[WARN] GLM-OCR sharp package missing under @huggingface/transformers (run npm install in continue/core)" -ForegroundColor Yellow
    if ($Strict) { exit 1 }
} elseif (-not (Test-Path $sharpPlatform)) {
    Write-Host "[WARN] @img/sharp-win32-x64 missing in Continue extension (sharp OCR will fail at runtime)" -ForegroundColor Yellow
    Write-Host "       Run: cd continue/core && npm install --include=optional @img/sharp-win32-x64@0.34.5" -ForegroundColor Yellow
    if ($Strict) { exit 1 }
} elseif ($sharpVersion -and $sharpPlatformVersion -and $sharpVersion -ne $sharpPlatformVersion) {
    Write-Host "[WARN] sharp version mismatch: sharp@$sharpVersion vs @img/sharp-win32-x64@$sharpPlatformVersion" -ForegroundColor Yellow
    if ($Strict) { exit 1 }
} elseif (-not $ortNative) {
    Write-Host "[WARN] GLM-OCR onnxruntime-node native binary missing after sync" -ForegroundColor Yellow
    if ($Strict) { exit 1 }
} else {
    Write-Host "[ OK ] GLM-OCR worker native deps available" -ForegroundColor Green
}
exit 0
