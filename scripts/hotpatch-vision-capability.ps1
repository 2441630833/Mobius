<#
.SYNOPSIS
    Mobius 识图能力热补丁：让已安装的 Mobius 不再因为模型"没声明 image_input"就丢掉图片。

.DESCRIPTION
    背景（源码层已修，见 commit）：
        - vscode：continue 的 vision 能力改为"声明优先 + 名称启发式 + 未知默认放行"
        - continue：uploadImage 不再是 capabilities.includes('image_input') 的硬开关

    但已安装的 Mobius 跑的是旧构建产物，重新安装/升级前想立刻生效，就用本脚本给两个
    打包文件打最小热补丁（只改 1 处常量，语义 = "所有 continue 模型都允许收图"）：

        resources\app\out\vs\workbench\workbench.desktop.main.js
            vision:<压缩后的函数名>(o.model)   ->   vision:!0
        resources\app\extensions\continue\out\extension.js
            uploadImage: model.capabilities?.includes("image_input"),
                                            ->   uploadImage: !0,

    原文件备份为 *.bak-visionhotfix，可用 -Revert 还原。升级应用后需要重跑 -Apply。

.PARAMETER Apply
    打补丁（幂等：已经打过会跳过）。

.PARAMETER Verif
    只校验补丁是否在位。

.PARAMETER Revert
    从 *.bak-visionhotfix 还原原始构建产物。

.PARAMETER InstallRoot
    覆盖默认安装目录（默认 %LOCALAPPDATA%\Programs\Mobius\resources\app）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-vision-capability.ps1 -Apply

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-vision-capability.ps1 -Verif

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-vision-capability.ps1 -Revert
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Apply,
    [switch]$Verif,
    [switch]$Revert,
    [string]$InstallRoot
)

$ErrorActionPreference = 'Stop'

$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Step { param([string]$Text) Write-Host ''; Write-Host "== $Text" -ForegroundColor Cyan }
function Write-Ok { param([string]$Text) Write-Host "   [OK]   $Text" -ForegroundColor Green }
function Write-Bad { param([string]$Text) Write-Host "   [FAIL] $Text" -ForegroundColor Red }
function Write-Info { param([string]$Text) Write-Host "   $Text" -ForegroundColor Gray }

function Get-AppRoot {
    if ($InstallRoot) { return $InstallRoot }
    return (Join-Path $env:LOCALAPPDATA 'Programs\Mobius\resources\app')
}

# 每项：文件（相对 app 根）、已打补丁的判定正则、待替换正则、替换文本
$Targets = @(
    [pscustomobject]@{
        Name    = 'workbench.desktop.main.js'
        RelPath = 'out\vs\workbench\workbench.desktop.main.js'
        Patched = 'vision:!0'
        Pattern = 'vision:[A-Za-z_$][A-Za-z0-9_$]*\(o\.model\)'
        Replace = 'vision:!0'
    },
    [pscustomobject]@{
        Name    = 'extension.js (continue)'
        RelPath = 'extensions\continue\out\extension.js'
        Patched = 'uploadImage: !0,'
        Pattern = 'uploadImage:\s*model\.capabilities\?\.includes\("image_input"\)'
        Replace = 'uploadImage: !0'
    }
)

function Get-TargetPath { param($Target) return (Join-Path (Get-AppRoot) $Target.RelPath) }

function Test-Patched {
    param($Target, [string]$Text)
    return ([regex]::Matches($Text, [regex]::Escape($Target.Patched))).Count -gt 0
}

# ================================================================ Verif

if ($Verif) {
    Write-Step '校验识图能力热补丁'
    $fail = 0
    $root = Get-AppRoot
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Bad "找不到应用目录：$root"
        exit 1
    }
    foreach ($t in $Targets) {
        $path = Get-TargetPath $t
        if (-not (Test-Path -LiteralPath $path)) { Write-Bad "缺失：$path"; $fail++; continue }
        $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
        if (Test-Patched $t $text) {
            Write-Ok "$($t.Name) 已打补丁"
        }
        else {
            Write-Bad "$($t.Name) 未打补丁（图片仍可能被本地丢弃）"
            $fail++
        }
    }
    Write-Host ''
    if ($fail -eq 0) { Write-Host '热补丁在位。请完全退出并重启 Mobius 后生效。' -ForegroundColor Green; exit 0 }
    Write-Host "校验失败 $fail 项：运行 -Apply 打补丁。" -ForegroundColor Red
    exit 1
}

# ================================================================ Revert

if ($Revert) {
    Write-Step '还原识图能力热补丁'
    foreach ($t in $Targets) {
        $path = Get-TargetPath $t
        $bak = "$path.bak-visionhotfix"
        if (Test-Path -LiteralPath $bak) {
            Copy-Item -LiteralPath $bak -Destination $path -Force
            Write-Ok "已还原：$($t.Name)"
        }
        else {
            Write-Info "无备份，跳过：$($t.Name)"
        }
    }
    exit 0
}

# ================================================================ Apply

Write-Step '打入识图能力热补丁'
$root = Get-AppRoot
if (-not (Test-Path -LiteralPath $root)) {
    throw "找不到应用目录：$root（可用 -InstallRoot 指定）"
}

$changed = 0
foreach ($t in $Targets) {
    $path = Get-TargetPath $t
    if (-not (Test-Path -LiteralPath $path)) { Write-Bad "缺失：$path"; continue }
    $text = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
    if (Test-Patched $t $text) { Write-Info "已是补丁状态，跳过：$($t.Name)"; continue }

    $matches = [regex]::Matches($text, $t.Pattern)
    if ($matches.Count -ne 1) {
        Write-Bad "$($t.Name)：匹配到 $($matches.Count) 处（期望 1），跳过以免破坏构建产物"
        continue
    }

    $bak = "$path.bak-visionhotfix"
    if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $path -Destination $bak -Force }

    $patched = [regex]::Replace($text, $t.Pattern, $t.Replace)
    [System.IO.File]::WriteAllText($path, $patched, $Utf8NoBom)
    Write-Ok "$($t.Name)：$($matches[0].Value) -> $($t.Replace)"
    $changed++
}

Write-Host ''
if ($changed -eq 0) {
    Write-Info '没有需要修改的文件（可能已打过补丁，或应用版本已包含源码修复）。'
}
else {
    Write-Ok "已修改 $changed 个构建产物；备份后缀 .bak-visionhotfix"
}
Write-Info '完全退出并重新启动 Mobius 后生效；升级应用后重跑 -Apply。'
exit 0