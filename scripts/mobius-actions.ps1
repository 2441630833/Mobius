#Requires -Version 5.1
<#
.SYNOPSIS
    Minimal GitHub Actions helper for the Mobius repo (no gh CLI required).

.DESCRIPTION
    Works with either GH_TOKEN / GITHUB_TOKEN environment variables or the
    credential already stored by Git Credential Manager for github.com.

    Actions:
      Auth      - verify token + repo permissions
      Status    - show the latest runs of a workflow
      Dispatch  - trigger workflow_dispatch on a branch
      Wait      - poll a run until it finishes, print artifact names
      Download  - download all artifacts of a finished run into a folder

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\mobius-actions.ps1 -Action Auth

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\mobius-actions.ps1 -Action Dispatch -Workflow build-windows.yml -ReleaseTag v1.0.23
#>
[CmdletBinding()]
param(
    [ValidateSet('Auth', 'Status', 'Dispatch', 'Wait', 'Download', 'Releases', 'DownloadRelease', 'RunInfo')]
    [string]$Action = 'Status',

    [string]$Repo = '2441630833/Mobius',
    [string]$Workflow = 'build-windows.yml',
    [string]$Ref = 'main',
    [string]$ReleaseTag = '',
    [string]$Arch = 'x64',
    [string]$InstallerTarget = 'user',
    [switch]$SystemTarget,
    [long]$RunId = 0,
    [int]$TimeoutMinutes = 110,
    [string]$OutDir = '',
    [string]$AssetPattern = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ApiBase = 'https://api.github.com'

function Get-GitHubToken {
    if ($env:GH_TOKEN) { return $env:GH_TOKEN }
    if ($env:GITHUB_TOKEN) { return $env:GITHUB_TOKEN }

    if (-not ('MobiusCred' -as [type])) {
        $sig = @'
using System;
using System.Runtime.InteropServices;
public class MobiusCred {
  [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern bool CredReadW(string target, int type, int flags, out IntPtr credential);
  [DllImport("advapi32.dll", SetLastError=true)]
  public static extern void CredFree(IntPtr cred);
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct CREDENTIAL {
    public int Flags; public int Type; public string TargetName; public string Comment;
    public long LastWritten; public int CredentialBlobSize; public IntPtr CredentialBlob;
    public int Persist; public int AttributeCount; public IntPtr Attributes;
    public string TargetAlias; public string UserName;
  }
}
'@
        Add-Type -TypeDefinition $sig
    }

    $targets = @(
        'git:https://github.com',
        'git:https://github.com/2441630833',
        'git:https://github.com/2441630833/Mobius'
    )
    foreach ($t in $targets) {
        $ptr = [IntPtr]::Zero
        if ([MobiusCred]::CredReadW($t, 1, 0, [ref]$ptr)) {
            try {
                $c = [Runtime.InteropServices.Marshal]::PtrToStructure($ptr, [type][MobiusCred+CREDENTIAL])
                $bytes = New-Object byte[] $c.CredentialBlobSize
                [Runtime.InteropServices.Marshal]::Copy($c.CredentialBlob, $bytes, 0, $c.CredentialBlobSize)
                $secret = [Text.Encoding]::Unicode.GetString($bytes)
                if ($secret) { return $secret.Trim() }
            }
            finally {
                [void][MobiusCred]::CredFree($ptr)
            }
        }
    }
    return $null
}

function Invoke-GhApi {
    param(
        [string]$Method = 'GET',
        [string]$Path,
        $Body = $null
    )
    $token = Get-GitHubToken
    if (-not $token) { throw 'No GitHub token available (set GH_TOKEN or sign in with Git Credential Manager).' }
    $headers = @{
        Authorization          = "Bearer $token"
        'User-Agent'           = 'mobius-actions-helper'
        Accept                 = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $uri = if ($Path -like 'http*') { $Path } else { "$script:ApiBase$Path" }
    $params = @{ Method = $Method; Uri = $uri; Headers = $headers; UseBasicParsing = $true }
    if ($null -ne $Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 6)
        $params.ContentType = 'application/json'
    }
    return Invoke-RestMethod @params
}

function Show-Auth {
    $user = Invoke-GhApi -Path '/user'
    Write-Host ("Authenticated as {0}" -f $user.login) -ForegroundColor Green
    $repoInfo = Invoke-GhApi -Path "/repos/$Repo"
    Write-Host ("Repo {0}: private={1} push={2} admin={3}" -f $repoInfo.full_name, $repoInfo.private, $repoInfo.permissions.push, $repoInfo.permissions.admin)
    $wf = Invoke-GhApi -Path "/repos/$Repo/actions/workflows"
    Write-Host ("Workflows visible: {0}" -f $wf.total_count)
    foreach ($w in $wf.workflows) { Write-Host ("  - {0} ({1})" -f $w.path, $w.state) }
}

function Show-Status {
    $runs = Invoke-GhApi -Path "/repos/$Repo/actions/workflows/$Workflow/runs?per_page=5"
    if ($runs.total_count -eq 0) { Write-Host 'No runs yet for this workflow.'; return }
    $runs.workflow_runs | Select-Object id, status, conclusion, event, head_branch, created_at, html_url | Format-Table -AutoSize
}

function Start-Dispatch {
    $body = @{ ref = $Ref; inputs = @{ arch = $Arch; target = $InstallerTarget } }
    if ($ReleaseTag) { $body.inputs.release_tag = $ReleaseTag }
    Invoke-GhApi -Method 'POST' -Path "/repos/$Repo/actions/workflows/$Workflow/dispatches" -Body $body | Out-Null
    Write-Host ("Dispatched {0} on ref '{1}' (arch={2}, target={3}, release_tag='{4}')" -f $Workflow, $Ref, $Arch, $InstallerTarget, $ReleaseTag) -ForegroundColor Green
    Start-Sleep -Seconds 6
    Show-Status
}

function Resolve-Run {
    param([long]$Id)
    if ($Id -gt 0) { return Invoke-GhApi -Path "/repos/$Repo/actions/runs/$Id" }
    $runs = Invoke-GhApi -Path "/repos/$Repo/actions/workflows/$Workflow/runs?per_page=1"
    if ($runs.total_count -eq 0) { throw 'No run found.' }
    return $runs.workflow_runs[0]
}

function Wait-Run {
    $run = Resolve-Run -Id $RunId
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    Write-Host ("Watching run {0} - {1}" -f $run.id, $run.html_url)
    while ($run.status -ne 'completed') {
        if ((Get-Date) -gt $deadline) { throw ("Timeout after {0} minutes; run still {1}." -f $TimeoutMinutes, $run.status) }
        Start-Sleep -Seconds 30
        $run = Invoke-GhApi -Path "/repos/$Repo/actions/runs/$($run.id)"
        Write-Host ("  [{0}] status={1} conclusion={2}" -f (Get-Date -Format 'HH:mm:ss'), $run.status, $run.conclusion)
    }
    Write-Host ("Run finished: {0}" -f $run.conclusion) -ForegroundColor ($(if ($run.conclusion -eq 'success') { 'Green' } else { 'Red' }))
    $arts = Invoke-GhApi -Path "/repos/$Repo/actions/runs/$($run.id)/artifacts"
    foreach ($a in $arts.artifacts) {
        Write-Host ("  artifact: {0} ({1:N1} MB) expired={2}" -f $a.name, ($a.size_in_bytes / 1MB), $a.expired)
    }
    if ($run.conclusion -ne 'success') {
        $jobs = Invoke-GhApi -Path "/repos/$Repo/actions/runs/$($run.id)/jobs"
        foreach ($j in $jobs.jobs) {
            foreach ($s in $j.steps) {
                if ($s.conclusion -eq 'failure') { Write-Host ("  FAILED step: {0} / {1}" -f $j.name, $s.name) -ForegroundColor Red }
            }
        }
    }
    return $run
}

function Save-Artifacts {
    param([long]$Id)
    $run = Resolve-Run -Id $Id
    if ($run.status -ne 'completed') { throw 'Run has not completed yet.' }
    if (-not $OutDir) { $OutDir = Join-Path (Get-Location) ("dist/actions-$($run.id)") }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $arts = Invoke-GhApi -Path "/repos/$Repo/actions/runs/$($run.id)/artifacts"
    if ($arts.total_count -eq 0) { Write-Host 'No artifacts.'; return }
    $token = Get-GitHubToken
    foreach ($a in $arts.artifacts) {
        $zip = Join-Path $OutDir ("{0}.zip" -f $a.name)
        $headers = @{ Authorization = "Bearer $token"; 'User-Agent' = 'mobius-actions-helper' }
        Invoke-WebRequest -Uri $a.archive_download_url -Headers $headers -OutFile $zip -UseBasicParsing
        $dest = Join-Path $OutDir $a.name
        Expand-Archive -LiteralPath $zip -DestinationPath $dest -Force
        Write-Host ("Downloaded {0} -> {1}" -f $a.name, $dest) -ForegroundColor Green
    }
    Get-ChildItem -Recurse -File $OutDir | Select-Object FullName, @{n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } } | Format-Table -AutoSize
}

if ($SystemTarget) { $InstallerTarget = 'system' }

function Show-Releases {    param([int]$Limit = 5)
    $rels = Invoke-GhApi -Path "/repos/$Repo/releases?per_page=$Limit"
    if (-not $rels -or $rels.Count -eq 0) { Write-Host 'No releases.'; return }
    foreach ($r in $rels) {
        Write-Host ("{0}  '{1}'  draft={2}  published={3}" -f $r.tag_name, $r.name, $r.draft, $r.published_at) -ForegroundColor Cyan
        foreach ($a in $r.assets) {
            Write-Host ("    {0}  {1:N1} MB  {2}" -f $a.name, ($a.size / 1MB), $a.browser_download_url)
        }
    }
}

function Save-ReleaseAssets {
    if (-not $ReleaseTag) { throw 'Specify -ReleaseTag (e.g. v1.0.23).' }
    $rel = Invoke-GhApi -Path "/repos/$Repo/releases/tags/$ReleaseTag"
    $pattern = if ($AssetPattern) { $AssetPattern } else { '*win32-x64*' }
    $assets = @($rel.assets | Where-Object { $_.name -like $pattern })
    if ($assets.Count -eq 0) { throw ("No asset matching '{0}' in release {1}." -f $pattern, $ReleaseTag) }
    $sumsAsset = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
    if (-not $OutDir) { $OutDir = Join-Path (Get-Location) ("dist/release-$ReleaseTag") }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $token = Get-GitHubToken
    $headers = @{ Authorization = "Bearer $token"; 'User-Agent' = 'mobius-actions-helper' }
    $sums = @{}
    if ($sumsAsset) {
        $sumsPath = Join-Path $OutDir 'SHA256SUMS.txt'
        Invoke-WebRequest -Uri $sumsAsset.url -Headers ($headers + @{ Accept = 'application/octet-stream' }) -OutFile $sumsPath -UseBasicParsing
        foreach ($line in Get-Content -LiteralPath $sumsPath) {
            if ($line -match '^([0-9a-fA-F]{64})\s+\*?(.+)$') { $sums[$Matches[2].Trim()] = $Matches[1].ToLower() }
        }
    }
    foreach ($a in $assets) {
        $dest = Join-Path $OutDir $a.name
        Write-Host ("Downloading {0} ({1:N1} MB) ..." -f $a.name, ($a.size / 1MB))
        Invoke-WebRequest -Uri $a.url -Headers ($headers + @{ Accept = 'application/octet-stream' }) -OutFile $dest -UseBasicParsing
        $hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $dest).Hash.ToLower()
        $expected = $sums[$a.name]
        if ($expected) {
            if ($expected -eq $hash) { Write-Host '  sha256 OK' -ForegroundColor Green }
            else { Write-Host ("  sha256 MISMATCH expected {0} got {1}" -f $expected, $hash) -ForegroundColor Red }
        }
        else { Write-Host ("  sha256 {0} (no manifest entry)" -f $hash) }
    }
    Get-ChildItem -LiteralPath $OutDir -File | Select-Object Name, @{ n = 'MB'; e = { [math]::Round($_.Length / 1MB, 2) } } | Format-Table -AutoSize
}

