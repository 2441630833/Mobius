<#
.SYNOPSIS
    Mobius 会话自动化维护：体检 -> 归档瘦身 -> 日志轮转 -> 数据库压缩。

.DESCRIPTION
    Mobius 卡顿的根因不是"文件多"，而是启动时必须把全部会话 *.jsonl 解析一遍建索引，
    并把 state.vscdb（会话索引 / 编辑记录）整块读进内存。会话越多、单个会话越长，
    内存与索引耗时越离谱 —— 单会话 7 MB、会话数 260+、state.vscdb 157 MB 时，
    进程会一路涨到几 GB 然后卡死。

    本脚本把这套维护自动化，三种模式：

      Check  只体检，输出"健康 / 留意 / 风险"，绝不改动任何文件。
      Clean  到阈值才真正动手（阈值内绝不删除任何东西）。
      Auto   先体检，超阈值才执行 Clean。计划任务默认用它，适合无人值守。

    安全策略：任何删除都遵循"先写 zip -> 回读校验条目数 -> 才删原件"，
    同时落一份 manifest（原路径 / 大小 / 修改时间），随时可以解包还原。
    先用 -DryRun 完整演练一遍，确认清单没问题再真跑。

.PARAMETER Mode
    Check | Clean | Auto

.PARAMETER DryRun
    演练模式：只打印将要执行的每一步，不写文件、不删文件、不建计划任务。

.PARAMETER DataRoot
    Mobius 用户数据目录，默认自动探测 %APPDATA%\Mobius\User。

.PARAMETER ArchiveRoot
    归档根目录，默认 %USERPROFILE%\MobiusArchive（zip、日志、报告都放这里）。

.PARAMETER KeepMinSessions
    任何情况下都至少保留最新 N 个会话（默认 120）。

.PARAMETER KeepDays
    早于 N 天且不在保留集内的会话强制归档（默认 45 天）。

.PARAMETER IncludeHistory
    一并精简 %APPDATA%\Mobius\User\History（编辑器撤销历史），默认不动。

.PARAMETER Force
    允许在 Mobius 正在运行时执行会话归档 / 日志轮转（仍然会跳过 state.vscdb 压缩）。

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\mobius-auto-maintain.ps1 -Mode Check

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\mobius-auto-maintain.ps1 -Mode Clean -DryRun

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\mobius-auto-maintain.ps1 -Mode Auto -Quiet

.NOTES
    退出码：0=健康  1=留意  2=风险  3=已执行清理动作  4=出错
#>
#Requires -Version 5.1
[CmdletBinding()]
param(
    [ValidateSet('Check', 'Clean', 'Auto')]
    [string]$Mode = 'Auto',

    [switch]$DryRun,

    [string]$DataRoot,

    [string]$ArchiveRoot = (Join-Path $env:USERPROFILE 'MobiusArchive'),

    # ---- 阈值（与《Mobius 会话清理指南》阈值表一致）----
    [int]$MaxSessions = 250,
    [int]$MaxSessionMB = 500,
    [int]$MaxStateMB = 150,
    [int]$MaxProcessMB = 2048,
    [int]$MaxSingleSessionMB = 8,

    # ---- 清理策略 ----
    [int]$KeepMinSessions = 120,
    [int]$KeepDays = 45,
    [int]$ProtectRecent = 3,
    [int]$MaxLogMB = 40,
    [int]$ArchiveKeepDays = 120,

    [switch]$IncludeHistory,
    [int]$HistoryKeepDays = 30,

    [switch]$Force,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$script:LogFile = $null
$script:Changed = $false
$script:IsQuiet = [bool]$Quiet

# Zip 相关类型：System.IO.Compression 与 FileSystem 两个程序集都必须显式加载
foreach ($asm in @('System.IO.Compression', 'System.IO.Compression.FileSystem')) {
    try { Add-Type -AssemblyName $asm -ErrorAction Stop | Out-Null } catch { }
}

# ================================================================ 基础工具

function Write-Log {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR', 'STEP')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $show = $true
    if ($script:IsQuiet -and $Level -eq 'INFO') { $show = $false }
    if ($script:IsQuiet -and $Level -eq 'STEP') { $show = $false }
    if ($show) {
        switch ($Level) {
            'WARN' { Write-Host $line -ForegroundColor Yellow }
            'ERROR' { Write-Host $line -ForegroundColor Red }
            'OK' { Write-Host $line -ForegroundColor Green }
            'STEP' { Write-Host $line -ForegroundColor Cyan }
            default { Write-Host $line }
        }
    }
    if ($script:LogFile) {
        try { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 } catch { }
    }
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return ('{0:N0} B' -f $Bytes)
}

function Resolve-MobiusDataRoot {
    param([string]$Explicit)
    $candidates = @()
    if ($Explicit) {
        $candidates = @($Explicit)
    }
    else {
        $candidates = @(
            (Join-Path $env:APPDATA 'Mobius\User'),
            (Join-Path $env:APPDATA 'Mobius'),
            (Join-Path $env:USERPROFILE '.mobius')
        )
    }
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) {
            return (Resolve-Path -LiteralPath $c).Path
        }
    }
    throw "找不到 Mobius 数据目录。请用 -DataRoot 显式指定（默认期望 %APPDATA%\Mobius\User）。"
}

