#!/usr/bin/env pwsh
# scripts/install-git-hooks.ps1
# One-time setup: point this clone's core.hooksPath at the version-controlled
# .githooks/ directory and lock commit encoding to UTF-8. Idempotent -- safe to
# re-run after a `git clone` or a `git pull` that updates .githooks/*.

param(
    [switch]$Verbose
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Set-LocalGitConfig {
    param([string]$Key, [string]$Value)
    $current = git config --local --get $Key 2>$null
    if ($current -eq $Value) {
        if ($Verbose) { Write-Host "  [skip] $Key = $Value (already set)" -ForegroundColor DarkGray }
        return
    }
    git config --local $Key $Value
    Write-Host "  [set ] $Key = $Value" -ForegroundColor Green
}

Write-Host "install-git-hooks: configuring repo at $(Get-Location)" -ForegroundColor Cyan

# 1. Point git at the version-controlled hooks directory
Set-LocalGitConfig 'core.hooksPath' '.githooks'

# 2. Lock commit-message encoding to UTF-8 (the cp936 mojibake trap)
Set-LocalGitConfig 'i18n.commitencoding' 'utf-8'
Set-LocalGitConfig 'i18n.logoutputencoding' 'utf-8'

# 3. Auto-include the repo-root .gitconfig (core.hooksPath + i18n.* live there)
$includePath = '../.gitconfig'
$currentInclude = git config --local --get 'include.path' 2>$null
if ($currentInclude -ne $includePath) {
    git config --local include.path $includePath
    Write-Host "  [set ] include.path = $includePath" -ForegroundColor Green
} elseif ($Verbose) {
    Write-Host "  [skip] include.path = $includePath (already set)" -ForegroundColor DarkGray
}

# 4. Sanity-check: the two hooks must exist and be executable
$requiredHooks = @('commit-msg', 'pre-commit')
foreach ($h in $requiredHooks) {
    $p = Join-Path '.githooks' $h
    if (-not (Test-Path $p -PathType Leaf)) {
        Write-Host "  [ERR ] missing hook file: $p" -ForegroundColor Red
        exit 1
    }
    # PowerShell does not need +x on Windows; on POSIX git will chmod at install
    # time. We just check the file is non-empty.
    $size = (Get-Item $p).Length
    if ($size -lt 100) {
        Write-Host "  [WARN] $p is suspiciously small ($size bytes)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "install-git-hooks: DONE." -ForegroundColor Green
Write-Host "  - Hooks will run on every `git commit`."
Write-Host "  - To bypass a hook once: git commit --no-verify"
Write-Host "  - To uninstall: git config --local --unset core.hooksPath"