function Show-RunInfo {
    $run = Resolve-Run -Id $RunId
    Write-Host ("run {0}  {1}/{2}  event={3}  branch={4}" -f $run.id, $run.status, $run.conclusion, $run.event, $run.head_branch) -ForegroundColor Cyan
    Write-Host ("  started {0}  updated {1}  {2}" -f $run.run_started_at, $run.updated_at, $run.html_url)
    $jobs = Invoke-GhApi -Path "/repos/$Repo/actions/runs/$($run.id)/jobs"
    foreach ($j in $jobs.jobs) {
        Write-Host ("  job {0}: {1}/{2}  ({3})" -f $j.name, $j.status, $j.conclusion, $j.started_at)
        foreach ($s in $j.steps) {
            $mark = switch ($s.conclusion) {
                'success' { '[ok]  ' }
                'failure' { '[FAIL]' }
                'skipped' { '[--]  ' }
                default { if ($s.status -eq 'in_progress') { '[..]  ' } else { '[    ]' } }
            }
            Write-Host ("    {0} {1}" -f $mark, $s.name)
        }
    }
}

# Only execute an action when the script is invoked directly; dot-sourcing exposes
# the helper functions to other scripts (e.g. update-mobius-local.ps1).
if ($MyInvocation.InvocationName -ne '.') {
    switch ($Action) {
        'Auth' { Show-Auth }
        'Status' { Show-Status }
        'Dispatch' { Show-Auth; Start-Dispatch }
        'Wait' { [void](Wait-Run) }
        'Download' { Save-Artifacts -Id $RunId }
        'Releases' { Show-Releases }
        'DownloadRelease' { Save-ReleaseAssets }
        'RunInfo' { Show-RunInfo }
    }
}