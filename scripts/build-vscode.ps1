# Build Mobius (VS Code fork + Continue)
$ErrorActionPreference = "Stop"

# Force UTF-8 console so MSBuild / cl.exe / node-gyp Chinese output is not mangled.
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$env:PYTHONIOENCODING = "utf-8"
cmd /c chcp 65001 > $null 2>&1

$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"

Write-Host "`n=== Building Mobius ===" -ForegroundColor Cyan
Write-Host "First build: ~20-40 min. Requires Node 22.15+ and VS C++ tools.`n" -ForegroundColor Yellow

& "$Root\scripts\check-prerequisites.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }

& "$Root\scripts\sync-brand-assets.ps1"

& "$Root\scripts\install-continue.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }

. "$Root\scripts\vs-dev-env.ps1"
if (-not (Import-VsDevEnvironment)) {
    Write-Host "[WARN] Could not load VS Developer environment (vcvars64). Native module link may fail." -ForegroundColor Yellow
}

# VS Code preinstall only checks vs2019/vs2022 paths; VS 2026 (18.x) needs vs2022_install override
if (-not $env:vs2022_install) {
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
        if ($vsPath) { $env:vs2022_install = $vsPath }
    }
}

Push-Location $VsCodeDir

# VS Code 1.126 runs .ts scripts via Node; Node 22 needs strip-types (24.15 not in nvm-windows yet)
$env:NODE_OPTIONS = "--experimental-strip-types"
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"
$env:npm_config_msvs_version = "2026"
$env:npm_config_node_gyp = (Join-Path $Root "scripts\node-gyp-win.js")
$env:MOBIUS_NODE_GYP_BIN = (Join-Path $VsCodeDir "build\npm\gyp\node_modules\node-gyp\bin\node-gyp.js")
# Also disable Spectre via Directory.Build.* for direct MSBuild invocations

# Clean partial install if native modules failed previously
$nativeOk = (Test-Path (Join-Path $VsCodeDir "node_modules\@parcel\watcher\build\Release")) -and
            (Test-Path (Join-Path $VsCodeDir "node_modules\@vscode\policy-watcher\build\Release\vscode-policy-watcher.node")) -and
            (Test-Path (Join-Path $VsCodeDir "node_modules\@vscode\windows-registry\build\Release\winregistry.node")) -and
            (Test-Path (Join-Path $VsCodeDir "node_modules\@vscode\sqlite3\build\Release\vscode-sqlite3.node")) -and
            (Test-Path (Join-Path $VsCodeDir "node_modules\native-keymap\build\Release\keymapping.node"))
$gulpOk = Test-Path (Join-Path $VsCodeDir "node_modules\gulp\bin\gulp.js")
$postinstallOk = Test-Path (Join-Path $VsCodeDir "build\node_modules\gulp-merge-json")

if ((Test-Path "node_modules") -and -not $nativeOk) {
    Write-Host "Removing incomplete node_modules (native build failed earlier)..." -ForegroundColor Yellow
    Write-Host "Close any running Code/Electron processes first." -ForegroundColor Yellow
    Remove-Item -Recurse -Force "node_modules" -ErrorAction SilentlyContinue
    $gulpOk = $false
    $postinstallOk = $false
}

if (-not (Test-Path "node_modules") -or -not $gulpOk) {
    if ((Test-Path "node_modules") -and -not $gulpOk) {
        Write-Host "VS Code node_modules incomplete (gulp missing) -- repairing..." -ForegroundColor Yellow
        npm install --ignore-scripts
        if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
        if (-not (Test-Path "node_modules\gulp\bin\gulp.js")) {
            Write-Host "[FAIL] gulp still missing after npm install --ignore-scripts" -ForegroundColor Red
            Pop-Location
            exit 1
        }
        Write-Host "Running postinstall (extensions, build/, remote/)..." -ForegroundColor Yellow
        node build/npm/postinstall.ts
        if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
    } else {
        Write-Host "Installing VS Code dependencies (10-20 min)..." -ForegroundColor Yellow
        npm install
        if ($LASTEXITCODE -ne 0) {
            Write-Host "`nnpm install failed; retrying without install scripts to restore devDependencies..." -ForegroundColor Yellow
            npm install --ignore-scripts
            if ($LASTEXITCODE -ne 0) {
                Write-Host "`nVS Code npm install failed." -ForegroundColor Red
                Write-Host "Common fixes:" -ForegroundColor Yellow
                Write-Host "  - ERR_UNKNOWN_FILE_EXTENSION .ts → use Node 22.15+ (script sets NODE_OPTIONS)" -ForegroundColor Gray
                Write-Host "  - MSB8040 Spectre → node-gyp-win.js wrapper + Directory.Build.*; or install Spectre libs in VS" -ForegroundColor Gray
                Write-Host "  - LNK1181 delayimp.lib → run from Developer PowerShell or ensure VS C++ workload is complete" -ForegroundColor Gray
                Write-Host "  - Clean retry: npm run install:vscode" -ForegroundColor Gray
                Pop-Location
                exit 1
            }
        }
    }
} elseif (-not $postinstallOk) {
    Write-Host "Completing VS Code postinstall (build/ + extensions deps)..." -ForegroundColor Yellow
    node build/npm/postinstall.ts
    if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
}

Write-Host "Compiling VS Code (client + extensions, skipping GitHub Copilot)..." -ForegroundColor Yellow
npm run compile-client
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }

Pop-Location

& "$Root\scripts\ensure-electron.ps1"
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n=== Build Complete ===" -ForegroundColor Green
Write-Host "Launch: npm start" -ForegroundColor White
