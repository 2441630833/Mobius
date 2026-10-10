# Build Mobius for Ubuntu Linux via Docker
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "`n=== Building Mobius for Ubuntu Linux via Docker ===" -ForegroundColor Cyan

# Check Docker
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "[FAIL] Docker is not installed or not in PATH." -ForegroundColor Red
    Write-Host "Please install Docker Desktop (https://www.docker.com/) to build Linux Ubuntu packages on Windows." -ForegroundColor Yellow
    exit 1
}

$DistDir = Join-Path $Root "dist"
if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
}

$env:DOCKER_BUILDKIT = "1"
Write-Host "Starting Docker BuildKit build with Dockerfile.ubuntu..." -ForegroundColor Yellow
Write-Host "Outputs will be exported to: $DistDir`n" -ForegroundColor DarkGray

try {
    & docker build -f Dockerfile.ubuntu --target export -o dist .
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n[ OK ] Docker build succeeded! Artifacts exported to ./dist:" -ForegroundColor Green
        Get-ChildItem -Path $DistDir | Format-Table Name, Length, LastWriteTime
        exit 0
    }
} catch {
    Write-Host "BuildKit export direct target failed, falling back to container run volume export..." -ForegroundColor Yellow
}

Write-Host "Building image mobius-ubuntu..." -ForegroundColor Yellow
& docker build -f Dockerfile.ubuntu -t mobius-ubuntu .
if ($LASTEXITCODE -ne 0) {
    Write-Host "[FAIL] Docker build failed." -ForegroundColor Red
    exit 1
}

Write-Host "Extracting artifacts from container to $DistDir..." -ForegroundColor Yellow
& docker run --rm -v "${DistDir}:/output" mobius-ubuntu cp -r /build/mobius/dist/. /output/

Write-Host "`n[ OK ] Linux Ubuntu artifacts ready in ./dist:" -ForegroundColor Green
Get-ChildItem -Path $DistDir | Format-Table Name, Length, LastWriteTime
