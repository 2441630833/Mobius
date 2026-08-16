# Ensure sqlite3 native binary for Continue (avoids GitHub timeout in prepackage)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Target = if ($env:CONTINUE_VSCODE_TARGET) { $env:CONTINUE_VSCODE_TARGET } else { "win32-x64" }
$GitHubPath = "TryGhost/node-sqlite3/releases/download/v5.1.7/sqlite3-v5.1.7-napi-v6-$Target.tar.gz"

function Test-SqliteReady([string]$SqliteDir) {
    $releaseNode = Join-Path $SqliteDir "build\Release\node_sqlite3.node"
    if (Test-Path $releaseNode) { return $true }
    $any = Get-ChildItem $SqliteDir -Recurse -Filter "node_sqlite3.node" -ErrorAction SilentlyContinue | Select-Object -First 1
    return [bool]$any
}

function Get-SqliteDownloadUrls {
    $direct = "https://github.com/$GitHubPath"
    $proxies = @(
        "https://gh-proxy.org/$direct",
        "https://v4.gh-proxy.org/$direct",
        "https://v6.gh-proxy.org/$direct"
    )
    return @($direct) + $proxies
}

function Prepare-Sqlite([string]$SqliteDir) {
    if (-not (Test-Path $SqliteDir)) {
        Write-Host "  sqlite3 package not found at $SqliteDir (run npm install first)" -ForegroundColor DarkYellow
        return $false
    }

    if (Test-SqliteReady $SqliteDir) {
        Write-Host "[ OK ] sqlite3 binary already present: $SqliteDir" -ForegroundColor Green
        return $true
    }

    Write-Host "Preparing sqlite3 for $Target at $SqliteDir" -ForegroundColor Yellow

    $buildDir = Join-Path $SqliteDir "build"
    $tarPath = Join-Path $SqliteDir "build.tar.gz"
    if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir -ErrorAction SilentlyContinue }

    $downloaded = $false
    foreach ($url in (Get-SqliteDownloadUrls)) {
        Write-Host "Trying download: $url" -ForegroundColor Gray
        try {
            Invoke-WebRequest -Uri $url -OutFile $tarPath -TimeoutSec 120 -UseBasicParsing
            if ((Get-Item $tarPath).Length -gt 1000) {
                $downloaded = $true
                break
            }
        } catch {
            Write-Host "  failed: $($_.Exception.Message)" -ForegroundColor DarkYellow
        }
    }

    if ($downloaded) {
        Push-Location $SqliteDir
        tar -xzf build.tar.gz
        Remove-Item build.tar.gz -Force -ErrorAction SilentlyContinue
        Pop-Location
        if (Test-SqliteReady $SqliteDir) {
            Write-Host "[ OK ] sqlite3 downloaded and extracted" -ForegroundColor Green
            return $true
        }
    }

    Write-Host "Download failed -- building sqlite3 from source (needs VS C++)..." -ForegroundColor Yellow
    $env:npm_config_msvs_version = "2026"
    Push-Location $SqliteDir
    npx --yes node-gyp@12 rebuild
    $buildOk = ($LASTEXITCODE -eq 0) -and (Test-SqliteReady $SqliteDir)
    Pop-Location

    if ($buildOk) {
        Write-Host "[ OK ] sqlite3 built from source" -ForegroundColor Green
        return $true
    }

    Write-Host "[FAIL] Could not prepare sqlite3 at $SqliteDir" -ForegroundColor Red
    return $false
}

$sqliteDirs = @(
    (Join-Path $Root "continue\core\node_modules\sqlite3"),
    (Join-Path $Root "continue\extensions\vscode\node_modules\sqlite3")
)

$allOk = $true
foreach ($dir in $sqliteDirs) {
    if (-not (Prepare-Sqlite $dir)) {
        if (Test-Path $dir) { $allOk = $false }
    }
}

if (-not $allOk) {
    Write-Host "`nManual fix:" -ForegroundColor Yellow
    Write-Host "  cd continue\core\node_modules\sqlite3" -ForegroundColor Gray
    Write-Host "  npx node-gyp@12 rebuild" -ForegroundColor Gray
    exit 1
}

exit 0
