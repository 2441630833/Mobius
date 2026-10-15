# Behavioral tests for install-win.ps1. No downloads, installs, app launches,
# desktop notifications, module dependencies, or changes outside a temp sandbox.
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$installerPath = Join-Path $PSScriptRoot 'install-win.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('mobius-installer-tests-' + [guid]::NewGuid())
$null = New-Item -ItemType Directory -Path $testRoot
$hostExecutable = (Get-Process -Id $PID).Path

$harness = @'
param([string]$Scenario, [string]$InstallerPath, [string]$Sandbox)
$ErrorActionPreference = 'Stop'
$env:LOCALAPPDATA = Join-Path $Sandbox 'Local'
$env:ProgramFiles = Join-Path $Sandbox 'Programs'
$env:SystemDrive = $null
$env:TEMP = Join-Path $Sandbox 'Temp'
$env:MOBIUS_FORCE = $null
$env:MOBIUS_FORCE_UPDATE = $null
$env:MOBIUS_CHECK = $null
$env:MOBIUS_AUTO_CLOSE = $null
$env:ELECTRON_NO_ATTACH_CONSOLE = 'test-before'
$script:fixtureTag = 'v9.8.7'
if ($Scenario -eq 'EscapedToast') { $script:fixtureTag = 'v9<&' }
$script:targetDir = Join-Path $env:LOCALAPPDATA 'Programs\Mobius'
if ($Scenario -eq 'CustomPath') { $script:targetDir = Join-Path $Sandbox 'Custom Install & Tools' }
$null = New-Item -ItemType Directory -Path $env:ProgramFiles, $env:TEMP, $script:targetDir -Force
$script:eventsPath = Join-Path $Sandbox 'events.jsonl'
function Write-TestEvent {
    param([string]$Kind, $Data)
    $line = @{ Kind = $Kind; Data = $Data } | ConvertTo-Json -Compress -Depth 8
    [IO.File]::AppendAllText($script:eventsPath, $line + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}
$existing = $Scenario -in @('UpdateDefault', 'CurrentDefault', 'ForceCurrent', 'CustomPath', 'FailInstaller')
if ($existing) {
    Set-Content -LiteralPath (Join-Path $script:targetDir 'Mobius.exe') -Value 'fixture'
    $tag = if ($Scenario -in @('CurrentDefault', 'ForceCurrent')) { $script:fixtureTag } else { 'v1.0.0' }
    Set-Content -LiteralPath (Join-Path $script:targetDir '.mobius-installed-tag') -Value $tag
}
$null = New-Item -ItemType Directory -Path (Join-Path $script:targetDir 'resources\app') -Force
Set-Content -LiteralPath (Join-Path $script:targetDir 'resources\app\product.json') -Value '{"win32AppUserModelId":"Mobius.Test","version":"1.0.0"}'
if ($Scenario -eq 'ForceCurrent') { $env:MOBIUS_FORCE = '1' }
if ($Scenario -eq 'EnvKeepOpen') { $env:MOBIUS_AUTO_CLOSE = '0' }
if ($Scenario -eq 'CheckOnly') { $env:MOBIUS_CHECK = '1' }

function Get-Command {
    param($Name, $ErrorAction)
    if ($Scenario -eq 'CustomPath') {
        return [pscustomobject]@{ Source = (Join-Path $script:targetDir 'bin\mobius.cmd') }
    }
}
function Get-Process { param($Name, $ErrorAction) }
function Start-Sleep { param($Seconds, $Milliseconds) }
function Invoke-RestMethod {
    param($Uri, $Headers, [switch]$UseBasicParsing)
    return [pscustomobject]@{
        tag_name = $script:fixtureTag; name = $script:fixtureTag; published_at = '2099-01-01T00:00:00Z'
        assets = @([pscustomobject]@{ name = 'MobiusSetup.exe'; browser_download_url = 'https://example.invalid/MobiusSetup.exe' })
    }
}
function Invoke-WebRequest {
    param($Uri, $OutFile, [switch]$UseBasicParsing)
    Write-TestEvent 'Download' @{ Path = $OutFile }
    Set-Content -LiteralPath $OutFile -Value 'fake installer'
    if ($Scenario -eq 'DownloadFailure') { throw 'simulated download failure' }
}
function Start-Process {
    param($FilePath, $ArgumentList, $WorkingDirectory, $WindowStyle, [switch]$PassThru, [switch]$Wait)
    $exitCode = 0
    $isToast = $FilePath -like '*\powershell.exe'
    if ($isToast) {
        $encoded = ($ArgumentList -split ' ')[-1]
        $command = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String($encoded))
        $tokens = $null; $errors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseInput($command, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw 'invalid notification helper syntax' }
        $match = [regex]::Match($command, "FromBase64String\('([^']+)'\)")
        [xml]$xml = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($match.Groups[1].Value))
        Write-TestEvent 'Toast' @{
            Title = [string]$xml.toast.visual.binding.text[0]
            Message = [string]$xml.toast.visual.binding.text[1]
            Hidden = ($WindowStyle -eq 'Hidden')
            RegisteredId = $command.Contains("CreateToastNotifier('Mobius.Test')")
        }
        if ($Scenario -eq 'ToastFailure') { $exitCode = 1 }
    } elseif ($FilePath -like '*MobiusSetup-*.exe') {
        Write-TestEvent 'Install' @{ Arguments = $ArgumentList; WaitTree = [bool]$Wait }
        if ($Scenario -eq 'FailInstaller') { $exitCode = 5 }
        elseif ($Scenario -ne 'MissingExe') {
            Set-Content -LiteralPath (Join-Path $script:targetDir 'Mobius.exe') -Value 'new fixture'
        }
    } elseif ($FilePath -eq (Join-Path $script:targetDir 'Mobius.exe')) {
        Write-TestEvent 'Launch' @{ NoAttach = $env:ELECTRON_NO_ATTACH_CONSOLE; WorkingDirectory = $WorkingDirectory }
        if ($Scenario -eq 'LaunchFailure') { throw 'simulated launch failure' }
        return
    } else { throw "Unexpected process: $FilePath" }
    $process = [pscustomobject]@{ ExitCode = $exitCode; Toast = $isToast; Timeout = ($Scenario -eq 'ToastTimeout'); HandleRead = $false }
    $process | Add-Member ScriptProperty Handle { $this.HandleRead = $true; return [IntPtr]::Zero }
    $process | Add-Member ScriptMethod WaitForExit {
        param($TimeoutMilliseconds)
        if (-not $this.HandleRead) { throw 'Process handle must be cached for Windows PowerShell 5.1 exit codes' }
        if ($this.Toast) { return (-not $this.Timeout) }
    }
    $process | Add-Member ScriptMethod Dispose {}
    $process | Add-Member ScriptMethod Kill { Write-TestEvent 'KillHelper' @{} }
    return $process
}
try {
    $source = Get-Content -LiteralPath $InstallerPath -Raw -Encoding UTF8
    if ($Scenario -eq 'KeepOpen') { & ([scriptblock]::Create($source)) -KeepOpen }
    else { Invoke-Expression $source }
} catch {
    Write-TestEvent 'Error' @{ Message = $_.Exception.Message }
}
Write-TestEvent 'CallerContinued' @{ ExitCode = $global:LASTEXITCODE; NoAttach = $env:ELECTRON_NO_ATTACH_CONSOLE }
'@

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

