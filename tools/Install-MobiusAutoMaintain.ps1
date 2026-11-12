<#
.SYNOPSIS
    把 Mobius 会话自动化维护注册成 Windows 计划任务（安装 / 卸载 / 查看状态）。

.DESCRIPTION
    配套脚本：tools\mobius-auto-maintain.ps1

    注册的任务（全部以当前用户身份运行，不需要管理员权限）：

      <Prefix>-Daily     每天 12:30      -Mode Auto   体检；超阈值才清理
      <Prefix>-Logon     登录后 3 分钟    -Mode Auto   专治"一开机就卡死"
      <Prefix>-Weekly    每周日 13:00     -Mode Clean -IncludeHistory  深度清理
      <Prefix>-Watchdog  每 30 分钟       -Mode Check  只体检（-Watchdog 时注册）

    运行结果写入 %USERPROFILE%\MobiusArchive\maintain.log 与 reports\。

.PARAMETER Install
    注册 / 覆盖安装计划任务（默认动作）。

.PARAMETER Uninstall
    删除全部由本脚本注册的计划任务。

.PARAMETER Status
    查看任务状态 + 最近一次体检报告。

.PARAMETER Watchdog
    额外注册每 30 分钟一次的体检任务（默认不注册，避免无谓 IO）。

.PARAMETER RunNow
    安装完成后立刻跑一次 -Mode Check，验证链路可用。

.PARAMETER MaxProcessMB
    传给维护脚本的内存阈值（默认 2048）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-MobiusAutoMaintain.ps1 -Install -RunNow

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-MobiusAutoMaintain.ps1 -Status

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\Install-MobiusAutoMaintain.ps1 -Uninstall
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$Status,
    [switch]$Watchdog,
    [switch]$RunNow,

    [int]$MaxProcessMB = 2048,
    [string]$ArchiveRoot = (Join-Path $env:USERPROFILE 'MobiusArchive'),
    [string]$TaskPrefix = 'MobiusAutoMaintain'
)

$ErrorActionPreference = 'Stop'

function Write-Step {
    param([string]$Text)
    Write-Host ''
    Write-Host "== $Text" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Text)
    Write-Host "   $Text" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Text)
    Write-Host "   $Text" -ForegroundColor Yellow
}

$maintainer = Join-Path $PSScriptRoot 'mobius-auto-maintain.ps1'
if (-not (Test-Path -LiteralPath $maintainer)) {
    throw "找不到维护脚本：$maintainer（请确保两个脚本在同一目录）。"
}

function New-MaintainAction {
    param([string[]]$Extra)
    $parts = @(
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle', 'Hidden',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $maintainer),
        '-ArchiveRoot', ('"{0}"' -f $ArchiveRoot),
        '-MaxProcessMB', "$MaxProcessMB"
    )
    if ($Extra) { $parts += $Extra }
    return New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ($parts -join ' ')
}

function New-MaintainSettings {
    return New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)
}

