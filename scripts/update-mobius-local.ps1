#Requires -Version 5.1
<#
.SYNOPSIS
    一条命令把本机 Mobius 更新到 GitHub 上的最新发布。

.DESCRIPTION
    本机访问 github.com 会超时，但 api.github.com 是通的，所以本脚本完全走
    GitHub REST API 下载发布包（会 302 到 objects.githubusercontent.com），
    不需要 gh CLI、不需要 git 直连、也不需要浏览器。

    流程：解析发布 → 下载补丁/安装包 → 校验 SHA256 → 关闭提示 → 应用补丁
          → 失败自动回退官方安装器 → 重装会话维护热补丁 → 打印新版本。

.PARAMETER Tag
    目标发布标签，例如 v1.0.23。留空表示 latest。

.PARAMETER InstallDir
    Mobius 安装目录，默认 %LOCALAPPDATA%\Programs\Mobius。

.PARAMETER Mode
    patch = 只应用增量补丁（约 30 MB）；setup = 直接跑官方安装器（约 900 MB）；
    auto  = 先试补丁，失败再回退安装器。

.PARAMETER Force
    Mobius 正在运行时也继续（不推荐：补丁需要文件不被占用）。

.PARAMETER DryRun
    只解析发布、打印将要做的事，不下载、不安装。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\update-mobius-local.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\update-mobius-local.ps1 -Tag v1.0.23 -Mode patch
#>
[CmdletBinding()]
param(
    [string]$Tag = '',
    [string]$InstallDir = '',
    [ValidateSet('patch', 'setup', 'auto')]
    [string]$Mode = 'auto',
    [switch]$Force,
    [switch]$DryRun,
    [switch]$SkipHotpatch,
    [string]$Repo = '2441630833/Mobius'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'mobius-actions.ps1') -Repo $Repo -Action 'Status'

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Get-InstalledVersion {
    param([string]$Dir)
    $pkg = Join-Path $Dir 'resources\app\package.json'
    if (-not (Test-Path -LiteralPath $pkg)) { return $null }
    try { return (Get-Content -LiteralPath $pkg -Raw -Encoding UTF8 | ConvertFrom-Json).version } catch { return $null }
}

function Save-Asset {
    param(
        [Parameter(Mandatory = $true)] $Asset,
        [Parameter(Mandatory = $true)] [string]$DestDir,
        [hashtable]$Sums
    )
    $dest = Join-Path $DestDir $Asset.name
    if ((Test-Path -LiteralPath $dest) -and ((Get-Item -LiteralPath $dest).Length -eq $Asset.size)) {
        Write-Host ("  {0} already downloaded, skipping" -f $Asset.name)
    }
    else {
        Write-Host ("  downloading {0} ({1:N1} MB) ..." -f $Asset.name, ($Asset.size / 1MB))
        $token = Get-GitHubToken
        $headers = @{ Authorization = "Bearer $token"; 'User-Agent' = 'mobius-actions-helper'; Accept = 'application/octet-stream' }
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Asset.url -Headers $headers -OutFile $dest -UseBasicParsing
    }
    $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dest).Hash.ToLower()
    $expected = if ($Sums) { $Sums[$Asset.name] } else { $null }
    if ($expected -and $expected -ne $hash) {
        throw ("SHA256 mismatch for {0}`n  expected {1}`n  actual   {2}" -f $Asset.name, $expected, $hash)
    }
    if ($expected) { Write-Host ("  sha256 OK ({0})" -f $hash) -ForegroundColor Green }
    else { Write-Host ("  sha256 {0} (release has no manifest entry)" -f $hash) -ForegroundColor Yellow }
    return $dest
}

# ---------------------------------------------------------------- resolve
if (-not $InstallDir) { $InstallDir = Join-Path $env:LOCALAPPDATA 'Programs\Mobius' }
if (-not (Test-Path -LiteralPath (Join-Path $InstallDir 'Mobius.exe'))) {
    throw "Mobius.exe not found under '$InstallDir'. Pass -InstallDir explicitly."
}
$InstallDir = (Resolve-Path -LiteralPath $InstallDir).Path
$currentVersion = Get-InstalledVersion -Dir $InstallDir
$currentTag = $null
$tagFile = Join-Path $InstallDir '.mobius-installed-tag'
if (Test-Path -LiteralPath $tagFile) {
    try { $currentTag = (Get-Content -LiteralPath $tagFile -Raw -Encoding UTF8).Trim() } catch {}
}
if (-not $currentTag -and $currentVersion) {
    $currentTag = if ($currentVersion -match '^v') { $currentVersion } else { "v$currentVersion" }
}

