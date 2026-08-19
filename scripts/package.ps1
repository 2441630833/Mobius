# Mobius -- one-click Windows Inno Setup installer (includes bundled Ollama + models)
# Default: user-setup (no admin). Pass -Target system for Program Files install.
param(
    [ValidateSet("x64", "arm64")]
    [string]$Arch = "x64",

    [ValidateSet("user", "system")]
    [string]$Target = $(if ($env:PACKAGE_TARGET -in @("user", "system")) { $env:PACKAGE_TARGET } else { "user" })
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"
$ClientDir = Join-Path (Split-Path -Parent $VsCodeDir) "VSCode-win32-$Arch"
$SetupDir = Join-Path $VsCodeDir ".build\win32-$Arch\$Target-setup"

# Strip --inspect/--debug from NODE_OPTIONS (JavaScript Debug Terminal). Otherwise
# child node processes write "Debugger attached." to stderr and PowerShell Stop mode aborts.
if ($env:NODE_OPTIONS) {
    $cleanedNodeOptions = ($env:NODE_OPTIONS -split '\s+' |
        Where-Object { $_ -and $_ -notmatch '^--inspect' -and $_ -notmatch '^--debug' }) -join ' '
    if ($cleanedNodeOptions) { $env:NODE_OPTIONS = $cleanedNodeOptions }
    else { Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue }
}

function Invoke-Step {
    param(
        [string]$Label,
        [scriptblock]$Action
    )
    Write-Host "`n=== $Label ===" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Label failed (exit $LASTEXITCODE)"
    }
}

function Invoke-VsCodeGulp {
    param([Parameter(Mandatory = $true)][string]$Task)

    $nodeDir = Resolve-NodeDirectory
    if (-not $nodeDir) {
        throw "node.exe not found (needed for gulp: $Task)"
    }
    $nodeExe = Join-Path $nodeDir "node.exe"
    # Prefer absolute node path: after vcvars, cmd/npm often lose Node from PATH
    if ($env:PATH -notlike "*$nodeDir*") {
        $env:PATH = "$nodeDir;$env:PATH"
    }
    & $nodeExe --experimental-strip-types --max-old-space-size=8192 ./node_modules/gulp/bin/gulp.js $Task
}

Write-Host "`n=== Mobius Package (win32-$Arch, $Target-setup) ===" -ForegroundColor Cyan
# Default: incremental (esbuild + min-ci). Full rebuild only when PACKAGE_FULL=1.
if ($env:PACKAGE_FULL -eq "1") {
    Remove-Item Env:PACKAGE_INCREMENTAL -ErrorAction SilentlyContinue
} elseif ($env:PACKAGE_INCREMENTAL -ne "0" -and $env:SKIP_VSCODE_BUILD -ne "1") {
    $env:PACKAGE_INCREMENTAL = "1"
}
$mode = if ($env:SKIP_VSCODE_BUILD -eq "1") { "setup-only (no compile)" } elseif ($env:PACKAGE_INCREMENTAL -eq "1") { "incremental" } else { "full" }
Write-Host "Build mode: $mode" -ForegroundColor Yellow
$targetHint = if ($Target -eq "user") {
    "per-user, no admin -- %LOCALAPPDATA%\Programs\Mobius"
} else {
    "system-wide -- Program Files\Mobius (requires admin)"
}
Write-Host "Install target: $Target ($targetHint)" -ForegroundColor Yellow
if ($env:SKIP_VSCODE_BUILD -eq "1" -or $env:SKIP_CONTINUE_BUILD -eq "1") {
    Write-Host ""
    Write-Host "WARNING: package:setup / SKIP_* rebuilds ONLY the .exe from the existing client tree." -ForegroundColor Red
    Write-Host "  - Continue / Ollama runtime code changes are NOT included." -ForegroundColor Red
    Write-Host "  - After editing ollamaHelper / Continue / workbench, use:" -ForegroundColor Red
    Write-Host "      npm run package:fast     (rebuild Continue + VS Code client + setup, reuse Ollama)" -ForegroundColor Yellow
    Write-Host "      npm run package         (same + verify/stage Ollama)" -ForegroundColor Yellow
    Write-Host "  - package:setup is for re-wrapping an already-updated VSCode-win32-* tree only.`n" -ForegroundColor Gray
}
Write-Host "This builds a full Windows installer with bundled Ollama + models (~3.5-4 GB)." -ForegroundColor Yellow
Write-Host "Ollama is stored without LZMA (nocompression) so day-to-day packaging stays fast when models don't change.`n" -ForegroundColor Gray

