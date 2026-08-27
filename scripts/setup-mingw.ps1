# Install portable GNU make + g++ into tools/mingw for Verilator --build.
#
# YosysHQ OSS CAD Suite on Windows ships verilator_bin.exe but not make/g++.
# Preferred source in CN: MSYS2 mingw64 packages from USTC (see
# config/mingw.packages). Fallback: skeeto/w64devkit from GitHub/mirrors.
#
#   .\scripts\setup-mingw.ps1            # install if missing
#   .\scripts\setup-mingw.ps1 -Force     # re-download even if present
param(
    [switch]$Force,
    [switch]$Detect
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Root = Split-Path -Parent $PSScriptRoot
$VersionFile = Join-Path $Root "config\mingw.version"
$PackageFile = Join-Path $Root "config\mingw.packages"
$Dest = Join-Path $Root "tools\mingw"
$Marker = Join-Path $Dest ".bundled-version"

function Read-PinnedVersion {
    if (-not (Test-Path -LiteralPath $VersionFile)) {
        throw "Missing $VersionFile"
    }
    return (Get-Content -LiteralPath $VersionFile -Raw).Trim()
}

function Test-KitReady([string]$dir) {
    $bin = Join-Path $dir "bin"
    $gxx = @(
        (Join-Path $bin "g++.exe"),
        (Join-Path $bin "g++")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    $make = @(
        (Join-Path $bin "make.exe"),
        (Join-Path $bin "mingw32-make.exe"),
        (Join-Path $bin "make")
    ) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    return [bool]($gxx -and $make)
}

function Repair-MakeAlias([string]$dir) {
    $bin = Join-Path $dir "bin"
    $make = Join-Path $bin "make.exe"
    $alias = Join-Path $bin "mingw32-make.exe"
    if ((-not (Test-Path -LiteralPath $make)) -and (Test-Path -LiteralPath $alias)) {
        Copy-Item -LiteralPath $alias -Destination $make -Force
    }
}

function Get-AssetName([string]$version) {
    return "w64devkit-x64-$version.7z.exe"
}

function Get-AssetUrls([string]$version, [string]$name) {
    $tag = if ($version.StartsWith("v")) { $version } else { "v$version" }
    $github = "https://github.com/skeeto/w64devkit/releases/download/$tag/$name"
    $urls = @()
    if ($env:MINGW_URL) { $urls += $env:MINGW_URL }
    $urls += "https://tvv.tw/$github"
    $urls += $github
    $urls += "https://gh-proxy.com/$github"
    $urls += "https://mirror.ghproxy.com/$github"
    $urls += "https://ghfast.top/$github"
    return $urls | Select-Object -Unique
}

function Get-Archive([string[]]$urls, [string]$archive) {
    if (Test-Path -LiteralPath $archive) {
        Remove-Item -LiteralPath $archive -Force
    }
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    foreach ($url in $urls) {
        Write-Host "Downloading $url" -ForegroundColor Cyan
        if ($curl) {
            & curl.exe -L --fail --retry 2 --retry-delay 2 --connect-timeout 20 --output $archive $url
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $archive) -and ((Get-Item -LiteralPath $archive).Length -gt 1MB)) {
                return
            }
        }
        else {
            try {
                Invoke-WebRequest -Uri $url -OutFile $archive -UseBasicParsing
                if ((Test-Path -LiteralPath $archive) -and ((Get-Item -LiteralPath $archive).Length -gt 1MB)) { return }
            }
            catch {
                Write-Host "  failed: $_" -ForegroundColor Yellow
            }
        }
        Write-Host "  source failed, trying next mirror..." -ForegroundColor Yellow
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    }
    throw "Download failed for every mirror (last: $($urls[-1]))"
}

function Get-SevenZip {
    foreach ($name in @("7zr.exe", "7z.exe")) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $local = Join-Path $Root "tools\_mingw-download\7zr.exe"
    if (Test-Path -LiteralPath $local) { return $local }
    New-Item -ItemType Directory -Force -Path (Split-Path $local) | Out-Null
    $urls = @(
        "https://www.7-zip.org/a/7zr.exe",
        "https://gh-proxy.com/https://github.com/ip7z/7zip/releases/download/25.01/7zr.exe"
    )
    foreach ($url in $urls) {
        Write-Host "Fetching 7zr.exe from $url" -ForegroundColor DarkGray
        try {
            & curl.exe -L --fail --retry 2 --output $local $url
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $local) -and ((Get-Item -LiteralPath $local).Length -gt 50KB)) {
                return $local
            }
        }
        catch { }
        if (Test-Path -LiteralPath $local) { Remove-Item -LiteralPath $local -Force }
    }
    return $null
}

function Expand-Sfx([string]$archive, [string]$extractRoot) {
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null
    $seven = Get-SevenZip
    if ($seven) {
        Write-Host "Extracting with $seven ..." -ForegroundColor Cyan
        & $seven x -y "-o$extractRoot" $archive
        if ($LASTEXITCODE -eq 0) { return }
        Write-Host "  7z extract failed (exit $LASTEXITCODE), trying SFX flags..." -ForegroundColor Yellow
    }
    Write-Host "Extracting SFX ..." -ForegroundColor Cyan
    & $archive x -y "-o$extractRoot"
    if ($LASTEXITCODE -ne 0) {
        throw "Could not extract $archive (install 7-Zip or retry). Last exit $LASTEXITCODE"
    }
}

function Read-Msys2Packages {
    if (-not (Test-Path -LiteralPath $PackageFile)) { return @() }
    return Get-Content -LiteralPath $PackageFile -Encoding UTF8 |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith("#") }
}