Write-Step "release"
$allReleases = Invoke-GhApi -Path "/repos/$Repo/releases"
$release = if ($Tag) {
    @($allReleases) | Where-Object { $_.tag_name -eq $Tag } | Select-Object -First 1
} else {
    @($allReleases) | Select-Object -First 1
}
if (-not $release) {
    $release = if ($Tag) { Invoke-GhApi -Path "/repos/$Repo/releases/tags/$Tag" } else { Invoke-GhApi -Path "/repos/$Repo/releases/latest" }
}
$Tag = $release.tag_name
Write-Host ("  target : {0}  (published {1})" -f $Tag, $release.published_at)
Write-Host ("  install: {0}" -f $InstallDir)
Write-Host ("  current: {0} ({1})" -f ($(if ($currentVersion) { $currentVersion } else { 'unknown' })), ($(if ($currentTag) { $currentTag } else { 'no tag' })))

$patchChain = if ($currentTag -and $Tag -and ($currentTag -ne $Tag)) {
    Find-MobiusPatchChain -Releases @($allReleases) -FromTag $currentTag -ToTag $Tag -Arch 'x64'
} else { $null }

$patchAsset = if ($patchChain -and $patchChain.Count -gt 0) { $patchChain[0].Asset } else {
    $release.assets | Where-Object { $_.name -like 'Mobius-Patch-*-win32-x64.zip' } | Select-Object -First 1
}
$setupAsset = $release.assets | Where-Object { $_.name -like 'Mobius-Setup-*-win32-x64.exe' -or $_.name -eq 'MobiusSetup.exe' } | Select-Object -First 1
$sumsAsset = $release.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1

switch ($Mode) {
    'patch' {
        if (-not $patchChain -and -not $patchAsset) {
            throw "No patch path found from $currentTag to $Tag, and release has no direct patch asset."
        }
    }
    'setup' {
        if (-not $setupAsset) { throw "Release $Tag has no setup asset." }
    }
    'auto' {
        if (-not $patchChain -and -not $patchAsset -and -not $setupAsset) {
            throw "Release $Tag has no usable asset."
        }
    }
}

if ($patchChain -and $patchChain.Count -gt 1) {
    $chainDesc = "$($patchChain[0].FromTag) -> " + (($patchChain | ForEach-Object { $_.ToTag }) -join ' -> ')
    $totalChainSize = ($patchChain | Measure-Object -Property Size -Sum).Sum
    Write-Host ("  patch  : {0} hops ({1:N1} MB): {2}" -f $patchChain.Count, ($totalChainSize / 1MB), $chainDesc)
} elseif ($patchChain -and $patchChain.Count -eq 1) {
    Write-Host ("  patch  : {0} ({1:N1} MB)" -f $patchChain[0].Name, ($patchChain[0].Size / 1MB))
} elseif ($patchAsset) {
    Write-Host ("  patch  : {0} ({1:N1} MB)" -f $patchAsset.name, ($patchAsset.size / 1MB))
} else {
    Write-Host "  patch  : not found (will fallback to setup)"
}
Write-Host ("  setup  : {0}" -f ($(if ($setupAsset) { "{0} ({1:N1} MB)" -f $setupAsset.name, ($setupAsset.size / 1MB) } else { 'not published' })))

if ($DryRun) {
    Write-Host ""
    Write-Host "DryRun: nothing downloaded or installed." -ForegroundColor Yellow
    return
}

# ---------------------------------------------------------------- preflight
$running = @(Get-Process -Name 'Mobius' -ErrorAction SilentlyContinue)
if ($running.Count -gt 0 -and -not $Force) {
    Write-Host ""
    Write-Host ("Mobius is running ({0} process(es)). Close it first, or re-run with -Force." -f $running.Count) -ForegroundColor Yellow
    Write-Host "Hint: right-click the tray icon -> Quit, then verify with: Get-Process Mobius" -ForegroundColor Yellow
    throw 'Mobius must be closed before an in-place update.'
}

$destDir = Join-Path (Get-Location) ("dist/release-$Tag")
New-Item -ItemType Directory -Force -Path $destDir | Out-Null

$sums = @{}
if ($sumsAsset) {
    $sumsPath = Join-Path $destDir 'SHA256SUMS.txt'
    $token = Get-GitHubToken
    Invoke-WebRequest -Uri $sumsAsset.url -Headers @{ Authorization = "Bearer $token"; 'User-Agent' = 'mobius-actions-helper'; Accept = 'application/octet-stream' } -OutFile $sumsPath -UseBasicParsing
    foreach ($line in Get-Content -LiteralPath $sumsPath) {
        if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') { $sums[$Matches[2].Trim()] = $Matches[1].ToLower() }
    }
}

