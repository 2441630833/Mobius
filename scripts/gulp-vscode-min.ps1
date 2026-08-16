# Run vscode-win32-*-min gulp task with Mobius build environment
param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"

. "$Root\scripts\vs-dev-env.ps1"
Ensure-BuildSourceVersion -RepoDir $VsCodeDir | Out-Null
& "$Root\scripts\init-electron-env.ps1" -Arch $Arch -VsCodeDir $VsCodeDir
Import-VsDevEnvironment | Out-Null
if (-not (Add-SignToolToPath)) {
    Write-Host "[WARN] signtool.exe not found; rcedit will skip Authenticode stripping" -ForegroundColor Yellow
}

Push-Location $VsCodeDir
$env:NODE_OPTIONS = "--experimental-strip-types"
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"
if ($env:SKIP_COPILOT_BUILD -ne "0") { $env:SKIP_COPILOT_BUILD = "1" }

try {
    npm run gulp "vscode-win32-$Arch-min"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}
