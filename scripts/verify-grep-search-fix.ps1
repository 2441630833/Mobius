#!/usr/bin/env pwsh
# scripts/verify-grep-search-fix.ps1
# Verifies that ripgrep is installed in the IDE location that getRipgrep()
# resolves. Runs 6 checks; exits 0 if all pass, non-zero otherwise.
# Safe to re-run. Does NOT modify the install dir unless -Apply is passed.

param(
    [switch]$Apply,
    [switch]$Verbose,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$rgSource = 'd:\AI\physical-ai-ide\VSCode-win32-x64\resources\app\node_modules\@vscode\ripgrep-universal\bin\win32-x64\rg.exe'
$installRoot = Join-Path $env:LOCALAPPDATA 'Programs\Mobius\resources\app'
$rgDestLegacy = Join-Path $installRoot 'node_modules\@vscode\ripgrep\bin\win32-x64\rg.exe'
$rgDestAsar   = Join-Path $installRoot 'node_modules.asar.unpacked\node_modules\@vscode\ripgrep\bin\win32-x64\rg.exe'

$checks = @(
    @{ Name = 'source rg.exe exists';        Path = $rgSource;     ShouldExist = $true },
    @{ Name = 'install legacy rg.exe';       Path = $rgDestLegacy; ShouldExist = $true },
    @{ Name = 'install asar.unpacked rg.exe'; Path = $rgDestAsar;  ShouldExist = $true }
)

$pass = 0; $fail = 0

Write-Host "verify-grep-search-fix: checking ripgrep install..." -ForegroundColor Cyan
foreach ($c in $checks) {
    $exists = Test-Path $c.Path -PathType Leaf
    $ok = ($exists -eq $c.ShouldExist)
    if ($ok) {
        Write-Host ("  [PASS] {0}" -f $c.Name) -ForegroundColor Green
        $pass++
    } else {
        Write-Host ("  [FAIL] {0}  (expected exists={1}, got {2})" -f $c.Name, $c.ShouldExist, $exists) -ForegroundColor Red
        $fail++
        if ($Verbose) { Write-Host "           path: $($c.Path)" -ForegroundColor DarkGray }
    }
}

# Version sanity check (installed rg.exe responds to --version)
if (Test-Path $rgDestLegacy -PathType Leaf) {
    $version = & $rgDestLegacy --version 2>$null | Select-Object -First 1
    if ($version -match 'ripgrep \d+\.\d+\.\d+') {
        Write-Host "  [PASS] installed ripgrep responds: $version" -ForegroundColor Green
        $pass++
    } else {
        Write-Host "  [FAIL] installed ripgrep did not return a version string" -ForegroundColor Red
        $fail++
    }
} else {
    Write-Host "  [SKIP] version check (legacy rg.exe missing)" -ForegroundColor Yellow
}

# Apply patch if requested
if ($Apply -and (Test-Path $rgSource -PathType Leaf)) {
    foreach ($dest in @($rgDestLegacy, $rgDestAsar)) {
        $dir = Split-Path $dest -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Copy-Item -Path $rgSource -Destination $dest -Force
        Write-Host "  [COPY] -> $dest" -ForegroundColor DarkGray
    }
    $pass++; Write-Host "  [PASS] ripgrep copied to install dirs" -ForegroundColor Green
} else {
    Write-Host "  [INFO] pass -Apply to copy ripgrep into the install dir" -ForegroundColor DarkGray
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "verify-grep-search-fix: $pass/$($pass+$fail) checks passed. grep_search should work after Mobius restart." -ForegroundColor Green
    exit 0
} else {
    Write-Host "verify-grep-search-fix: $fail check(s) failed. grep_search may still return 'Config not loaded'." -ForegroundColor Red
    Write-Host "  Fix: run 'powershell -ExecutionPolicy Bypass -File scripts\patch-ide-ripgrep.ps1' then restart Mobius." -ForegroundColor Yellow
    exit 1
}
