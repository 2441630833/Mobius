# Serve Mobius web front end
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$WebDir = Join-Path $Root "web"
$Port = if ($env:WEB_PORT) { $env:WEB_PORT } else { 5173 }

if (-not (Test-Path $WebDir)) {
    Write-Host "Missing web/ directory" -ForegroundColor Red
    exit 1
}

Write-Host "Mobius web UI: http://localhost:$Port/web/" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor DarkGray

Push-Location $Root
try {
    if (Get-Command npx -ErrorAction SilentlyContinue) {
        npx --yes serve -l $Port .
    } elseif (Get-Command python -ErrorAction SilentlyContinue) {
        python -m http.server $Port
    } else {
        Write-Host "Install Node.js or Python to serve the web UI." -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}