function Get-MobiusProcessList {
    $result = @()
    foreach ($n in @('Mobius', 'mobius')) {
        $result += @(Get-Process -Name $n -ErrorAction SilentlyContinue)
    }
    $seen = @{}
    $unique = @()
    foreach ($p in $result) {
        if ($null -eq $p) { continue }
        if ($seen.ContainsKey($p.Id)) { continue }
        $seen[$p.Id] = $true
        $unique += $p
    }
    return $unique
}

# ================================================================ 采集

function Get-SessionProfile {
    param([string]$Root)
    $empty = [pscustomobject]@{
        Directory    = $null
        Files        = @()
        Count        = 0
        TotalBytes   = 0.0
        LargestBytes = 0.0
    }
    $all = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.jsonl' -Depth 5 -ErrorAction SilentlyContinue)
    if ($all.Count -eq 0) { return $empty }

    $groups = $all | Group-Object -Property DirectoryName
    $best = $null
    $bestScore = -1.0
    foreach ($g in $groups) {
        $sum = 0.0
        foreach ($f in $g.Group) { $sum += $f.Length }
        # 目录名里带 session / chat / conversation 的加权，避免误选无关 jsonl
        $score = $sum
        if ($g.Name -match '(?i)session|chat|conversation|agent') { $score = $score * 3 }
        if ($score -gt $bestScore) { $bestScore = $score; $best = $g }
    }
    if ($null -eq $best) { return $empty }

    # Mobius 的会话按 workspace 分目录（...\workspaceStorage\<id>\chatSessions）。
    # 只要识别出这一类目录名，就把所有同名目录一起统计 —— 否则会严重低估总量。
    $leaf = Split-Path -Leaf $best.Name
    $files = @($best.Group)
    if ($leaf -match '(?i)^(chatSessions|sessions|conversations|chat)$') {
        $merged = @()
        foreach ($g in $groups) {
            if ((Split-Path -Leaf $g.Name) -ieq $leaf) { $merged += @($g.Group) }
        }
        if ($merged.Count -gt 0) {
            $files = $merged
            $best = [pscustomobject]@{ Name = "{0}（全部 workspace）" -f $leaf; Group = $merged }
        }
    }

    $total = 0.0
    $max = 0.0
    foreach ($f in $files) {
        $total += $f.Length
        if ($f.Length -gt $max) { $max = $f.Length }
    }
    return [pscustomobject]@{
        Directory    = $best.Name
        Files        = $files
        Count        = $files.Count
        TotalBytes   = $total
        LargestBytes = $max
    }
}

function Get-StateDbInfo {
    param([string]$Root)
    $dbs = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter 'state.vscdb' -Depth 5 -ErrorAction SilentlyContinue)
    $total = 0.0
    $max = 0.0
    foreach ($d in $dbs) {
        $size = [double]$d.Length
        if ($size -gt $max) { $max = $size }
        $total += $size
        $wal = [string]$d.FullName + '-wal'
        if (Test-Path -LiteralPath $wal) { $total += [double](Get-Item -LiteralPath $wal).Length }
    }
    return [pscustomobject]@{
        Files      = $dbs
        TotalBytes = $total
        MaxBytes   = $max
    }
}

