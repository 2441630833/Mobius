# Ensure @vscode/ripgrep native binary (skipped by npm install --ignore-scripts)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Target = if ($env:CONTINUE_VSCODE_TARGET) { $env:CONTINUE_VSCODE_TARGET } else { "win32-x64" }
$RipgrepDir = Join-Path $Root "continue\extensions\vscode\node_modules\@vscode\ripgrep"
$BinDir = Join-Path $RipgrepDir "bin"
$RgExe = Join-Path $BinDir "rg.exe"

if (-not (Test-Path $RipgrepDir)) {
    Write-Host "  @vscode/ripgrep not installed yet (run npm install in extensions/vscode first)" -ForegroundColor DarkYellow
    exit 0
}

if (Test-Path $RgExe) {
    Write-Host "[ OK ] ripgrep binary already present" -ForegroundColor Green
    exit 0
}

$assets = @{
    "win32-x64"   = "ripgrep-v13.0.0-10-x86_64-pc-windows-msvc.zip"
    "win32-arm64" = "ripgrep-v13.0.0-10-aarch64-pc-windows-msvc.zip"
}

if (-not $assets.ContainsKey($Target)) {
    Write-Host "[FAIL] Unsupported ripgrep target: $Target" -ForegroundColor Red
    exit 1
}

$asset = $assets[$Target]
$releasePath = "microsoft/ripgrep-prebuilt/releases/download/v13.0.0-10/$asset"
$direct = "https://github.com/$releasePath"
$urls = @(
    "https://gh-proxy.org/$direct",
    "https://v4.gh-proxy.org/$direct",
    "https://v6.gh-proxy.org/$direct",
    $direct
)

Write-Host "Preparing ripgrep for $Target..." -ForegroundColor Yellow
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null

$zipPath = Join-Path $env:TEMP "continue-ripgrep-$asset"
$extractDir = Join-Path $env:TEMP "continue-ripgrep-extract"

if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue }

$downloaded = $false
foreach ($url in $urls) {
    Write-Host "Trying download: $url" -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri $url -OutFile $zipPath -TimeoutSec 120 -UseBasicParsing
        if ((Get-Item $zipPath).Length -gt 1000) {
            $downloaded = $true
            break
        }
    } catch {
        Write-Host "  failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

if (-not $downloaded) {
    Write-Host "[FAIL] Could not download ripgrep binary" -ForegroundColor Red
    exit 1
}

Expand-Archive -Path $zipPath -DestinationPath $extractDir -Force
$found = Get-ChildItem $extractDir -Recurse -Filter "rg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $found) {
    Write-Host "[FAIL] rg.exe not found in downloaded archive" -ForegroundColor Red
    exit 1
}

Copy-Item $found.FullName $RgExe -Force
Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue

Write-Host "[ OK ] ripgrep downloaded to $RgExe" -ForegroundColor Green
exit 0
