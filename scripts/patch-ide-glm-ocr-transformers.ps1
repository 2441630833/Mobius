# Copy @huggingface/transformers (+ @img sharp) next to the GLM-OCR worker
# so installed / staged Mobius can require() it. Does not rebuild the installer.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$fromHf = Join-Path $Root "continue\extensions\vscode\node_modules\@huggingface\transformers"
$fromImg = Join-Path $Root "continue\extensions\vscode\node_modules\@img"
if (-not (Test-Path (Join-Path $fromHf "package.json"))) {
    Write-Host "[FAIL] Source package missing: $fromHf" -ForegroundColor Red
    Write-Host "       Run: npm run ensure:glm-ocr" -ForegroundColor Yellow
    exit 1
}

$targets = @(
    (Join-Path $Root "continue\extensions\vscode\out"),
    (Join-Path $Root "VSCode-win32-x64\resources\app\extensions\continue\out"),
    (Join-Path $env:LOCALAPPDATA "Programs\Mobius\resources\app\extensions\continue\out")
) | Where-Object { Test-Path $_ }

function Copy-Pkg {
    param([string]$From, [string]$DestParent, [string]$Rel)
    $to = Join-Path $DestParent $Rel
    $parent = Split-Path -Parent $to
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    Write-Host "Copy $Rel -> $parent" -ForegroundColor Yellow
    robocopy $From $to /E /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) {
        throw "robocopy failed ($LASTEXITCODE) $From -> $to"
    }
}

if (-not $targets.Count) {
    Write-Host "[WARN] No Continue extension folders to patch" -ForegroundColor Yellow
    exit 0
}

foreach ($root in $targets) {
    $nm = Join-Path $root "node_modules"
    Copy-Pkg -From $fromHf -DestParent $nm -Rel "@huggingface\transformers"
    if (Test-Path $fromImg) {
        Copy-Pkg -From $fromImg -DestParent $nm -Rel "@img"
    }
}

Write-Host "[ OK ] GLM-OCR @huggingface/transformers patched into $($targets.Count) tree(s)" -ForegroundColor Green
exit 0