function Get-Msys2Mirrors {
    $mirrors = @()
    if ($env:MINGW_MSYS2_MIRROR) { $mirrors += $env:MINGW_MSYS2_MIRROR.TrimEnd("/") }
    $mirrors += @(
        "https://mirrors.ustc.edu.cn/msys2/mingw/mingw64",
        "https://mirrors.tuna.tsinghua.edu.cn/msys2/mingw/mingw64",
        "https://repo.msys2.org/mingw/mingw64"
    )
    return $mirrors | Select-Object -Unique
}

function Save-Package([string]$name, [string]$destFile) {
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    foreach ($mirror in Get-Msys2Mirrors) {
        $url = "$mirror/$name"
        Write-Host "  $url" -ForegroundColor DarkGray
        if ($curl) {
            & curl.exe -L --fail --retry 2 --retry-delay 2 --connect-timeout 15 --output $destFile $url
            if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $destFile) -and ((Get-Item -LiteralPath $destFile).Length -gt 1KB)) {
                return
            }
        }
        if (Test-Path -LiteralPath $destFile) { Remove-Item -LiteralPath $destFile -Force }
    }
    throw "Could not download $name from any MSYS2 mirror"
}

function Install-FromMsys2([string]$tmpDir) {
    $packages = @(Read-Msys2Packages)
    if ($packages.Count -eq 0) { return $false }
    $tar = Get-Command tar.exe -ErrorAction SilentlyContinue
    if (-not $tar) {
        Write-Host "Windows tar.exe missing; skip MSYS2 packages." -ForegroundColor Yellow
        return $false
    }

    Write-Host "Installing MinGW from MSYS2 mirrors (USTC first) ..." -ForegroundColor Cyan
    $pkgDir = Join-Path $tmpDir "msys2-pkgs"
    $extractRoot = Join-Path $tmpDir "msys2-extract"
    New-Item -ItemType Directory -Force -Path $pkgDir | Out-Null
    if (Test-Path -LiteralPath $extractRoot) {
        Remove-Item -LiteralPath $extractRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $extractRoot | Out-Null

    foreach ($pkg in $packages) {
        $destFile = Join-Path $pkgDir $pkg
        Write-Host "Downloading $pkg" -ForegroundColor Cyan
        Save-Package $pkg $destFile
        Write-Host "  extracting ..." -ForegroundColor DarkGray
        & tar.exe -xf $destFile -C $extractRoot
        if ($LASTEXITCODE -ne 0) {
            throw "tar extract failed for $pkg (exit $LASTEXITCODE)"
        }
    }

    $unpacked = Join-Path $extractRoot "mingw64"
    if (-not (Test-Path -LiteralPath $unpacked)) {
        $unpacked = $extractRoot
    }
    Repair-MakeAlias $unpacked
    if (-not (Test-KitReady $unpacked)) {
        Write-Host "MSYS2 extract missing g++/make; falling back to w64devkit." -ForegroundColor Yellow
        return $false
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
    if (Test-Path -LiteralPath $Dest) {
        Remove-Item -LiteralPath $Dest -Recurse -Force
    }
    Move-Item -LiteralPath $unpacked -Destination $Dest
    Repair-MakeAlias $Dest
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Marker, "msys2-gcc-16.1.0`n", $utf8NoBom)
    return $true
}

function Install-FromW64devkit([string]$tmpDir, [string]$version) {
    $zipName = Get-AssetName $version
    $archive = Join-Path $tmpDir $zipName
    Write-Host "Falling back to w64devkit $version (~60 MB GitHub asset)." -ForegroundColor DarkGray
    Get-Archive (Get-AssetUrls $version $zipName) $archive

    $extractRoot = Join-Path $tmpDir "extract"
    Expand-Sfx $archive $extractRoot

    $unpacked = $extractRoot
    Repair-MakeAlias $unpacked
    if (-not (Test-KitReady $unpacked)) {
        $nested = Get-ChildItem -Directory $extractRoot | Select-Object -First 1
        if ($nested) { $unpacked = $nested.FullName }
    }
    Repair-MakeAlias $unpacked
    if (-not (Test-KitReady $unpacked)) {
        throw "Extracted tree has no g++/make under bin/. Contents: $(Get-ChildItem $extractRoot | ForEach-Object Name)"
    }

    New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
    if (Test-Path -LiteralPath $Dest) {
        Remove-Item -LiteralPath $Dest -Recurse -Force
    }
    Move-Item -LiteralPath $unpacked -Destination $Dest

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($Marker, $version + "`n", $utf8NoBom)
}

$Version = Read-PinnedVersion
Write-Host "MinGW make/g++ -> $Dest" -ForegroundColor Cyan

if ($Detect) {
    if (Test-KitReady $Dest) {
        Write-Host "OK  bundled make/g++ at $Dest\bin" -ForegroundColor Green
        exit 0
    }
    Write-Host "WARN MinGW kit not installed. Run: npm run chip:mingw" -ForegroundColor Yellow
    exit 1
}

if (-not $Force -and (Test-KitReady $Dest)) {
    Write-Host "Already bundled (make/g++ present)." -ForegroundColor Green
    exit 0
}

$tmpDir = Join-Path $Root "tools\_mingw-download"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$installed = $false
try {
    $installed = Install-FromMsys2 $tmpDir
}
catch {
    Write-Host "MSYS2 package install failed: $_" -ForegroundColor Yellow
    $installed = $false
}

if (-not $installed) {
    Install-FromW64devkit $tmpDir $Version
}

if (-not (Test-KitReady $Dest)) {
    throw "MinGW install finished but $Dest\bin still has no g++/make"
}

Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Installed: $Dest" -ForegroundColor Green
exit 0