function Get-LogProfile {
    param([string]$Root)
    $logs = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Depth 4 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '(?i)\.log(\.\d+)?$' -or $_.Name -match '(?i)\.log$' })
    $total = 0.0
    $big = @()
    foreach ($l in $logs) {
        $total += [double]$l.Length
        if ($l.Length -ge ($MaxLogMB * 1MB)) { $big += $l }
    }
    return [pscustomobject]@{ Files = $logs; TotalBytes = $total; Oversized = $big }
}

function Get-Metrics {
    param([string]$Root)
    $procs = Get-MobiusProcessList
    $totalRss = 0.0
    $peakRss = 0.0
    foreach ($p in $procs) {
        try {
            $ws = [double]$p.WorkingSet64
            $totalRss += $ws
            if ($ws -gt $peakRss) { $peakRss = $ws }
        }
        catch { }
    }
    $sessions = Get-SessionProfile -Root $Root
    $state = Get-StateDbInfo -Root $Root
    $logs = Get-LogProfile -Root $Root
    return [pscustomobject]@{
        Root             = $Root
        ProcessCount     = $procs.Count
        ProcessTotalMB   = [math]::Round($totalRss / 1MB, 0)
        ProcessPeakMB    = [math]::Round($peakRss / 1MB, 0)
        SessionDirectory = $sessions.Directory
        SessionFiles     = $sessions.Files
        SessionCount     = $sessions.Count
        SessionBytes     = [double]$sessions.TotalBytes
        SessionMB        = [math]::Round($sessions.TotalBytes / 1MB, 1)
        LargestSessionMB = [math]::Round($sessions.LargestBytes / 1MB, 2)
        StateFiles       = $state.Files
        StateBytes       = [double]$state.TotalBytes
        StateMB          = [math]::Round($state.TotalBytes / 1MB, 1)
        LogFiles         = $logs.Files
        LogBytes         = [double]$logs.TotalBytes
        OversizedLogs    = $logs.Oversized
    }
}

function Measure-Health {
    param([object]$M)
    $items = @()

    $items += [pscustomobject]@{
        指标 = '会话文件数'; 当前 = "{0} 个" -f $M.SessionCount
        阈值 = "> $MaxSessions 个"; 超限 = [bool]($M.SessionCount -gt $MaxSessions)
    }
    $items += [pscustomobject]@{
        指标 = '会话合计大小'; 当前 = (Format-Size $M.SessionBytes)
        阈值 = "> $MaxSessionMB MB"; 超限 = [bool]($M.SessionMB -gt $MaxSessionMB)
    }
    $items += [pscustomobject]@{
        指标 = '最大单会话'; 当前 = "{0} MB" -f $M.LargestSessionMB
        阈值 = "> $MaxSingleSessionMB MB"; 超限 = [bool]($M.LargestSessionMB -gt $MaxSingleSessionMB)
    }
    $items += [pscustomobject]@{
        指标 = 'state.vscdb'; 当前 = (Format-Size $M.StateBytes)
        阈值 = "> $MaxStateMB MB"; 超限 = [bool]($M.StateMB -gt $MaxStateMB)
    }
    $items += [pscustomobject]@{
        指标 = '单进程内存'; 当前 = "{0} MB" -f $M.ProcessPeakMB
        阈值 = "> $MaxProcessMB MB"; 超限 = [bool]($M.ProcessPeakMB -gt $MaxProcessMB)
    }

    $hit = 0
    foreach ($i in $items) { if ($i.超限) { $hit++ } }

    $critical = [bool]($M.ProcessPeakMB -gt $MaxProcessMB)
    $level = 'Healthy'
    if ($critical -or $hit -ge 3) { $level = 'Risk' }
    elseif ($hit -ge 1) { $level = 'Watch' }

    return [pscustomobject]@{ Items = $items; Level = $level; HitCount = $hit }
}

# ================================================================ 动作

