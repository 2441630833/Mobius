# Check Windows prerequisites for building VS Code OSS
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$VsCodeNvmrc = Join-Path $Root "vscode\.nvmrc"

$ok = $true

Write-Host "`n=== Mobius -- Build Prerequisites ===" -ForegroundColor Cyan

function Test-MinNodeVersion([string]$version, [int]$minMajor, [int]$minMinor) {
    if ($version -match '^(\d+)\.(\d+)') {
        $maj = [int]$Matches[1]
        $min = [int]$Matches[2]
        if ($maj -gt $minMajor) { return $true }
        if ($maj -eq $minMajor -and $min -ge $minMinor) { return $true }
    }
    return $false
}

# Node.js version (VS Code .nvmrc may pin a version not yet in nvm-windows)
$preferredNode = "24.15.0"
if (Test-Path $VsCodeNvmrc) {
    $preferredNode = (Get-Content $VsCodeNvmrc -Raw).Trim().TrimStart('v')
}
$currentNode = (node -v 2>$null).TrimStart('v')

if (-not $currentNode) {
    Write-Host "[FAIL] Node.js not found" -ForegroundColor Red
    $ok = $false
} elseif ((Test-MinNodeVersion $currentNode 24 0) -or (Test-MinNodeVersion $currentNode 22 18)) {
    Write-Host "[ OK ] Node.js v$currentNode" -ForegroundColor Green
} elseif (Test-MinNodeVersion $currentNode 22 15) {
    Write-Host "[ OK ] Node.js v$currentNode (build OK; launch uses isMainModule patch)" -ForegroundColor Green
    Write-Host "       Recommended: nvm install 22.18.0 && nvm use 22.18.0" -ForegroundColor Gray
} else {
    Write-Host "[WARN] Node.js v$currentNode -- use 22.15+ or 24.x" -ForegroundColor Yellow
    Write-Host "       Do NOT double-click nvm.exe -- open PowerShell and run:" -ForegroundColor Gray
    Write-Host "         nvm install 22.18.0" -ForegroundColor Gray
    Write-Host "         nvm use 22.18.0" -ForegroundColor Gray
    Write-Host "       Preferred by VS Code: $preferredNode (may not be in nvm-windows yet)" -ForegroundColor Gray
}

# Visual Studio C++ toolset (required for native modules like @parcel/watcher)
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasCppToolset = $false
$cl = Get-Command cl.exe -ErrorAction SilentlyContinue
if ($cl) {
    $hasCppToolset = $true
    Write-Host "[ OK ] C++ compiler on PATH (cl.exe)" -ForegroundColor Green
} elseif (Test-Path $vsWhere) {
    $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if (-not $vsPath) {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Workload.VCTools -property installationPath 2>$null
    }
    if ($vsPath) {
        $hasCppToolset = $true
        Write-Host "[ OK ] Visual Studio C++ toolset ($vsPath)" -ForegroundColor Green
    }
}
if (-not $hasCppToolset) {
    Write-Host "[FAIL] Visual Studio C++ toolset not found" -ForegroundColor Red
    Write-Host "       Install Visual Studio 2022 with workload:" -ForegroundColor Yellow
    Write-Host "       'Desktop development with C++'" -ForegroundColor Yellow
    Write-Host "       https://visualstudio.microsoft.com/downloads/" -ForegroundColor Gray
    $ok = $false
}

# Windows 10/11 SDK (required by @vscode/gulp-electron for signtool during Electron download)
$windowsSdkBin = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
$clickOnceSignTool = "${env:ProgramFiles(x86)}\Microsoft SDKs\ClickOnce\SignTool\signtool.exe"
$hasSignTool = $false
if (Test-Path $windowsSdkBin) {
    $hasSignTool = @(Get-ChildItem $windowsSdkBin -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue).Count -gt 0
} elseif (Test-Path $clickOnceSignTool) {
    $hasSignTool = $true
}
if ($hasSignTool) {
    if (Test-Path $windowsSdkBin) {
        Write-Host "[ OK ] Windows 10/11 SDK (signtool.exe)" -ForegroundColor Green
    } else {
        Write-Host "[ OK ] signtool via ClickOnce fallback (Windows Kits\10 not installed)" -ForegroundColor Green
    }
} else {
    Write-Host "[FAIL] Windows 10/11 SDK not found" -ForegroundColor Red
    Write-Host "       Required for first Electron download (npm start)." -ForegroundColor Yellow
    Write-Host "       Option A -- Visual Studio Installer:" -ForegroundColor Yellow
    Write-Host "         Modify VS 2022 -> Desktop development with C++ -> Windows 10/11 SDK" -ForegroundColor Gray
    Write-Host "       Option B -- winget (standalone SDK):" -ForegroundColor Yellow
    Write-Host "         winget install Microsoft.WindowsSDK.10.0.22621" -ForegroundColor Gray
    $ok = $false
}

# Python (node-gyp)
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Host "[WARN] Python not on PATH (node-gyp may need it)" -ForegroundColor Yellow
} else {
    Write-Host "[ OK ] Python: $(python --version 2>&1)" -ForegroundColor Green
}

# Continue extension
$extJs = Join-Path $Root "continue\extensions\vscode\out\extension.js"
if (Test-Path $extJs) {
    Write-Host "[ OK ] Continue extension built" -ForegroundColor Green
} else {
    Write-Host "[WARN] Continue extension not built -- run: npm run install:continue" -ForegroundColor Yellow
}

# Bundled Ollama (optional -- required for @codebase indexing)
. "$Root\scripts\ollama-common.ps1"
$cpuArch = Get-WindowsCpuArch
if (Test-OllamaBundled) {
    $marker = Get-OllamaBundledVersionFile
    $ver = if (Test-Path $marker) { (Get-Content $marker -Raw).Trim() } else { "unknown" }
    Write-Host "[ OK ] Bundled Ollama v$ver ($cpuArch) at resources/ollama/bin-$cpuArch" -ForegroundColor Green
    if (Test-OllamaAllArchesBundled -Version $ver) {
        Write-Host "[ OK ] Both amd64 + arm64 runtimes bundled for release" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Only $cpuArch runtime present -- run: npm run bundle:ollama for both arches" -ForegroundColor Yellow
    }
} else {
    Write-Host "[WARN] Bundled Ollama ($cpuArch) not installed -- run: npm run bundle:ollama" -ForegroundColor Yellow
    Write-Host "       @codebase indexing disabled until bundled" -ForegroundColor Gray
}

Write-Host ""
if (-not $ok) {
    Write-Host "Fix the [FAIL] items above, then re-run: npm run build:vscode" -ForegroundColor Red
    exit 1
}

Write-Host "Prerequisites look good." -ForegroundColor Green
exit 0
