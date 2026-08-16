# Download Electron if missing (Node 22.15 needs isMainModule patch in vscode/build/lib)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"
$ElectronDir = Join-Path $VsCodeDir ".build\electron"
$Win32Js = Join-Path $VsCodeDir "node_modules\@vscode\gulp-electron\src\win32.js"
$ElectronVersion = "42.2.0"
$ElectronZipName = "electron-v$ElectronVersion-win32-x64.zip"
$ProductExeName = "Mobius.exe"
$CodeIco = Join-Path $VsCodeDir "resources\win32\code.ico"

function Remove-DevElectronAppStub {
    # electron.ts writes resources/app/package.json pointing at ./out/main.js, but
    # does not link the compiled out/ tree. Dev launch must use default_app.asar,
    # which loads out/main.js from the repo root (the "." argument to code.bat).
    $AppDir = Join-Path $ElectronDir "resources\app"
    if (Test-Path $AppDir) {
        Write-Host "Removing stub resources/app (dev uses default_app.asar + repo out/)" -ForegroundColor Yellow
        Remove-Item -Recurse -Force $AppDir
    }
}

function Ensure-SignToolFallback {
    $sdkBin = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (Test-Path $sdkBin) { return }

    $fallback = "${env:ProgramFiles(x86)}\Microsoft SDKs\ClickOnce\SignTool\signtool.exe"
    if (-not (Test-Path $fallback)) {
        Write-Host "[FAIL] Windows 10/11 SDK not found and no signtool fallback." -ForegroundColor Red
        Write-Host "       Install SDK: winget install Microsoft.WindowsSDK.10.0.22621" -ForegroundColor Yellow
        Write-Host "       Or via VS Installer: Desktop development with C++ -> Windows 10/11 SDK" -ForegroundColor Yellow
        exit 1
    }

    if (-not (Test-Path $Win32Js)) { return }

    $content = Get-Content $Win32Js -Raw
    if ($content -notmatch 'mobius: signtool fallback') {
        $content = $content -replace '(?ms)(if \(!fs\.existsSync\(windowsSDKDir\)\) \{\s*)throw `There is no Windows 10 SDK installed at \$\{windowsSDKDir\}\.`;\s*\}', @'
if (!fs.existsSync(windowsSDKDir)) {
    const fallback = "C:\\Program Files (x86)\\Microsoft SDKs\\ClickOnce\\SignTool\\signtool.exe";
    if (fs.existsSync(fallback)) {
      return fallback; // mobius: signtool fallback
    }
    throw `There is no Windows 10 SDK installed at ${windowsSDKDir}.`;
  }
'@
        Set-Content -Path $Win32Js -Value $content -NoNewline
        Write-Host "Using ClickOnce signtool fallback (Windows SDK not in Windows Kits\10\bin)" -ForegroundColor Yellow
    }
}

function Find-CachedElectronZip {
    $cacheRoot = Join-Path $env:LOCALAPPDATA "electron\Cache"
    if (-not (Test-Path $cacheRoot)) { return $null }
    Get-ChildItem -Path $cacheRoot -Recurse -Filter $ElectronZipName -File -ErrorAction SilentlyContinue |
        Sort-Object Length -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Set-ElectronProductBranding {
    $stock = Join-Path $ElectronDir "electron.exe"
    $productExe = Join-Path $ElectronDir $ProductExeName
    if ((Test-Path $stock) -and -not (Test-Path $productExe)) {
        Rename-Item -Path $stock -NewName $ProductExeName
    }
    $exePath = if (Test-Path $productExe) { $productExe } else { $stock }
    if (-not (Test-Path $exePath)) { return }
    if (-not (Test-Path $CodeIco)) { return }

    $rceditJs = Join-Path $VsCodeDir "node_modules\rcedit\lib\rcedit.js"
    if (-not (Test-Path $rceditJs)) {
        Write-Host "[WARN] rcedit not found; skipping icon branding" -ForegroundColor Yellow
        return
    }
    Write-Host "Applying Mobius icon to $([IO.Path]::GetFileName($exePath))..." -ForegroundColor DarkGray
    Push-Location $VsCodeDir
    try {
        node -e "require('rcedit')(process.argv[1], { icon: process.argv[2] }, err => { if (err) { console.error(err); process.exit(1) } })" $exePath $CodeIco
    } catch {
        Write-Host "[WARN] rcedit failed: $_" -ForegroundColor Yellow
    } finally {
        Pop-Location
    }
}

function Restore-ElectronFromZip {
    param([Parameter(Mandatory = $true)][string]$ZipPath)

    Write-Host "Restoring Electron from local cache (skipping GitHub download)..." -ForegroundColor Yellow
    Write-Host "  $ZipPath" -ForegroundColor DarkGray
    if (Test-Path $ElectronDir) {
        Remove-Item -Recurse -Force $ElectronDir
    }
    New-Item -ItemType Directory -Force -Path $ElectronDir | Out-Null
    Expand-Archive -Path $ZipPath -DestinationPath $ElectronDir -Force
    Set-ElectronProductBranding
    Remove-DevElectronAppStub
}

function Set-ElectronDownloadMirror {
    # GitHub releases often time out in CN; npmmirror hosts the same artifacts.
    # (package.ps1 uses scripts/init-electron-env.ps1 for mirror + cache seed.)
    if ($env:ELECTRON_MIRROR -eq "official" -or $env:ELECTRON_MIRROR -eq "github") {
        Remove-Item Env:ELECTRON_MIRROR -ErrorAction SilentlyContinue
        return
    }
    if (-not $env:ELECTRON_MIRROR) {
        $env:ELECTRON_MIRROR = "https://npmmirror.com/mirrors/electron/"
        Write-Host "Using Electron mirror: $env:ELECTRON_MIRROR" -ForegroundColor DarkGray
    }
}

$existingExe = $null
if (Test-Path $ElectronDir) {
    $existingExe = @(Get-ChildItem $ElectronDir -Filter "*.exe" -ErrorAction SilentlyContinue) | Select-Object -First 1
}
if ($existingExe) {
    # Ensure product name for launch-ide.ps1
    $productExe = Join-Path $ElectronDir $ProductExeName
    if (-not (Test-Path $productExe)) {
        Set-ElectronProductBranding
    }
    Remove-DevElectronAppStub
    exit 0
}

Ensure-SignToolFallback

$cachedZip = Find-CachedElectronZip
if ($cachedZip) {
    Restore-ElectronFromZip -ZipPath $cachedZip
    $exe = Get-ChildItem $ElectronDir -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($exe) {
        Write-Host "[ OK ] Electron ready ($($exe.Name))" -ForegroundColor Green
        exit 0
    }
}

Set-ElectronDownloadMirror
Write-Host "Downloading Electron (first launch only, ~2 min)..." -ForegroundColor Yellow
Push-Location $VsCodeDir
$env:NODE_OPTIONS = "--experimental-strip-types"
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"
node build/lib/electron.ts
if ($LASTEXITCODE -ne 0) { Pop-Location; exit 1 }
Pop-Location
Remove-DevElectronAppStub
Set-ElectronProductBranding

$exe = Get-ChildItem $ElectronDir -Filter "*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) {
    Write-Host "[FAIL] Electron download finished but no .exe found in $ElectronDir" -ForegroundColor Red
    exit 1
}
Write-Host "[ OK ] Electron ready ($($exe.Name))" -ForegroundColor Green