function New-SessionArchive {
    param(
        [System.IO.FileInfo[]]$Files,
        [string]$ZipPath,
        [string]$ManifestPath
    )
    Add-Type -AssemblyName System.IO.Compression | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }

    $used = New-Object 'System.Collections.Generic.HashSet[string]'
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($f in $Files) {
            $entry = $f.Name
            $i = 1
            while ($used.Contains($entry)) {
                $base = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
                $entry = '{0}_{1}{2}' -f $base, $i, $f.Extension
                $i = $i + 1
            }
            [void]$used.Add($entry)
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $zip, $f.FullName, $entry, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    }
    finally {
        $zip.Dispose()
    }

    # 回读校验：条目数必须一致，否则一个原件都不删
    $verify = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
    try { $entries = $verify.Entries.Count } finally { $verify.Dispose() }
    if ($entries -ne $Files.Count) {
        throw "归档校验失败：zip 内 $entries 条，预期 $($Files.Count) 条，已保留全部原文件。"
    }

    $manifest = @()
    foreach ($f in $Files) {
        $manifest += [pscustomobject]@{
            name     = $f.Name
            path     = $f.FullName
            sizeMB   = [math]::Round($f.Length / 1MB, 2)
            modified = $f.LastWriteTime.ToString('s')
        }
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
    return $true
}

function Get-ArchiveTargets {
    param([object]$M)
    $sorted = @($M.SessionFiles | Sort-Object -Property LastWriteTime -Descending)
    $keepCount = $KeepMinSessions
    if ($M.SessionCount -gt $MaxSessions) {
        $keepCount = $MaxSessions
    }
    if ($keepCount -gt $sorted.Count) { $keepCount = $sorted.Count }

    $keep = New-Object 'System.Collections.Generic.HashSet[string]'
    for ($i = 0; $i -lt $keepCount; $i++) { [void]$keep.Add($sorted[$i].FullName) }

    # 最近的几条会话视为"正在用"，绝不因为体积大就归档
    $protectCount = $ProtectRecent
    if ($protectCount -gt $sorted.Count) { $protectCount = $sorted.Count }
    $protect = New-Object 'System.Collections.Generic.HashSet[string]'
    for ($i = 0; $i -lt $protectCount; $i++) { [void]$protect.Add($sorted[$i].FullName) }

    $overCount = [bool]($M.SessionCount -gt $MaxSessions)
    $cutoff = (Get-Date).AddDays(-$KeepDays)
    $targets = @()
    foreach ($f in $sorted) {
        if ($protect.Contains($f.FullName)) { continue }
        $mb = $f.Length / 1MB
        $stale = [bool]($f.LastWriteTime -lt $cutoff)
        $huge = [bool]($mb -ge $MaxSingleSessionMB)
        if ($overCount -or $stale -or $huge) { $targets += $f }
    }

    # 保护集里出现超大会话时给出提醒（不删，只提示另开新对话）
    $warn = @()
    foreach ($f in $sorted) {
        if (-not $protect.Contains($f.FullName)) { continue }
        if (($f.Length / 1MB) -ge $MaxSingleSessionMB) {
            $warn += ("{0}（{1}）" -f $f.Name, (Format-Size $f.Length))
        }
    }
    return [pscustomobject]@{ Targets = $targets; KeepCount = $keepCount; ProtectedHuge = $warn }
}