function Register-MaintainTask {
    param(
        [string]$Name,
        [object]$Action,
        [object]$Trigger,
        [object]$Settings,
        [string]$Description
    )
    $existing = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction SilentlyContinue
    }
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $Name -Action $Action -Trigger $Trigger -Settings $Settings `
        -Principal $principal -Description $Description | Out-Null
    Write-Ok "已注册任务：$Name"
}

# ================================================================ 分支

if ($Uninstall) {
    Write-Step '卸载 Mobius 自动化维护任务'
    $tasks = @(Get-ScheduledTask -TaskName ($TaskPrefix + '*') -ErrorAction SilentlyContinue)
    if ($tasks.Count -eq 0) {
        Write-Warn '没有找到已注册的任务，无需卸载。'
        return
    }
    foreach ($t in $tasks) {
        try {
            Unregister-ScheduledTask -TaskName $t.TaskName -Confirm:$false -ErrorAction Stop
            Write-Ok "已删除：$($t.TaskName)"
        }
        catch {
            Write-Warn "删除失败：$($t.TaskName) - $($_.Exception.Message)"
        }
    }
    Write-Host ''
    Write-Host '完成。归档目录 MobiusArchive 未删除，需要时请手动清理。' -ForegroundColor Green
    return
}

if ($Status) {
    Write-Step 'Mobius 自动化维护任务状态'
    $tasks = @(Get-ScheduledTask -TaskName ($TaskPrefix + '*') -ErrorAction SilentlyContinue)
    if ($tasks.Count -eq 0) {
        Write-Warn '尚未注册任何任务，运行 -Install 即可。'
    }
    else {
        $rows = @()
        foreach ($t in $tasks) {
            $info = $null
            try { $info = $t | Get-ScheduledTaskInfo } catch { }
            $rows += [pscustomobject]@{
                任务     = $t.TaskName
                状态     = [string]$t.State
                上次运行 = if ($info) { [string]$info.LastRunTime } else { '' }
                上次结果 = if ($info) { [string]$info.LastTaskResult } else { '' }
                下次运行 = if ($info) { [string]$info.NextRunTime } else { '' }
            }
        }
        $rows | Format-Table -AutoSize | Out-String -Width 200 | Write-Host
    }

    $report = Join-Path $ArchiveRoot 'last-report.json'
    if (Test-Path -LiteralPath $report) {
        Write-Host "最近一次报告：$report" -ForegroundColor Green
        $raw = Get-Content -LiteralPath $report -Raw -Encoding UTF8
        Write-Host $raw
    }
    else {
        Write-Warn '还没有生成过报告，先跑一次 -Mode Check。'
    }
    return
}

# ================================================================ 安装

Write-Step '注册 Mobius 自动化维护计划任务'
Write-Host "   维护脚本：$maintainer"
Write-Host "   归档目录：$ArchiveRoot"

$settings = New-MaintainSettings
$userName = "$env:USERDOMAIN\$env:USERNAME"

# 1) 每天 12:30 体检 + 必要时清理
Register-MaintainTask -Name ($TaskPrefix + '-Daily') `
    -Action (New-MaintainAction -Extra @('-Mode', 'Auto', '-Quiet')) `
    -Trigger (New-ScheduledTaskTrigger -Daily -At '12:30') `
    -Settings $settings `
    -Description 'Mobius 会话体检；超过阈值时自动归档旧会话、轮转日志、压缩 state.vscdb。'

# 2) 登录后 3 分钟（启动瞬间最卡的时段）
$logonTrigger = New-ScheduledTaskTrigger -AtLogOn -User $userName
$logonTrigger.Delay = 'PT3M'
Register-MaintainTask -Name ($TaskPrefix + '-Logon') `
    -Action (New-MaintainAction -Extra @('-Mode', 'Auto', '-Quiet')) `
    -Trigger $logonTrigger `
    -Settings $settings `
    -Description 'Mobius 登录后体检并清理，避免启动时解析过多会话导致卡死。'

# 3) 每周日 13:00 深度清理（含 History）
Register-MaintainTask -Name ($TaskPrefix + '-Weekly') `
    -Action (New-MaintainAction -Extra @('-Mode', 'Clean', '-IncludeHistory', '-Quiet')) `
    -Trigger (New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '13:00') `
    -Settings $settings `
    -Description 'Mobius 每周深度清理：会话归档 + History 精简 + state.vscdb 压缩。'

# 4) 可选看门狗：每 30 分钟只体检，用于发现内存爬升
if ($Watchdog) {
    $startAt = (Get-Date).AddMinutes(5)
    $trigger = New-ScheduledTaskTrigger -Once -At $startAt `
        -RepetitionInterval (New-TimeSpan -Minutes 30) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
    Register-MaintainTask -Name ($TaskPrefix + '-Watchdog') `
        -Action (New-MaintainAction -Extra @('-Mode', 'Check', '-Quiet')) `
        -Trigger $trigger `
        -Settings $settings `
        -Description '每 30 分钟只体检 Mobius 内存与会话规模，结果写入 maintain.log 与 reports。'
}

Write-Host ''
Write-Ok '全部任务注册完成。'
Write-Host '   立刻验证：' -NoNewline
Write-Host "powershell -ExecutionPolicy Bypass -File `"$maintainer`" -Mode Check" -ForegroundColor Gray

if ($RunNow) {
    Write-Step '立刻执行一次体检'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $maintainer -Mode Check -ArchiveRoot $ArchiveRoot -MaxProcessMB $MaxProcessMB
    Write-Host ''
    Write-Ok "体检完成，退出码 $LASTEXITCODE（0=健康 1=留意 2=风险 4=出错）。"
}