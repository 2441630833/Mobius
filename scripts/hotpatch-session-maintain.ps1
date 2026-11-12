<#
.SYNOPSIS
    Mobius 会话维护热补丁：把自动化维护工具部署进已安装的 Mobius，并可校验 / 卸载 / 打包。

.DESCRIPTION
    配套文件（仓库内）：
        tools\mobius-auto-maintain.ps1
        tools\Install-MobiusAutoMaintain.ps1
        tools\mobius-体检.cmd / mobius-清理演练.cmd / mobius-一键清理.cmd / mobius-开启自动化.cmd

    热补丁产物：
        <InstallRoot>\mobius-maintain\...       部署后的脚本
        <InstallRoot>\mobius-maintain\HOTPATCH.json   版本 / 时间 / SHA256 清单 / 来源仓库

    InstallRoot 默认 %LOCALAPPDATA%\Programs\Mobius\resources\app，
    即"补丁随应用走"，升级应用后重跑一次 -Apply 即可。

.PARAMETER Apply
    部署热补丁（覆盖旧版本）。

.PARAMETER Verif
    只校验：文件是否齐全、SHA256 是否匹配、计划任务是否注册。只读。

.PARAMETER Uninstall
    删除已部署的热补丁目录（以及 -RegisterTasks 注册的计划任务）。

.PARAMETER MakeDist
    在 dist\ 下生成可分发 zip（含脚本 + 一键安装 cmd + 校验清单）。

.PARAMETER RegisterTasks
    Apply 时顺便注册 Windows 计划任务（等同运行 Install-MobiusAutoMaintain.ps1 -Install）。

.PARAMETER InstallRoot
    覆盖默认部署目录（测试用）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-session-maintain.ps1 -Apply -RegisterTasks

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-session-maintain.ps1 -Verif

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-session-maintain.ps1 -MakeDist
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Verif,
    [switch]$Uninstall,
    [switch]$MakeDist,
    [switch]$RegisterTasks,
    [string]$InstallRoot,
    [string]$Version = '1.1.0'
)

$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Parent $PSScriptRoot
$ToolDir = Join-Path $RepoRoot 'tools'
$FolderName = 'mobius-maintain'
$TaskPrefix = 'MobiusAutoMaintain'

$PayloadFiles = @(
    'mobius-auto-maintain.ps1',
    'Install-MobiusAutoMaintain.ps1',
    'mobius-体检.cmd',
    'mobius-清理演练.cmd',
    'mobius-一键清理.cmd',
    'mobius-开启自动化.cmd'
)

# 可分发 zip 解压后的场景：脚本与载荷同目录，不再位于 <repo>\scripts 下
if (-not (Test-Path -LiteralPath (Join-Path $ToolDir 'mobius-auto-maintain.ps1'))) {
    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'mobius-auto-maintain.ps1')) {
        $ToolDir = $PSScriptRoot
    }
}

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host "== $Text" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host "   [OK]   $Text" -ForegroundColor Green
}

function Write-Bad {
    param([string]$Text)
    Write-Host "   [FAIL] $Text" -ForegroundColor Red
}

function Write-Info {
    param([string]$Text)
    Write-Host "   $Text" -ForegroundColor Gray
}

function Resolve-DefaultInstallRoot {
    $p = Join-Path $env:LOCALAPPDATA 'Programs\Mobius\resources\app'
    return $p
}

function Get-TargetRoot {
    if ($InstallRoot) { return (Join-Path $InstallRoot $FolderName) }
    return (Join-Path (Resolve-DefaultInstallRoot) $FolderName)
}

function Get-Sha256 {
    param([string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Assert-Payload {
    $missing = @()
    foreach ($f in $PayloadFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $ToolDir $f))) { $missing += $f }
    }
    if ($missing.Count -gt 0) {
        throw ("源脚本缺失：{0}（请在仓库根目录运行本脚本）" -f ($missing -join ', '))
    }
}

# ================================================================ MakeDist

