param(
    [string]$BuildRoot = "d:\AI\physical-ai-ide\VSCode-win32-x64\resources\app",
    [string]$IdeRoot   = "$env:LOCALAPPDATA\Programs\Mobius\resources\app"
)

$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
    Ship a verified rg.exe to the installed Mobius IDE so the chat agent's
    grep_search tool stops returning "Config not loaded".

.DESCRIPTION
    The built VSCode tree ships ripgrep at the modern path
        @vscode\ripgrep-universal\bin\win32-x64\rg.exe
    but the installed IDE (under %LocalAppData%\Programs\Mobius\resources\app)
    is missing the legacy path that getRipgrep() resolves against:
        @vscode\ripgrep\bin\win32-x64\rg.exe

    This script copies the verified build-output rg.exe into both the legacy
    directory and the .asar.unpacked mirror so either code path resolves.

.PARAMETER BuildRoot
    Path to the built VSCode tree. Defaults to
        d:\AI\physical-ai-ide\VSCode-win32-x64\resources\app

.PARAMETER IdeRoot
    Path to the installed Mobius IDE app dir. Defaults to
        $env:LOCALAPPDATA\Programs\Mobius\resources\app

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts\patch-ide-ripgrep.ps1
#>

$BuildRg     = Join-Path $BuildRoot "node_modules\@vscode\ripgrep-universal\bin\win32-x64\rg.exe"
$LegacyDir   = Join-Path $IdeRoot   "node_modules\@vscode\ripgrep\bin\win32-x64"
$UnpackedDir = Join-Path $IdeRoot   "node_modules.asar.unpacked\node_modules\@vscode\ripgrep\bin\win32-x64"
$Targets = @(
    (Join-Path $LegacyDir   "rg.exe"),
    (Join-Path $UnpackedDir "rg.exe")
)

if (-not (Test-Path $BuildRg)) {
    Write-Host "[FAIL] Source rg.exe not found: $BuildRg" -ForegroundColor Red
    Write-Host "        Run 'npm run compile:safe' first to produce the build." -ForegroundColor Red
    exit 1
}

$ver = & $BuildRg --version 2>&1
if ($LASTEXITCODE -ne 0 -or (($ver -join "`n") -notmatch 'ripgrep')) {
    Write-Host "[FAIL] Source binary did not respond to --version as ripgrep:" -ForegroundColor Red
    Write-Host "        $ver" -ForegroundColor Red
    exit 1
}

foreach ($t in $Targets) {
    $dir = Split-Path -Parent $t
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Copy-Item -Path $BuildRg -Destination $t -Force
    Write-Host "[ OK ] Installed $t" -ForegroundColor Green
}

$verify = & $Targets[0] --version
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Installed rg.exe failed to run" -ForegroundColor Red
    exit 1
}
Write-Host "[ OK ] Verified installed ripgrep responds to --version: $verify" -ForegroundColor Green

Write-Host ""
Write-Host "Restart Mobius to pick up the new rg.exe. The chat agent's grep_search" -ForegroundColor Cyan
Write-Host "tool will then load the legacy path and stop returning 'Config not loaded'." -ForegroundColor Cyan
exit 0
