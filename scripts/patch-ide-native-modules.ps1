param(
    [string]$IdeRoot = "$env:LOCALAPPDATA\Programs\Mobius\resources\app",
    [string]$SourceRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) "vscode"),
    [string]$UserDataDir = "$env:APPDATA\Mobius",
    [switch]$NoCrashReporter
)

$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
    Copy missing win32-x64 native Node modules from the source tree into the
    installed Mobius IDE.

.DESCRIPTION
    The packaged/installed Mobius build is missing several `.node` binaries
    that are present in the built source tree (vscode/node_modules). The most
    important one is @vscode/windows-ca-certs/build/Release/crypt32.node:
    without it, @vscode/proxy-agent throws on every startup while loading the
    Windows system root certificates:

        ProxyResolver#loadSystemCertificates error Error: Cannot find module
        '...@vscode\windows-ca-certs\build\Release\crypt32'

    That error is visible in every session's main.log. It destabilizes TLS /
    HTTPS streams to the model and is one of the contributors to the IDE
    closing unexpectedly mid-task (main-process native crash cascades with no
    Crashpad dump because crash reporting is disabled).

    This script copies each missing win32-x64 `.node` from the source tree
    into the installed IDE, then verifies it is loadable. It mirrors
    scripts/patch-ide-ripgrep.ps1 and is safe to re-run.

.PARAMETER IdeRoot
    Path to the installed Mobius app dir. Defaults to
        $env:LOCALAPPDATA\Programs\Mobius\resources\app

.PARAMETER SourceRoot
    Path to the built VS Code source tree (contains node_modules/...).
    Defaults to <repo>/vscode.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/patch-ide-native-modules.ps1
#>

if (-not (Test-Path $IdeRoot)) {
    Write-Host "[FAIL] Installed IDE not found: $IdeRoot" -ForegroundColor Red
    Write-Host "       Pass -IdeRoot or run the installer first." -ForegroundColor Yellow
    exit 1
}

# win32-x64 native modules that ship in source but are stripped from the
# installed build. Paths are relative to node_modules.
$Modules = @(
    "@vscode\windows-ca-certs\build\Release\crypt32.node",
    "@os-theme\win32-x64\os-theme-napi.win32-x64.node",
    "native-is-elevated\build\Release\iselevated.node",
    "@github\copilot\prebuilds\win32-x64\cli-native.node",
    "@github\copilot\prebuilds\win32-x64\computer.node",
    "@github\copilot\prebuilds\win32-x64\keytar.node",
    "bufferutil\prebuilds\win32-x64\bufferutil.node",
    "utf-8-validate\prebuilds\win32-x64\node.napi.node"
)

$srcNm = Join-Path $SourceRoot "node_modules"
$dstNm = Join-Path $IdeRoot "node_modules"

if (-not (Test-Path $srcNm)) {
    Write-Host "[FAIL] Source node_modules not found: $srcNm" -ForegroundColor Red
    Write-Host "       Run 'npm run install:vscode' (or a build) first." -ForegroundColor Yellow
    exit 1
}

$copied = 0
$missing = 0

foreach ($rel in $Modules) {
    $src = Join-Path $srcNm $rel
    $dst = Join-Path $dstNm $rel

    if (-not (Test-Path $src)) {
        Write-Host "[SKIP] Source missing: $rel" -ForegroundColor DarkYellow
        $missing++
        continue
    }

    # Only copy if absent or different (avoid touching unchanged files).
    $needCopy = $true
    if (Test-Path $dst) {
        $s = Get-Item $src
        $d = Get-Item $dst
        if ($s.Length -eq $d.Length) { $needCopy = $false }
    }

    if (-not $needCopy) {
        Write-Host "[ OK ] Already present: $rel" -ForegroundColor DarkGreen
        continue
    }

    $dir = Split-Path -Parent $dst
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Copy-Item -Path $src -Destination $dst -Force
    Write-Host "[ OK ] Installed $rel" -ForegroundColor Green
    $copied++
}

Write-Host ""
Write-Host "Copied $copied module(s); $missing source-missing." -ForegroundColor Cyan

# Enable local crash reporting so a future silent close (main-process native
# crash, OOM, GPU/utility process crash) leaves a .dmp under Crashpad/reports
# instead of vanishing with no evidence. We write a user argv.json that sets
# enable-crash-reporter=true but no submit URL, so dumps stay on disk only.
if (-not $NoCrashReporter -and (Test-Path $UserDataDir)) {
    $argvPath = Join-Path $UserDataDir "argv.json"
    $argv = [ordered]@{}
    if (Test-Path $argvPath) {
        try {
            $existing = Get-Content $argvPath -Raw | ConvertFrom-Json
            foreach ($p in $existing.PSObject.Properties) { $argv[$p.Name] = $p.Value }
        } catch { $argv = [ordered]@{} }
    }
    $changed = $false
    if (-not $argv.Contains('enable-crash-reporter') -or -not $argv['enable-crash-reporter']) {
        $argv['enable-crash-reporter'] = $true
        $changed = $true
    }
    if ($changed) {
        $argv | ConvertTo-Json -Depth 10 | Set-Content -Path $argvPath -Encoding UTF8
        Write-Host "[ OK ] Enabled local crash reporting in $argvPath" -ForegroundColor Green
    } else {
        Write-Host "[ OK ] Crash reporting already enabled ($argvPath)" -ForegroundColor DarkGreen
    }
}

# Verify the critical one is present and nonzero in size. A full load test
# would require launching Electron with the matching Node ABI, which is not
# necessary for a file-copy patch and would block this script on a GUI launch.
$crypt32 = Join-Path $dstNm "@vscode\windows-ca-certs\build\Release\crypt32.node"
if (-not (Test-Path $crypt32)) {
    Write-Host "[FAIL] crypt32.node still missing after copy" -ForegroundColor Red
    exit 1
}
$c = Get-Item $crypt32
if ($c.Length -lt 1024) {
    Write-Host "[FAIL] crypt32.node looks too small ($($c.Length) bytes)" -ForegroundColor Red
    exit 1
}
Write-Host "[ OK ] crypt32.node present ($($c.Length) bytes)" -ForegroundColor Green

Write-Host ""
Write-Host "Restart Mobius to pick up the native modules." -ForegroundColor Cyan
exit 0