. "$Root\scripts\vs-dev-env.ps1"
Ensure-BuildSourceVersion -RepoDir $VsCodeDir | Out-Null

# Electron: use CN mirror + seed local zip into @electron/get cache (avoids GitHub ETIMEDOUT).
# Even with a zip cache hit, @electron/get still fetches SHASUMS256.txt -- mirror keeps that fast.
& "$Root\scripts\init-electron-env.ps1" -Arch $Arch -VsCodeDir $VsCodeDir

Invoke-Step "Check prerequisites" {
    & "$Root\scripts\check-prerequisites.ps1"
}

Invoke-Step "Sync brand assets (installer wizard images)" {
    & "$Root\scripts\sync-brand-assets.ps1"
}

# Inno Setup LicenseFile reads vscode/LICENSE.txt (RepoDir), not monorepo root.
Invoke-Step "Sync LICENSE.txt into vscode (installer license page)" {
    $srcLicense = Join-Path $Root "LICENSE.txt"
    $dstLicense = Join-Path $VsCodeDir "LICENSE.txt"
    if (-not (Test-Path $srcLicense)) {
        throw "Missing root license: $srcLicense"
    }
    Copy-Item -LiteralPath $srcLicense -Destination $dstLicense -Force
    Write-Host "Synced LICENSE.txt -> $dstLicense"
}

if ($env:SKIP_OLLAMA_BUNDLE -ne "1") {
    Invoke-Step "Bundle Ollama (dual-arch runtime + models)" {
        & "$Root\scripts\bundle-ollama.ps1"
    }
} else {
    Write-Host "`n=== Bundle Ollama (skipped: SKIP_OLLAMA_BUNDLE=1) ===" -ForegroundColor Yellow
}

Invoke-Step "Verify bundled Ollama" {
    & "$Root\scripts\verify-ollama-bundle.ps1"
}