try {
    $harnessPath = Join-Path $testRoot 'harness.ps1'
    # BOM allows Windows PowerShell 5.1 to read any non-ASCII fixture text.
    [IO.File]::WriteAllText($harnessPath, $harness, [Text.UTF8Encoding]::new($true))
    $cases = @('FreshDefault', 'UpdateDefault', 'CurrentDefault', 'ForceCurrent',
        'CheckOnly', 'KeepOpen', 'EnvKeepOpen', 'FailInstaller', 'MissingExe',
        'DownloadFailure', 'ToastFailure', 'ToastTimeout', 'LaunchFailure', 'CustomPath', 'EscapedToast')
    foreach ($case in $cases) {
        $sandbox = Join-Path $testRoot $case
        $null = New-Item -ItemType Directory -Path $sandbox
        $stdout = Join-Path $sandbox 'stdout.log'
        $stderr = Join-Path $sandbox 'stderr.log'
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $harnessPath +
            '" -Scenario ' + $case + ' -InstallerPath "' + $installerPath + '" -Sandbox "' + $sandbox + '"'
        $child = Start-Process -FilePath $hostExecutable -ArgumentList $arguments -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        try {
            $null = $child.Handle
            Assert-Test ($child.WaitForExit(30000)) "$case timed out"
            Assert-Test ($child.ExitCode -eq 0) "$case child exit $($child.ExitCode): $(Get-Content -LiteralPath $stderr -Raw)"
        } finally {
            if (-not $child.HasExited) { $child.Kill() }
            $child.Dispose()
        }
        $eventsFile = Join-Path $sandbox 'events.jsonl'
        Assert-Test (Test-Path -LiteralPath $eventsFile) "$case produced no events"
        $events = @(Get-Content -LiteralPath $eventsFile -Encoding UTF8 | ForEach-Object { $_ | ConvertFrom-Json })
        $errors = @($events | Where-Object Kind -eq 'Error')
        $caller = @($events | Where-Object Kind -eq 'CallerContinued')
        $installs = @($events | Where-Object Kind -eq 'Install')
        $downloads = @($events | Where-Object Kind -eq 'Download')
        $toasts = @($events | Where-Object Kind -eq 'Toast')
        $launches = @($events | Where-Object Kind -eq 'Launch')
        $expectedFailure = $case -in @('FailInstaller', 'MissingExe', 'DownloadFailure')
        Assert-Test ($errors.Count -eq [int]$expectedFailure) "$case unexpected errors: $($errors | ConvertTo-Json -Compress)"
        $keepOpen = $expectedFailure -or $case -in @('CheckOnly', 'KeepOpen', 'EnvKeepOpen', 'ToastFailure', 'ToastTimeout')
        Assert-Test ($caller.Count -eq [int]$keepOpen) "$case incorrect shell exit behavior"
        if ($caller.Count) {
            Assert-Test ($caller[0].Data.NoAttach -eq 'test-before') "$case did not restore launch environment"
            if ($expectedFailure) { Assert-Test ($caller[0].Data.ExitCode -eq 1) "$case missing failure exit status" }
        }
        $noInstall = $case -in @('CheckOnly', 'CurrentDefault')
        Assert-Test ($downloads.Count -eq [int](-not $noInstall)) "$case unexpected download count"
        Assert-Test ($installs.Count -eq [int](-not ($noInstall -or $case -eq 'DownloadFailure'))) "$case unexpected install count"
        if ($installs.Count) {
            Assert-Test (-not $installs[0].Data.WaitTree) "$case waits for the entire process tree"
            Assert-Test ($installs[0].Data.Arguments.Contains('/MERGETASKS="!runcode"')) "$case installer can launch app early"
            Assert-Test ($installs[0].Data.Arguments.Contains('/NORESTART')) "$case installer can restart Windows"
        }
        $noSuccess = $expectedFailure -or $case -eq 'CheckOnly'
        Assert-Test ($toasts.Count -eq [int](-not $noSuccess)) "$case incorrect success notification"
        if ($toasts.Count) {
            Assert-Test ($toasts[0].Data.Hidden -and $toasts[0].Data.RegisteredId) "$case incorrect notification host or app ID"
            $expectedTag = if ($case -eq 'EscapedToast') { 'v9<&' } else { 'v9.8.7' }
            Assert-Test ($toasts[0].Data.Message.Contains($expectedTag)) "$case corrupted notification content"
            $expectedTitle = if ($case -eq 'CurrentDefault') { 'Mobius 已是最新版本' }
                elseif ($case -in @('UpdateDefault', 'ForceCurrent', 'CustomPath')) { 'Mobius 更新成功' }
                else { 'Mobius 安装成功' }
            Assert-Test ($toasts[0].Data.Title -eq $expectedTitle) "$case incorrect notification title"
        }
        Assert-Test ($launches.Count -eq [int](-not ($noSuccess -or $case -eq 'CurrentDefault'))) "$case incorrect app launch"
        if ($launches.Count) { Assert-Test ($launches[0].Data.NoAttach -eq '1') "$case app can attach to installer console" }
        if ($case -eq 'ToastTimeout') {
            Assert-Test (@($events | Where-Object Kind -eq 'KillHelper').Count -eq 1) 'Timed-out notification helper was not stopped'
        }
        $target = if ($case -eq 'CustomPath') { Join-Path $sandbox 'Custom Install & Tools' }
            else { Join-Path $sandbox 'Local\Programs\Mobius' }
        $marker = Join-Path $target '.mobius-installed-tag'
        if ($expectedFailure -and $case -ne 'FailInstaller') {
            Assert-Test (-not (Test-Path -LiteralPath $marker)) "$case wrote a false success marker"
        } elseif ($case -eq 'FailInstaller') {
            Assert-Test ((Get-Content -LiteralPath $marker -Raw).Trim() -eq 'v1.0.0') 'Failed update overwrote the old marker'
        } elseif ($case -ne 'CheckOnly') {
            Assert-Test ((Get-Content -LiteralPath $marker -Raw -Encoding UTF8).Trim() -eq $expectedTag) "$case incorrect installed marker"
        }
        Assert-Test (@(Get-ChildItem -LiteralPath (Join-Path $sandbox 'Temp') -Filter 'MobiusSetup-*.exe').Count -eq 0) "$case left a downloaded installer"
        Write-Host "PASS $case" -ForegroundColor Green
    }
    Write-Host "All $($cases.Count) installer scenarios passed on PowerShell $($PSVersionTable.PSVersion)." -ForegroundColor Green
} finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
    $tempParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedTestRoot.StartsWith($tempParent, [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFileName($resolvedTestRoot) -like 'mobius-installer-tests-*')) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
