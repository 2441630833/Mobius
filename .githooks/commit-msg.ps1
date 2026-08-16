param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$MsgFile
)

# .githooks/commit-msg.ps1
# PowerShell implementation called via commit-msg shell shim.
# All Chinese phrases are built from [char]0xXXXX codes so the file is
# ASCII-only source - avoids cp936 mojibake when powershell.exe reads it
# through the Windows codepage path.

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $MsgFile -PathType Leaf)) {
    Write-Host "commit-msg: message file not found: $MsgFile" -ForegroundColor Red
    exit 1
}

$msg = [System.IO.File]::ReadAllText((Resolve-Path $MsgFile).Path, [System.Text.UTF8Encoding]::new($false))
$lower = $msg.ToLowerInvariant()

# Build Chinese forbidden phrases from Unicode code points (BMP only)
# so the source file stays ASCII and never hits cp936 decode issues.
$zh1 = [char]0x8BF7 + [char]0x56DE + [char]0x590D + [char]0x7EE7 + [char]0x7EED
$zh2 = [char]0x8BF7 + [char]0x56DE + [char]0x590D + [char]0x4EFB + [char]0x610F + [char]0x6D88 + [char]0x606F
$zh3 = [char]0x8981 + [char]0x6211 + [char]0x7EE7 + [char]0x7EED + [char]0x5417
$zh4 = [char]0x8BF7 + [char]0x7EE7 + [char]0x7EED
$zh5 = [char]0x5DE5 + [char]0x5177 + [char]0x8C03 + [char]0x7528 + [char]0x5DF2 + [char]0x7528 + [char]0x5B8C
$zh6 = [char]0x672C + [char]0x8F6E + [char]0x5DE5 + [char]0x5177 + [char]0x8C03 + [char]0x7528
$zh7 = [char]0x4E0B + [char]0x4E00 + [char]0x8F6E + [char]0x7EE7 + [char]0x7EED

$zhPhrases = @($zh1, $zh2, $zh3, $zh4, $zh5, $zh6, $zh7)

$enPhrases = @(
    'reply continue', 'please reply', 'reply any message',
    'shall i proceed', 'please confirm', 'may i edit',
    'ready to apply', 'tool turns left', 'out of tool'
)

$forbidden = $zhPhrases + $enPhrases

$issues = @()
foreach ($p in $forbidden) {
    if ($lower.Contains($p.ToLowerInvariant())) {
        $issues += "commit message contains agent-stop phrase: '$p'"
    }
}

$firstLine = ($msg -split "`n")[0].Trim()
if ([string]::IsNullOrWhiteSpace($firstLine)) {
    $issues += "commit subject is empty"
}

if ($issues.Count -gt 0) {
    Write-Host "commit-msg: BLOCKED:" -ForegroundColor Red
    foreach ($i in $issues) { Write-Host "  - $i" -ForegroundColor Red }
    Write-Host ""
    Write-Host "The commit message suggests work was left unfinished. Fix the message,"
    Write-Host "finish the task, then re-commit. Use git commit --no-verify to bypass"
    Write-Host "(only if you are certain)."
    exit 1
}

if ($msg.Contains([char]0xFFFD)) {
    Write-Host "commit-msg: WARNING - message contains mojibake replacement char (U+FFFD)." -ForegroundColor Yellow
    Write-Host "  Consider re-writing the message via create_file (UTF-8) instead of" -ForegroundColor Yellow
    Write-Host "  git commit -m on a cp936 console." -ForegroundColor Yellow
}

exit 0