if ($env:SKIP_CONTINUE_BUILD -ne "1") {
    Invoke-Step "Build Continue extension (release)" {
        $env:CONTINUE_RELEASE = "1"
        & "$Root\scripts\install-continue.ps1"
        Remove-Item Env:CONTINUE_RELEASE -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "`n=== Build Continue extension (skipped: SKIP_CONTINUE_BUILD=1) ===" -ForegroundColor Yellow
    $extJs = Join-Path $Root "continue\extensions\vscode\out\extension.js"
    if (-not (Test-Path $extJs)) {
        Write-Host "[FAIL] Missing Continue build: $extJs" -ForegroundColor Red
        exit 1
    }
}

if ($env:SKIP_VSCODE_BUILD -ne "1") {
    Import-VsDevEnvironment | Out-Null
    if (-not (Add-SignToolToPath)) {
        Write-Host "[WARN] signtool.exe not found; rcedit will skip Authenticode stripping" -ForegroundColor Yellow
    }

    if (-not $env:vs2022_install) {
        $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $vsWhere) {
            $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
            if ($vsPath) { $env:vs2022_install = $vsPath }
        }
    }

    Push-Location $VsCodeDir
    $env:NODE_OPTIONS = "--experimental-strip-types"
    $env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"
    $env:npm_config_msvs_version = "2026"
    $env:npm_config_node_gyp = (Join-Path $Root "scripts\node-gyp-win.js")
    $env:MOBIUS_NODE_GYP_BIN = (Join-Path $VsCodeDir "build\npm\gyp\node_modules\node-gyp\bin\node-gyp.js")
    # Mobius ships Continue, not GitHub Copilot -- skip copilot extension build by default
    if ($env:SKIP_COPILOT_BUILD -ne "0") { $env:SKIP_COPILOT_BUILD = "1" }

    try {
        if ($env:PACKAGE_INCREMENTAL -eq "1") {
            # Incremental: refresh local extensions (esp. Continue) into .build/extensions,
            # rebundle desktop JS, then re-package client tree.
            # Skips clean/rebuild of marketplace + all built-in extensions (slow part of full min).
            $outMin = Join-Path $VsCodeDir "out-vscode-min"
            if (-not (Test-Path $outMin)) {
                throw "PACKAGE_INCREMENTAL=1 requires a prior full build (missing out-vscode-min). Run without PACKAGE_INCREMENTAL once."
            }
            # min-ci packages from .build/extensions -- Continue rebuilds under extensions/continue
            # are invisible until this step re-runs vsce packaging into .build.
            Invoke-Step "Gulp compile-non-native-extensions-build (refresh Continue)" {
                Invoke-VsCodeGulp "compile-non-native-extensions-build"
            }
            Invoke-Step "Gulp esbuild-bundle-win32-$Arch-min (incremental)" {
                Invoke-VsCodeGulp "esbuild-bundle-win32-$Arch-min"
            }
            Invoke-Step "Gulp vscode-win32-$Arch-min-ci (repackage)" {
                Invoke-VsCodeGulp "vscode-win32-$Arch-min-ci"
            }
        } else {
            Invoke-Step "Gulp vscode-win32-$Arch-min (esbuild release)" {
                Invoke-VsCodeGulp "vscode-win32-$Arch-min"
            }
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host "`n=== VS Code build (skipped: SKIP_VSCODE_BUILD=1) ===" -ForegroundColor Yellow
    if (-not (Test-Path $ClientDir)) {
        Write-Host "[FAIL] Missing client tree: $ClientDir" -ForegroundColor Red
        exit 1
    }
}

Invoke-Step "Stage bundled Ollama into client tree" {
    & "$Root\scripts\stage-bundled-ollama.ps1" -Arch $Arch
}

Push-Location $VsCodeDir
$env:NODE_OPTIONS = "--experimental-strip-types"
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"
# Drop stale npm_config_* that confuse npm and aren't needed for Inno Setup
Remove-Item Env:npm_config_msvs_version -ErrorAction SilentlyContinue
try {
    Invoke-Step "Gulp vscode-win32-$Arch-inno-updater" {
        Invoke-VsCodeGulp "vscode-win32-$Arch-inno-updater"
    }
    Invoke-Step "Gulp vscode-win32-$Arch-$Target-setup" {
        Invoke-VsCodeGulp "vscode-win32-$Arch-$Target-setup"
    }
} finally {
    Pop-Location
}

$setupExe = Join-Path $SetupDir "MobiusSetup.exe"
if (-not (Test-Path $setupExe)) {
    Write-Host "[FAIL] Installer not found: $setupExe" -ForegroundColor Red
    exit 1
}

$pkgJson = Get-Content (Join-Path $VsCodeDir "package.json") -Raw | ConvertFrom-Json
$version = $pkgJson.version
$binFiles = @(Get-ChildItem -Path $SetupDir -Filter "MobiusSetup-*.bin" -ErrorAction SilentlyContinue)
$totalBytes = (Get-Item $setupExe).Length
foreach ($bin in $binFiles) { $totalBytes += $bin.Length }

Write-Host "`n=== Package Complete ===" -ForegroundColor Green
Write-Host "Installer: $setupExe" -ForegroundColor White
Write-Host "Target   : $Target-setup" -ForegroundColor White
if ($binFiles.Count -gt 0) {
    Write-Host "Volumes  : $($binFiles.Count) disk-spanning .bin file(s) beside the .exe (keep them together)" -ForegroundColor White
}
Write-Host "Version  : $version" -ForegroundColor White
Write-Host "Size     : $([math]::Round($totalBytes / 1GB, 2)) GB (exe + bins)" -ForegroundColor White
Write-Host "Includes : Mobius IDE + Continue + Ollama (amd64+arm64) + glm-ocr + MiniLM ONNX`n" -ForegroundColor Gray
