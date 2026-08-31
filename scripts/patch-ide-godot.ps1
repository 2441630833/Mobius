# Copy Godot Game mode scripts, game-dev, and engine into live / staged Mobius installs.
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$SourceGameDev = Join-Path $Root "game-dev"
$SourceGodotTools = Join-Path $Root "tools\godot"
$SourceGodotExe = Join-Path $SourceGodotTools "godot.exe"
$scriptFiles = @("godot-mcp-server.js", "godot-mcp-launcher.js", "setup-godot.ps1")

function Copy-GodotEngine {
    param([string]$DestRoot)
    $dest = Join-Path $DestRoot "tools\godot"
    if (-not (Test-Path -LiteralPath $SourceGodotExe)) {
        Write-Host "[WARN] Repo missing $SourceGodotExe — engine not copied to $DestRoot" -ForegroundColor Yellow
        return $false
    }
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    Get-ChildItem -LiteralPath $dest -Filter "*.zip" -ErrorAction SilentlyContinue | ForEach-Object {
        try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop }
        catch { Write-Host "[WARN] Could not remove leftover $($_.Name) (in use) — continuing" -ForegroundColor Yellow }
    }
    robocopy $SourceGodotTools $dest /E /XF "*.zip" /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy tools/godot failed for $DestRoot" }
    $global:LASTEXITCODE = 0
    $exe = Join-Path $dest "godot.exe"
    if (-not (Test-Path -LiteralPath $exe)) {
        throw "Missing godot.exe after copy: $exe"
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText((Join-Path $dest "godot.path"), $exe, $utf8NoBom)
    return $true
}

function Copy-GodotPayload {
    param([string]$ClientDir)
    if (-not (Test-Path -LiteralPath $ClientDir)) { return $false }

    $destScripts = Join-Path $ClientDir "scripts"
    New-Item -ItemType Directory -Force -Path $destScripts | Out-Null
    foreach ($name in $scriptFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $destScripts $name) -Force
    }

    $destGameDev = Join-Path $ClientDir "game-dev"
    if (Test-Path -LiteralPath $destGameDev) { Remove-Item -LiteralPath $destGameDev -Recurse -Force }
    robocopy $SourceGameDev $destGameDev /E /XD ".godot" /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy game-dev failed for $ClientDir" }
    $global:LASTEXITCODE = 0

    $null = Copy-GodotEngine -DestRoot $ClientDir

    $payload = Join-Path $ClientDir "resources\mobius-godot"
    New-Item -ItemType Directory -Force -Path $payload | Out-Null
    $payloadScripts = Join-Path $payload "scripts"
    New-Item -ItemType Directory -Force -Path $payloadScripts | Out-Null
    foreach ($name in $scriptFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $payloadScripts $name) -Force
    }
    $payloadGameDev = Join-Path $payload "game-dev"
    if (Test-Path -LiteralPath $payloadGameDev) {
        # Prefer overwrite over delete so a locked leftover download zip cannot block the patch.
        robocopy $SourceGameDev $payloadGameDev /E /XD ".godot" /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    } else {
        robocopy $SourceGameDev $payloadGameDev /E /XD ".godot" /NFL /NDL /NJH /NJS /NC /NS /NP | Out-Null
    }
    if ($LASTEXITCODE -ge 8) { throw "robocopy mobius-godot/game-dev failed for $ClientDir" }
    $global:LASTEXITCODE = 0
    $null = Copy-GodotEngine -DestRoot $payload

    $marker = [ordered]@{
        name        = "Mobius"
        private     = $true
        description = "Mobius Godot Game mode payload"
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText(
        (Join-Path $payload "package.json"),
        ($marker | ConvertTo-Json -Depth 3),
        $utf8NoBom
    )
    return $true
}

$targets = @(
    (Join-Path $Root "VSCode-win32-x64"),
    (Join-Path $env:LOCALAPPDATA "Programs\Mobius")
)

$patched = 0
foreach ($client in $targets) {
    if (-not (Copy-GodotPayload -ClientDir $client)) { continue }
    $probe = Join-Path $client "scripts\godot-mcp-server.js"
    $engine = Join-Path $client "tools\godot\godot.exe"
    if (-not (Test-Path -LiteralPath $probe)) {
        Write-Host "[FAIL] Patch incomplete: $probe" -ForegroundColor Red
        exit 1
    }
    if (-not (Test-Path -LiteralPath $engine)) {
        Write-Host "[FAIL] Engine missing after patch: $engine" -ForegroundColor Red
        Write-Host "       Run: npm run godot:setup -- -Install" -ForegroundColor Yellow
        exit 1
    }
    Write-Host "[ OK ] Godot payload + engine -> $client" -ForegroundColor Green
    $patched++
}

if ($patched -eq 0) {
    Write-Host "[WARN] No Mobius install or staged client to patch" -ForegroundColor Yellow
    exit 0
}

Write-Host "`n[ OK ] Patched $patched tree(s). Restart Mobius if Game mode was open." -ForegroundColor Green
exit 0
