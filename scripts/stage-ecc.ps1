# Stage the ECC (Everything Claude Code) agent payload into the packaged Mobius client tree.
#
# Layout in packaged desktop installer:
#   <install>/scripts/ecc-agent-preflight.js
#   <install>/scripts/ecc-cli.js
#   <install>/resources/mobius-ecc/
#       package.json
#       skills/               <- 300+ skills
#       agents/               <- agent profiles
#       manifests/            <- JSON component / profile catalogs
#       rules/                <- coding rules and standards
#       scripts/              <- ecc.js, consult.js, etc.
#       node_modules/         <- production dependencies
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("x64", "arm64")]
    [string]$Arch,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ClientDir = Join-Path (Split-Path -Parent (Join-Path $Root "vscode")) "VSCode-win32-$Arch"
$SourceEcc = Join-Path $Root "ECC"
$Payload = Join-Path $ClientDir "resources\mobius-ecc"
$ClientScripts = Join-Path $ClientDir "scripts"

function Write-Info { param([string]$m) Write-Host "       $m" -ForegroundColor Gray }

Write-Host "`n=== Stage ECC Agent Payload ($Arch client) ===" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $SourceEcc)) {
    Write-Host "[FAIL] Missing ECC source submodule: $SourceEcc" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $ClientDir)) {
    Write-Host "[FAIL] Client build output not found: $ClientDir" -ForegroundColor Red
    Write-Info "Run gulp vscode-win32-$Arch-min-ci first."
    exit 1
}

if ($env:SKIP_ECC_STAGE -eq "1" -and -not $Force) {
    Write-Host "[SKIP] SKIP_ECC_STAGE=1" -ForegroundColor Yellow
    exit 0
}

# Ensure ECC production dependencies are installed before staging
if (-not (Test-Path (Join-Path $SourceEcc "node_modules\js-yaml"))) {
    Write-Host "Installing production dependencies for ECC submodule..." -ForegroundColor Cyan
    Push-Location $SourceEcc
    try {
        npm install --omit=dev --no-audit --no-fund
    } finally {
        Pop-Location
    }
}

# 1. Copy preflight and CLI scripts to <install>/scripts
New-Item -ItemType Directory -Force -Path $ClientScripts | Out-Null
$scriptFiles = @("ecc-agent-preflight.js", "ecc-cli.js")
foreach ($name in $scriptFiles) {
    $src = Join-Path $PSScriptRoot $name
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $ClientScripts $name) -Force
    }
}
Write-Host "[ OK ] scripts/ecc-agent-preflight.js + ecc-cli.js -> $ClientScripts" -ForegroundColor Green

# 2. Stage ECC payload under resources/mobius-ecc
if (Test-Path -LiteralPath $Payload) {
    Remove-Item -LiteralPath $Payload -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $Payload | Out-Null

# Robocopy ECC files excluding git repo and bulky test/docker directories
robocopy $SourceEcc $Payload /E /XD ".git" "tests" "docker" /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) {
    throw "robocopy failed for ECC -> $Payload (exit $LASTEXITCODE)"
}
$global:LASTEXITCODE = 0

# Also mirror preflight scripts into payload/scripts if not already there
$payloadScripts = Join-Path $Payload "scripts"
New-Item -ItemType Directory -Force -Path $payloadScripts | Out-Null
foreach ($name in $scriptFiles) {
    $src = Join-Path $PSScriptRoot $name
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $payloadScripts $name) -Force
    }
}

# 3. Validate staged payload
$required = @(
    (Join-Path $ClientScripts "ecc-agent-preflight.js"),
    (Join-Path $ClientScripts "ecc-cli.js"),
    (Join-Path $Payload "package.json"),
    (Join-Path $Payload "manifests\install-components.json"),
    (Join-Path $Payload "scripts\ecc.js")
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "[FAIL] Staged ECC payload validation failed: $path" -ForegroundColor Red
        exit 1
    }
}

$skillCount = @(Get-ChildItem -Path (Join-Path $Payload "skills") -Filter "SKILL.md" -Recurse -ErrorAction SilentlyContinue).Count
$sizeMb = [math]::Round(
    ((Get-ChildItem -LiteralPath $Payload -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 1
)
Write-Host "[ OK ] ECC payload staged ($sizeMb MB, $skillCount skills under resources/mobius-ecc)" -ForegroundColor Green