# ---------------------------------------------------------------- update
$updated = $false
if ($Mode -in @('patch', 'auto') -and (($patchChain -and $patchChain.Count -gt 0) -or $patchAsset)) {
    $chainToApply = if ($patchChain -and $patchChain.Count -gt 0) {
        $patchChain
    } else {
        @([pscustomobject]@{
            FromTag = $currentTag
            ToTag   = $Tag
            Name    = $patchAsset.name
            Asset   = $patchAsset
            Size    = $patchAsset.size
        })
    }

    $chainCount = $chainToApply.Count
    Write-Step "incremental patch (chain: $chainCount hop(s))"

    $chainBackupDir = Join-Path $InstallDir '.chain-backup'
    if (Test-Path -LiteralPath $chainBackupDir) {
        Remove-Item -LiteralPath $chainBackupDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    try {
        for ($i = 0; $i -lt $chainCount; $i++) {
            $hop = $chainToApply[$i]
            $stepNum = $i + 1
            if ($chainCount -gt 1) {
                Write-Host ("  step [{0}/{1}]: {2} -> {3} ({4})" -f $stepNum, $chainCount, $hop.FromTag, $hop.ToTag, $hop.Name) -ForegroundColor Cyan
            } else {
                Write-Host ("  applying {0} ..." -f $hop.Name) -ForegroundColor Cyan
            }
            $patchZip = Save-Asset -Asset $hop.Asset -DestDir $destDir -Sums $sums
            $applyArgs = @{
                InstallDir      = $InstallDir
                PatchZip        = $patchZip
                ExpectedFromTag = $hop.FromTag
                ExpectedToTag   = $hop.ToTag
                ChainBackupDir  = $chainBackupDir
            }
            $patchSha = if ($sums) { $sums[$hop.Name] } else { $null }
            if ($patchSha) { $applyArgs.ExpectedSha256 = $patchSha }
            & (Join-Path $PSScriptRoot 'apply-delta.ps1') @applyArgs
        }
        $updated = $true
        Remove-Item -LiteralPath $chainBackupDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  patch chain applied successfully" -ForegroundColor Green
    }
    catch {
        Write-Host ("  patch failed: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
        if (Test-Path -LiteralPath $chainBackupDir) {
            Write-Host "  rolling back installation to initial state before patch chain..." -ForegroundColor Yellow
            try {
                $addedRecordFile = Join-Path $chainBackupDir '.added-files.txt'
                if (Test-Path -LiteralPath $addedRecordFile) {
                    $addedLines = [System.IO.File]::ReadAllLines($addedRecordFile, [System.Text.UTF8Encoding]::new($false))
                    foreach ($line in $addedLines) {
                        if ($line -and $line.Trim()) {
                            $targetAdded = Join-Path $InstallDir $line.Trim()
                            Remove-Item -LiteralPath $targetAdded -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                $backedFiles = Get-ChildItem -LiteralPath $chainBackupDir -Recurse -File
                foreach ($bf in $backedFiles) {
                    if ($bf.Name -eq '.added-files.txt') { continue }
                    $rel = $bf.FullName.Substring($chainBackupDir.Length).TrimStart('\', '/')
                    $dest = Join-Path $InstallDir $rel
                    $destParent = Split-Path $dest -Parent
                    if (-not (Test-Path -LiteralPath $destParent)) {
                        New-Item -ItemType Directory -Path $destParent -Force | Out-Null
                    }
                    Copy-Item -LiteralPath $bf.FullName -Destination $dest -Force
                }
                if ($currentTag) {
                    Set-Content -LiteralPath (Join-Path $InstallDir '.mobius-installed-tag') -Value $currentTag -Encoding UTF8 -Force
                }
            } finally {
                Remove-Item -LiteralPath $chainBackupDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
        if ($Mode -eq 'patch') { throw }
        Write-Host '  falling back to the official installer' -ForegroundColor Yellow
    }
}

if (-not $updated) {
    if (-not $setupAsset) { throw 'No setup asset available to fall back to.' }
    Write-Step "official installer"
    $setup = Save-Asset -Asset $setupAsset -DestDir $destDir -Sums $sums
    Write-Host "  running installer silently (this takes a few minutes) ..."
    $proc = Start-Process -FilePath $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/MERGETASKS=!runcode' -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw ("installer exited with code {0}" -f $proc.ExitCode) }
    $updated = $true
}

# ---------------------------------------------------------------- verify
Write-Step "verify"
$newVersion = Get-InstalledVersion -Dir $InstallDir
Write-Host ("  version: {0} -> {1}" -f ($(if ($currentVersion) { $currentVersion } else { 'unknown' })), ($(if ($newVersion) { $newVersion } else { 'unknown' })))
$stamp = Join-Path $InstallDir 'resources\app\package.json'
Write-Host ("  package.json last write: {0}" -f (Get-Item -LiteralPath $stamp).LastWriteTime)

if (-not $SkipHotpatch) {
    $hotpatch = Join-Path $PSScriptRoot 'hotpatch-session-maintain.ps1'
    if (Test-Path -LiteralPath $hotpatch) {
        Write-Step "re-apply session maintenance hotpatch"
        try { & $hotpatch -Apply -RegisterTasks } catch { Write-Host ("  hotpatch skipped: {0}" -f $_.Exception.Message) -ForegroundColor Yellow }
    }
}

Write-Host ""
Write-Host "Done. Start Mobius and run the health check:" -ForegroundColor Green
Write-Host "  powershell -ExecutionPolicy Bypass -File .\tools\mobius-auto-maintain.ps1 -Mode Check"