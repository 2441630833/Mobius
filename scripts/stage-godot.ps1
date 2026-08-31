# Stage Godot Game mode payload into the packaged Mobius client tree.
#
# Installed IDE has no git checkout. Game mode resolves scripts/godot-mcp-server.js by
# walking up from appRoot (resources/app -> install root) and from resources/mobius-godot.
#
# Layout (both ship so older builds still find install-root scripts/):
#   <install>/scripts/godot-mcp-server.js
#   <install>/game-dev/project.godot
#   <install>/tools/godot/godot.exe     <- when present in the repo (setup-godot -Install)
#   <install>/resources/mobius-godot/   <- self-contained mirror (chip-design pattern)
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("x64", "arm64")]
    [string]$Arch,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ClientDir = Join-Path (Split-Path -Parent (Join-Path $Root "vscode")) "VSCode-win32-$Arch"
$SourceGameDev = Join-Path $Root "game-dev"
$SourceGodotTools = Join-Path $Root "tools\godot"
$SourceGodotExe = Join-Path $SourceGodotTools "godot.exe"
$Payload = Join-Path $ClientDir "resources\mobius-godot"

function Write-Info { param([string]$m) Write-Host "       $m" -ForegroundColor Gray }

Write-Host "`n=== Stage Godot payload ($Arch client) ===" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $SourceGameDev)) {
    Write-Host "[FAIL] Missing source tree: $SourceGameDev" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $ClientDir)) {
    Write-Host "[FAIL] Client build output not found: $ClientDir" -ForegroundColor Red
    Write-Info "Run gulp vscode-win32-$Arch-min-ci first."
    exit 1
}

if ($env:SKIP_GODOT_STAGE -eq "1" -and -not $Force) {
    Write-Host "[SKIP] SKIP_GODOT_STAGE=1" -ForegroundColor Yellow
    exit 0
}

$scriptFiles = @(
    "godot-mcp-server.js",
    "godot-mcp-launcher.js",
    "setup-godot.ps1"
)
foreach ($name in $scriptFiles) {
    $src = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "[FAIL] Missing $src" -ForegroundColor Red
        exit 1
    }
}

Write-Host "Client : $ClientDir" -ForegroundColor Gray
Write-Host "Payload: $Payload" -ForegroundColor Gray

function Copy-GameDevTree {
    param([string]$Dest)
    if (Test-Path -LiteralPath $Dest) {
        Remove-Item -LiteralPath $Dest -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $Dest | Out-Null
    robocopy $SourceGameDev $Dest /E /XD ".godot" /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed for game-dev -> $Dest (exit $LASTEXITCODE)" }
    $global:LASTEXITCODE = 0
}

function Copy-GodotScripts {
    param([string]$DestScripts)
    New-Item -ItemType Directory -Force -Path $DestScripts | Out-Null
    foreach ($name in $scriptFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $DestScripts $name) -Force
    }
}

function Copy-GodotEngine {
    param([string]$DestRoot)
    $dest = Join-Path $DestRoot "tools\godot"
    if (-not (Test-Path -LiteralPath $SourceGodotExe)) {
        Write-Host "[INFO] tools/godot/godot.exe not in repo — engine not staged under $DestRoot" -ForegroundColor DarkGray
        Write-Info "Run: npm run godot:setup -- -Install"
        return $false
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem -LiteralPath $dest -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop }
        catch { Write-Host "[WARN] Could not remove leftover $($_.Name) (in use) — continuing" -ForegroundColor Yellow }
    }
    robocopy $SourceGodotTools $dest /E /XF "*.zip" /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed for tools/godot -> $dest (exit $LASTEXITCODE)" }
    $global:LASTEXITCODE = 0
    $exe = Join-Path $dest "godot.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "Staged tools/godot missing godot.exe at $exe"
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $dest "godot.path"), $exe, $utf8NoBom)
    Write-Host "[ OK ] tools/godot/godot.exe -> $DestRoot" -ForegroundColor Green
    return $true
}

# Install root (resolveGodotPaths walk-up from appRoot depth 2)
$rootScripts = Join-Path $ClientDir "scripts"
Copy-GodotScripts -DestScripts $rootScripts
Copy-GameDevTree -Dest (Join-Path $ClientDir "game-dev")
$engineAtRoot = Copy-GodotEngine -DestRoot $ClientDir
Write-Host "[ OK ] install-root scripts/ + game-dev/" -ForegroundColor Green

# Self-contained payload under resources/
if (Test-Path -LiteralPath $Payload) {
    Remove-Item -LiteralPath $Payload -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $Payload | Out-Null
Copy-GodotScripts -DestScripts (Join-Path $Payload "scripts")
Copy-GameDevTree -Dest (Join-Path $Payload "game-dev")
$engineAtPayload = Copy-GodotEngine -DestRoot $Payload

$marker = [ordered]@{
    name        = "Mobius"
    private     = $true
    description = "Mobius Godot Game mode payload (Star Catcher demo + godot-mcp-server)"
    scripts     = [ordered]@{
        "godot:setup"  = "powershell -ExecutionPolicy Bypass -File scripts/setup-godot.ps1"
        "godot:detect" = "node scripts/godot-mcp-server.js --detect"
        "godot:import" = "node scripts/godot-mcp-server.js --import"
        "godot:test"   = "node scripts/godot-mcp-server.js --test"
        "godot:play"   = "node scripts/godot-mcp-server.js --play"
    }
}
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText(
    (Join-Path $Payload "package.json"),
    ($marker | ConvertTo-Json -Depth 5),
    $utf8NoBom
)
Write-Host "[ OK ] resources/mobius-godot/" -ForegroundColor Green

$required = @(
    (Join-Path $ClientDir "scripts\godot-mcp-server.js"),
    (Join-Path $ClientDir "game-dev\project.godot"),
    (Join-Path $Payload "scripts\godot-mcp-server.js"),
    (Join-Path $Payload "game-dev\project.godot"),
    (Join-Path $Payload "package.json")
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "[FAIL] Staged payload validation failed: $path" -ForegroundColor Red
        exit 1
    }
}
if ($engineAtRoot -and -not (Test-Path -LiteralPath (Join-Path $ClientDir "tools\godot\godot.exe"))) {
    Write-Host "[FAIL] Expected install-root tools/godot/godot.exe" -ForegroundColor Red
    exit 1
}
if ($engineAtPayload -and -not (Test-Path -LiteralPath (Join-Path $Payload "tools\godot\godot.exe"))) {
    Write-Host "[FAIL] Expected payload tools/godot/godot.exe" -ForegroundColor Red
    exit 1
}

$sizeMb = [math]::Round(
    ((Get-ChildItem -LiteralPath $Payload -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 1
)
Write-Host "[ OK ] Godot payload staged ($sizeMb MB under resources/mobius-godot)" -ForegroundColor Green
if (-not $engineAtRoot) {
    Write-Info "Godot engine missing in repo — users run: npm run godot:setup -- -Install"
}