if ($MakeDist) {
    Write-Step "构建分发包 v$Version"
    Assert-Payload

    $distDir = Join-Path $RepoRoot 'dist'
    if (-not (Test-Path -LiteralPath $distDir)) { New-Item -ItemType Directory -Path $distDir -Force | Out-Null }
    $stage = Join-Path $env:TEMP ("mobius-maintain-dist-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $pkgName = "mobius-maintain-hotpatch-v$Version"
    $pkgRoot = Join-Path $stage $pkgName
    New-Item -ItemType Directory -Path $pkgRoot -Force | Out-Null

    foreach ($f in $PayloadFiles) {
        Copy-Item -LiteralPath (Join-Path $ToolDir $f) -Destination $pkgRoot -Force
    }

    # 一键安装 cmd
    $installCmd = @'
@echo off
rem One-click install: deploy scripts into the installed Mobius app and register tasks
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0hotpatch-session-maintain.ps1" -Apply -RegisterTasks
pause
'@
    [System.IO.File]::WriteAllText((Join-Path $pkgRoot 'install.cmd'), ($installCmd -replace "`r?`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))

    # 校验 cmd
    $verifyCmd = @'
@echo off
rem Verify deployed hot patch (read-only)
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0hotpatch-session-maintain.ps1" -Verif
pause
'@
    [System.IO.File]::WriteAllText((Join-Path $pkgRoot 'verify.cmd'), ($verifyCmd -replace "`r?`n", "`r`n"), (New-Object System.Text.ASCIIEncoding))

    # 把热补丁脚本自身也放进包里，这样解压即可安装
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'hotpatch-session-maintain.ps1') -Destination $pkgRoot -Force

    $manifest = @()
    foreach ($f in (Get-ChildItem -LiteralPath $pkgRoot -File | Sort-Object Name)) {
        $manifest += [pscustomobject]@{ name = $f.Name; sha256 = (Get-Sha256 $f.FullName); bytes = $f.Length }
    }
    $manifest | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $pkgRoot 'CHECKSUMS.json') -Encoding UTF8

    $zipPath = Join-Path $distDir ("{0}.zip" -f $pkgName)
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    # 只打包 $pkgName 这一层，解压后得到 mobius-maintain-hotpatch-vX.Y.Z\ 根目录
    [System.IO.Compression.ZipFile]::CreateFromDirectory($pkgRoot, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue

    Write-Ok "已生成：$zipPath"
    Write-Info ("包含 {0} 个文件，大小 {1:N1} KB" -f $manifest.Count, ((Get-Item -LiteralPath $zipPath).Length / 1KB))
    exit 0
}

# ================================================================ Verif

if ($Verif) {
    Write-Step "校验热补丁 v$Version"
    $target = Get-TargetRoot
    $marker = Join-Path $target 'HOTPATCH.json'
    $fail = 0

    if (-not (Test-Path -LiteralPath $marker)) {
        Write-Bad "未安装：找不到 $marker"
        Write-Info '先运行：powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-session-maintain.ps1 -Apply'
        exit 1
    }

    $meta = Get-Content -LiteralPath $marker -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Info ("部署目录：{0}" -f $target)
    Write-Info ("补丁版本：{0}（{1}）" -f $meta.version, $meta.appliedAt)

    foreach ($entry in $meta.files) {
        $path = Join-Path $target $entry.name
        if (-not (Test-Path -LiteralPath $path)) {
            Write-Bad "缺失：$($entry.name)"
            $fail++
            continue
        }
        $actual = Get-Sha256 $path
        if ($actual -ne $entry.sha256) {
            Write-Bad "被改动或损坏：$($entry.name)"
            $fail++
        }
        else {
            Write-Ok "校验通过：$($entry.name)"
        }
    }

    $tasks = @(Get-ScheduledTask -TaskName ($TaskPrefix + '*') -ErrorAction SilentlyContinue)
    if ($tasks.Count -gt 0) {
        Write-Ok ("计划任务已注册：{0} 个（{1}）" -f $tasks.Count, (($tasks | ForEach-Object { $_.TaskName }) -join ', '))
    }
    else {
        Write-Info '计划任务未注册（需要自动化时运行 install.cmd 或 -Apply -RegisterTasks）'
    }

    Write-Host ''
    if ($fail -eq 0) {
        Write-Host '热补丁在线，文件与清单一致。' -ForegroundColor Green
        exit 0
    }
    Write-Host "校验失败 $fail 项：请重新 -Apply 覆盖安装。" -ForegroundColor Red
    exit 1
}

# ================================================================ Uninstall

if ($Uninstall) {
    Write-Step '卸载热补丁'
    $tasks = @(Get-ScheduledTask -TaskName ($TaskPrefix + '*') -ErrorAction SilentlyContinue)
    foreach ($t in $tasks) {
        try {
            Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction Stop
            Write-Ok "已删除任务：$($t.TaskName)"
        }
        catch { Write-Bad "删除任务失败：$($t.TaskName)" }
    }
    $target = Get-TargetRoot
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
        Write-Ok "已删除目录：$target"
    }
    else {
        Write-Info '没有找到已部署目录，无需删除。'
    }
    Write-Info '归档目录 MobiusArchive 不受影响，需要时请手动清理。'
    exit 0
}

# ================================================================ Apply（默认）

Write-Step "部署热补丁 v$Version"
Assert-Payload

$root = if ($InstallRoot) { $InstallRoot } else { Resolve-DefaultInstallRoot }
$target = Get-TargetRoot
if (-not (Test-Path -LiteralPath $root)) {
    throw "目标根目录不存在：$root（Mobius 是否安装在默认位置？可用 -InstallRoot 指定）"
}
if (-not (Test-Path -LiteralPath $target)) { New-Item -ItemType Directory -Path $target -Force | Out-Null }

$entries = @()
foreach ($f in $PayloadFiles) {
    $src = Join-Path $ToolDir $f
    $dst = Join-Path $target $f
    Copy-Item -LiteralPath $src -Destination $dst -Force
    $entries += [pscustomobject]@{ name = $f; sha256 = (Get-Sha256 $dst); bytes = (Get-Item -LiteralPath $dst).Length }
    Write-Info "已部署：$f"
}

$meta = [pscustomobject]@{
    name      = 'mobius-session-maintain'
    version   = $Version
    appliedAt = (Get-Date).ToString('s')
    repoRoot  = $RepoRoot
    files     = $entries
}
$meta | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $target 'HOTPATCH.json') -Encoding UTF8
Write-Ok "已写入清单：$(Join-Path $target 'HOTPATCH.json')"

if ($RegisterTasks) {
    Write-Step '注册计划任务'
    $installer = Join-Path $target 'Install-MobiusAutoMaintain.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -Install
    Write-Ok '计划任务注册完成。'
}
else {
    Write-Info '未注册计划任务（需要自动化时加 -RegisterTasks，或运行部署目录里的 mobius-开启自动化.cmd）'
}

Write-Host ''
Write-Ok "热补丁部署完成：$target"
Write-Info ("自检：powershell -ExecutionPolicy Bypass -File `"{0}`" -Verif" -f (Join-Path $PSScriptRoot 'hotpatch-session-maintain.ps1'))
exit 0