# Wipe the Continue / Mobius codebase index so it rebuilds from scratch.
# The index lives at ~/.continue/index (sqlite + lancedb). It is a regenerable
# cache -- deleting it only costs a fresh full re-index on next launch.
#
# Usage: npm run reset:index
#        powershell -ExecutionPolicy Bypass -File scripts/reset-continue-index.ps1

param(
    # Kill running Mobius processes first. Unsaved editor buffers rely on
    # VS Code hot-exit backups, so there is a small risk of losing them.
    [switch]$Force
)

$ErrorActionPreference = "Continue"
$IndexDir = Join-Path $HOME ".continue\index"

if (-not (Test-Path $IndexDir)) {
    Write-Host "[ OK ] No index directory at $IndexDir - nothing to reset." -ForegroundColor Green
    exit 0
}

$beforeGb = [math]::Round(
    ((Get-ChildItem $IndexDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum) / 1GB,
    2
)

$procs = @(Get-Process -Name "Mobius" -ErrorAction SilentlyContinue)
if ($procs.Count -gt 0) {
    if (-not $Force) {
        Write-Host "[FAIL] Mobius is running ($($procs.Count) processes) and holds the index files open." -ForegroundColor Red
        Write-Host "       Close Mobius and re-run, or pass -Force to terminate it automatically." -ForegroundColor Yellow
        exit 2
    }
    Write-Host "[ .. ] Stopping $($procs.Count) Mobius process(es)..." -ForegroundColor Yellow
    Stop-Process -Name "Mobius" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    $procs = @(Get-Process -Name "Mobius" -ErrorAction SilentlyContinue)
    if ($procs.Count -gt 0) {
        Write-Host "[FAIL] Mobius is still running; aborting to avoid a partial wipe." -ForegroundColor Red
        exit 3
    }
}

# Same-volume rename is instant and survives a locked file better than a delete.
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$trash = Join-Path ([System.IO.Path]::GetTempPath()) "continue-index-$stamp"
try {
    Move-Item -Path $IndexDir -Destination $trash -Force -ErrorAction Stop
} catch {
    Write-Host "[FAIL] Could not move $IndexDir : $($_.Exception.Message)" -ForegroundColor Red
    exit 4
}
Write-Host "[ .. ] Moved $beforeGb GB to $trash"

Remove-Item -Recurse -Force $trash -ErrorAction SilentlyContinue
if (Test-Path $trash) {
    Write-Host "[WARN] Some files survived deletion (still locked): $trash" -ForegroundColor Yellow
    Write-Host "       Delete that folder manually, or it will go away on the next reboot." -ForegroundColor Yellow
    exit 5
}

Write-Host "[ OK ] Cleared $beforeGb GB. Start Mobius to trigger a full re-index." -ForegroundColor Green
exit 0