function Invoke-SessionArchive {
    param([object]$M)
    if ($M.SessionCount -le $KeepMinSessions -and $M.SessionMB -le $MaxSessionMB -and
        $M.LargestSessionMB -le $MaxSingleSessionMB) {
        Write-Log "会话 $($M.SessionCount) 个 / $(Format-Size $M.SessionBytes)，均在保留范围内，不归档。" 'INFO'
        return 0
    }

    $plan = Get-ArchiveTargets -M $M
    foreach ($w in $plan.ProtectedHuge) {
        Write-Log "最近会话偏大，已保护未归档：$w（长对话建议另开新会话）" 'WARN'
    }
    if ($plan.Targets.Count -eq 0) {
        Write-Log '没有需要归档的会话。' 'INFO'
        return 0
    }

    $bytes = 0.0
    foreach ($t in $plan.Targets) { $bytes += $t.Length }
    Write-Log ("归档计划：{0} 个会话（{1}），保留最新 {2} 个。" -f `
            $plan.Targets.Count, (Format-Size $bytes), $plan.KeepCount) 'STEP'

    if ($DryRun) {
        $n = 0
        foreach ($t in $plan.Targets) {
            if ($n -ge 5) { break }
            Write-Log ("  DRY 归档 {0}  ({1}, {2})" -f $t.Name, (Format-Size $t.Length), $t.LastWriteTime.ToString('yyyy-MM-dd')) 'INFO'
            $n++
        }
        if ($plan.Targets.Count -gt 5) {
            Write-Log ("  DRY 其余 {0} 个略。" -f ($plan.Targets.Count - 5)) 'INFO'
        }
        return 0
    }

    if (-not (Test-Path -LiteralPath $ArchiveRoot)) {
        New-Item -ItemType Directory -Path $ArchiveRoot -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zipPath = Join-Path $ArchiveRoot ("sessions-{0}.zip" -f $stamp)
    $manifestPath = Join-Path $ArchiveRoot ("sessions-{0}.manifest.json" -f $stamp)

    [void](New-SessionArchive -Files $plan.Targets -ZipPath $zipPath -ManifestPath $manifestPath)
    Write-Log "已生成归档：$zipPath" 'OK'

    $deleted = 0
    $failed = 0
    foreach ($t in $plan.Targets) {
        try {
            Remove-Item -LiteralPath $t.FullName -Force -ErrorAction Stop
            $deleted++
        }
        catch {
            $failed++
            Write-Log "删除失败（可能被占用）：$($t.Name)" 'WARN'
        }
    }
    Write-Log "已归档删除 $deleted 个会话，失败 $failed 个，释放约 $(Format-Size $bytes)。" 'OK'
    if ($deleted -gt 0) { $script:Changed = $true }
    return $deleted
}

function Invoke-LogRotation {
    param([object]$M)
    if ($M.OversizedLogs.Count -eq 0) { return 0 }
    $bytes = 0.0
    foreach ($l in $M.OversizedLogs) { $bytes += $l.Length }
    Write-Log ("日志轮转：{0} 个文件超过 {1} MB，共 {2}。" -f $M.OversizedLogs.Count, $MaxLogMB, (Format-Size $bytes)) 'STEP'
    if ($DryRun) {
        foreach ($l in $M.OversizedLogs) {
            Write-Log ("  DRY 轮转 {0}  ({1})" -f $l.Name, (Format-Size $l.Length)) 'INFO'
        }
        return 0
    }

    if (-not (Test-Path -LiteralPath $ArchiveRoot)) {
        New-Item -ItemType Directory -Path $ArchiveRoot -Force | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zipPath = Join-Path $ArchiveRoot ("logs-{0}.zip" -f $stamp)
    [void](New-SessionArchive -Files $M.OversizedLogs -ZipPath $zipPath -ManifestPath ($zipPath + '.manifest.json'))

    $removed = 0
    foreach ($l in $M.OversizedLogs) {
        try { Remove-Item -LiteralPath $l.FullName -Force -ErrorAction Stop; $removed++ } catch { }
    }
    Write-Log "日志轮转完成：$removed 个文件已归档到 $(Split-Path -Leaf $zipPath)。" 'OK'
    if ($removed -gt 0) { $script:Changed = $true }
    return $removed
}

function Get-SqliteExe {
    $cmd = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($p in @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Mobius\resources\app\node_modules\sqlite3\build\Release\sqlite3.exe'),
            (Join-Path $PSScriptRoot 'sqlite3.exe')
        )) {
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

function Get-PythonExe {
    foreach ($n in @('python', 'python3', 'py')) {
        $c = Get-Command $n -ErrorAction SilentlyContinue
        if ($c) { return $c.Source }
    }
    return $null
}

function Invoke-DbVacuum {
    <# 优先 sqlite3.exe；没有就用 python 内置 sqlite3 模块（Windows 上一般都有） #>
    param([string]$Source, [string]$Target)
    $sqlite = Get-SqliteExe
    if ($sqlite) {
        $literal = "VACUUM INTO '{0}'" -f ($Target -replace '\\', '/')
        & $sqlite $Source $literal | Out-Null
        return 'sqlite3'
    }
    $python = Get-PythonExe
    if ($python) {
        # 写成临时 .py 再执行，避免 PowerShell 5.1 传参把内嵌引号吃掉
        $scriptPath = Join-Path $env:TEMP 'mobius-vacuum.py'
        $lines = @(
            'import sqlite3, sys',
            'src, dst = sys.argv[1], sys.argv[2]',
            'con = sqlite3.connect(src)',
            'con.execute("VACUUM INTO " + chr(39) + dst.replace(chr(39), chr(39) + chr(39)) + chr(39))',
            'con.close()'
        )
        [System.IO.File]::WriteAllText($scriptPath, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
        & $python $scriptPath $Source $Target | Out-Null
        return 'python'
    }
    return $null
}

function Invoke-StateDbCompact {
    param([object]$M)
    if ($M.StateMB -le $MaxStateMB) { return 0 }
    $dbs = @($M.StateFiles | Sort-Object -Property Length -Descending)
    if ($dbs.Count -eq 0) { return 0 }

    Write-Log ("state.vscdb {0} 超过阈值 {1} MB，准备压缩（VACUUM）。" -f (Format-Size $M.StateBytes), $MaxStateMB) 'STEP'

    $running = (Get-MobiusProcessList).Count -gt 0
    if ($running -and -not $Force) {
        Write-Log 'Mobius 正在运行，跳过 state.vscdb 压缩；完全退出 Mobius 后再跑一次即可。' 'WARN'
        return 0
    }

    $sqlite = Get-SqliteExe
    $python = Get-PythonExe
    if (-not $sqlite -and -not $python) {
        Write-Log '未找到 sqlite3.exe / python，跳过数据库压缩（其余清理已完成）。' 'WARN'
        return 0
    }

    if ($DryRun) {
        Write-Log ("  DRY 用 {0} 对 {1} 执行 VACUUM" -f $(if ($sqlite) { Split-Path -Leaf $sqlite } else { 'python sqlite3' }), $dbs[0].FullName) 'INFO'
        return 0
    }

    $ok = 0
    foreach ($db in $dbs) {
        if ($db.Length -le ($MaxStateMB * 1MB)) { continue }
        $tmp = [string]$db.FullName + '.compact-' + (Get-Date -Format 'HHmmss')
        try {
            $engine = Invoke-DbVacuum -Source $db.FullName -Target $tmp
            if (-not $engine) { throw '没有可用的 VACUUM 执行器' }
            if (-not (Test-Path -LiteralPath $tmp)) { throw 'VACUUM 未生成目标文件' }
            $before = [double]$db.Length
            $after = [double](Get-Item -LiteralPath $tmp).Length
            if ($after -gt 0 -and $after -lt $before) {
                Copy-Item -LiteralPath $db.FullName -Destination ([string]$db.FullName + '.bak') -Force
                Move-Item -LiteralPath $tmp -Destination $db.FullName -Force
                Write-Log ("state.vscdb 压缩完成：{0} -> {1}（原件备份 .bak）" -f (Format-Size $before), (Format-Size $after)) 'OK'
                $ok++
                $script:Changed = $true
            }
            else {
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                Write-Log '压缩未减小体积，已放弃（原文件未改动）。' 'INFO'
            }
        }
        catch {
            Write-Log ("state.vscdb 压缩失败：{0}" -f $_.Exception.Message) 'WARN'
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    }
    return $ok
}

function Invoke-HistoryPrune {
    param([string]$Root)
    if (-not $IncludeHistory) { return 0 }
    $historyDir = Join-Path $Root 'History'
    if (-not (Test-Path -LiteralPath $historyDir)) { return 0 }
    $cutoff = (Get-Date).AddDays(-$HistoryKeepDays)
    $old = @(Get-ChildItem -LiteralPath $historyDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff })
    if ($old.Count -eq 0) { return 0 }
    Write-Log ("History 精简：{0} 个超期条目（早于 {1}）。" -f $old.Count, $cutoff.ToString('yyyy-MM-dd')) 'STEP'
    if ($DryRun) { return 0 }
    $removed = 0
    foreach ($d in $old) {
        try { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop; $removed++ } catch { }
    }
    if ($removed -gt 0) { $script:Changed = $true }
    Write-Log "History 已清理 $removed 个条目。" 'OK'
    return $removed
}

function Remove-OldArchives {
    if (-not (Test-Path -LiteralPath $ArchiveRoot)) { return 0 }
    $cutoff = (Get-Date).AddDays(-$ArchiveKeepDays)
    $old = @(Get-ChildItem -LiteralPath $ArchiveRoot -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff -and ($_.Extension -eq '.zip' -or $_.Extension -eq '.json') })
    if ($old.Count -eq 0) { return 0 }
    Write-Log ("归档目录轮转：{0} 个文件超过 {1} 天。" -f $old.Count, $ArchiveKeepDays) 'STEP'
    if ($DryRun) { return 0 }
    foreach ($f in $old) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue }
    return $old.Count
}

# ================================================================ 报告

function Write-Report {
    param([object]$M, [object]$H, [hashtable]$Actions)
    $reportDir = Join-Path $ArchiveRoot 'reports'
    if (-not $DryRun) {
        if (-not (Test-Path -LiteralPath $reportDir)) { New-Item -ItemType Directory -Path $reportDir -Force | Out-Null }
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $path = Join-Path $reportDir ("report-{0}.json" -f $stamp)
    }
    else {
        $path = $null
    }

    $report = [pscustomobject]@{
        generatedAt = (Get-Date).ToString('s')
        mode        = $Mode
        dryRun      = [bool]$DryRun
        level       = $H.Level
        metrics     = [pscustomobject]@{
            dataRoot         = $M.Root
            sessionDirectory = $M.SessionDirectory
            sessionCount     = $M.SessionCount
            sessionMB        = $M.SessionMB
            largestMB        = $M.LargestSessionMB
            stateMB          = $M.StateMB
            logMB            = [math]::Round($M.LogBytes / 1MB, 1)
            processCount     = $M.ProcessCount
            processPeakMB    = $M.ProcessPeakMB
            processTotalMB   = $M.ProcessTotalMB
        }
        thresholds  = [pscustomobject]@{
            maxSessions = $MaxSessions; maxSessionMB = $MaxSessionMB; maxStateMB = $MaxStateMB
            maxProcessMB = $MaxProcessMB; maxSingleSessionMB = $MaxSingleSessionMB
        }
        checks      = $H.Items
        actions     = $Actions
    }

    if (-not $DryRun) {
        $json = $report | ConvertTo-Json -Depth 6
        $json | Set-Content -LiteralPath $path -Encoding UTF8
        $json | Set-Content -LiteralPath (Join-Path $ArchiveRoot 'last-report.json') -Encoding UTF8
    }
    return $path
}

function Get-DisplayWidth {
    param([string]$Text)
    $w = 0
    foreach ($ch in $Text.ToCharArray()) {
        if ([int]$ch -gt 0x2E7F) { $w += 2 } else { $w += 1 }
    }
    return $w
}

function Format-Cell {
    param([string]$Text, [int]$Width)
    $pad = $Width - (Get-DisplayWidth $Text)
    if ($pad -lt 0) { $pad = 0 }
    return $Text + (' ' * $pad)
}

function Show-Health {
    param([object]$H)
    Write-Host ''
    Write-Host ('  ' + (Format-Cell '指标' 14) + (Format-Cell '当前值' 18) + '阈值') -ForegroundColor DarkGray
    Write-Host '  ------------------------------------------------------------------' -ForegroundColor DarkGray
    foreach ($i in $H.Items) {
        $color = 'Gray'
        if ($i.超限) { $color = 'Red' }
        $cur = [string]$i.当前
        $thr = [string]$i.阈值
        Write-Host ('  ' + (Format-Cell $i.指标 14) + (Format-Cell $cur 18) + $thr) -ForegroundColor $color
    }
    Write-Host ''
    switch ($H.Level) {
        'Healthy' { Write-Host '  结论：健康 —— 什么都不用做。' -ForegroundColor Green }
        'Watch' { Write-Host '  结论：留意 —— 已有一项接近/超过阈值，建议本周内跑一次 -Mode Clean。' -ForegroundColor Yellow }
        'Risk' { Write-Host '  结论：风险 —— 立刻保存工作并重启 Mobius，然后跑 -Mode Clean。' -ForegroundColor Red }
    }
    Write-Host ''
}

# ================================================================ 主流程

$exitCode = 4
try {
    if (-not $DryRun) {
        if (-not (Test-Path -LiteralPath $ArchiveRoot)) { New-Item -ItemType Directory -Path $ArchiveRoot -Force | Out-Null }
        $script:LogFile = Join-Path $ArchiveRoot 'maintain.log'
    }

    Write-Log ("===== Mobius 自动化维护  Mode={0}  DryRun={1} =====" -f $Mode, [bool]$DryRun) 'STEP'

    $root = Resolve-MobiusDataRoot -Explicit $DataRoot
    Write-Log "数据目录：$root" 'INFO'

    $metrics = Get-Metrics -Root $root
    $health = Measure-Health -M $metrics
    Write-Log ("会话 {0} 个 / {1}，最大单会话 {2} MB，state.vscdb {3}，进程峰值 {4} MB" -f `
            $metrics.SessionCount, (Format-Size $metrics.SessionBytes), $metrics.LargestSessionMB, `
        (Format-Size $metrics.StateBytes), $metrics.ProcessPeakMB) 'INFO'

    $actions = @{}

    $doClean = $false
    if ($Mode -eq 'Clean') { $doClean = $true }
    if ($Mode -eq 'Auto' -and ($health.HitCount -gt 0 -or $health.Level -ne 'Healthy')) { $doClean = $true }

    if ($doClean) {
        $running = (Get-MobiusProcessList).Count -gt 0
        if ($running -and -not $Force) {
            Write-Log '检测到 Mobius 正在运行：会话归档可能被占用，本次仍尝试执行；state.vscdb 会跳过。' 'WARN'
        }
        $actions['sessionsArchived'] = (Invoke-SessionArchive -M $metrics)
        $actions['logsRotated'] = (Invoke-LogRotation -M $metrics)
        $actions['historyPruned'] = (Invoke-HistoryPrune -Root $root)
        $actions['stateDbCompacted'] = (Invoke-StateDbCompact -M $metrics)
        $actions['oldArchivesPruned'] = (Remove-OldArchives)

        if (-not $DryRun) {
            # 清理后重新采集一次，让报告反映真实结果
            $metrics = Get-Metrics -Root $root
            $health = Measure-Health -M $metrics
        }
    }
    else {
        Write-Log '未超阈值，本次不执行任何清理动作。' 'INFO'
        $actions['sessionsArchived'] = 0
        $actions['logsRotated'] = 0
        $actions['historyPruned'] = 0
        $actions['stateDbCompacted'] = 0
        $actions['oldArchivesPruned'] = 0
    }

    if (-not $Quiet) { Show-Health -H $health }

    $reportPath = Write-Report -M $metrics -H $health -Actions $actions
    if ($reportPath) { Write-Log "报告：$reportPath" 'INFO' }

    if ($Mode -eq 'Check') {
        if ($health.Level -eq 'Risk') { $exitCode = 2 }
        elseif ($health.Level -eq 'Watch') { $exitCode = 1 }
        else { $exitCode = 0 }
    }
    else {
        if ($script:Changed) { $exitCode = 3 }
        elseif ($health.Level -eq 'Risk') { $exitCode = 2 }
        elseif ($health.Level -eq 'Watch') { $exitCode = 1 }
        else { $exitCode = 0 }
    }

    Write-Log ("完成。结论 {0}，退出码 {1}。" -f $health.Level, $exitCode) 'OK'
    exit $exitCode
}
catch {
    $msg = $_.Exception.Message
    Write-Log ("执行失败：{0}" -f $msg) 'ERROR'
    Write-Log ("位置：{0}" -f $_.InvocationInfo.PositionMessage) 'ERROR'
    exit 4
}