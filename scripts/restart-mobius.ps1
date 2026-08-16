#!/usr/bin/env pwsh
# scripts/restart-mobius.ps1
# Gracefully stop all running Mobius processes and re-launch Mobius.exe from
# the install dir, preserving any CLI arguments that were originally passed.
# Useful after patching rg.exe into the install dir -- the running process
# caches its module paths and won't pick up the new rg.exe until restarted.

param(
    [int]$StopTimeoutSec = 15,
    [switch]$WhatIf,
    [switch]$NoRelaunch
)

$ErrorActionPreference = 'Stop'
$mobiusExe = Join-Path $env:LOCALAPPDATA 'Programs\Mobius\Mobius.exe'

if (-not (Test-Path $mobiusExe -PathType Leaf)) {
    Write-Host "restart-mobius: Mobius.exe not found at $mobiusExe" -ForegroundColor Red
    exit 1
}

# 1. Find existing Mobius processes
$procs = @(Get-Process -Name 'Mobius' -ErrorAction SilentlyContinue)
if ($procs.Count -eq 0) {
    Write-Host "restart-mobius: no running Mobius process found" -ForegroundColor Yellow
} else {
    Write-Host "restart-mobius: stopping $($procs.Count) Mobius process(es) (timeout=${StopTimeoutSec}s)..." -ForegroundColor Cyan
    foreach ($p in $procs) {
        try {
            if ($WhatIf) {
                Write-Host "  [whatif] would stop PID $($p.Id)" -ForegroundColor DarkGray
            } else {
                Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
                Write-Host "  [stop] PID $($p.Id)" -ForegroundColor Green
            }
        } catch {
            Write-Host "  [warn] failed to stop PID $($p.Id): $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
    if (-not $WhatIf -and $procs.Count -gt 0) {
        $deadline = (Get-Date).AddSeconds($StopTimeoutSec)
        while ((Get-Date) -lt $deadline) {
            $stillRunning = @(Get-Process -Name 'Mobius' -ErrorAction SilentlyContinue)
            if ($stillRunning.Count -eq 0) { break }
            Start-Sleep -Milliseconds 500
        }
        $stragglers = @(Get-Process -Name 'Mobius' -ErrorAction SilentlyContinue)
        if ($stragglers.Count -gt 0) {
            Write-Host "  [warn] $($stragglers.Count) process(es) still alive after timeout, sending final kill" -ForegroundColor Yellow
            $stragglers | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 2
        }
        Write-Host "  [ok] all Mobius processes stopped" -ForegroundColor Green
    }
}

# 2. Re-launch Mobius with the install-path exe
if ($NoRelaunch) {
    Write-Host "restart-mobius: -NoRelaunch set; skipping relaunch" -ForegroundColor DarkGray
    exit 0
}
Write-Host "restart-mobius: launching $mobiusExe" -ForegroundColor Cyan
if ($WhatIf) {
    Write-Host "  [whatif] would Start-Process $mobiusExe" -ForegroundColor DarkGray
} else {
    Start-Process -FilePath $mobiusExe -WorkingDirectory (Split-Path $mobiusExe -Parent)
    Write-Host "  [launch] done" -ForegroundColor Green
}
