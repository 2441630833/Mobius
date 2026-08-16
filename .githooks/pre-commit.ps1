param(
    [switch]$DryRun
)

# .githooks/pre-commit.ps1
# PowerShell implementation called via pre-commit shell shim.
# All Chinese phrases are built from [char]0xXXXX codes so the file is
# ASCII-only source - avoids cp936 mojibake when powershell.exe reads it
# through the Windows codepage path.

$ErrorActionPreference = 'Stop'
$staged = git diff --cached --name-only --diff-filter=ACM
$issues = @()

# Build Chinese agent-stop phrases from Unicode code points.
$zh1 = [char]0x8BF7 + [char]0x56DE + [char]0x590D + [char]0x7EE7 + [char]0x7EED
$zh2 = [char]0x8BF7 + [char]0x56DE + [char]0x590D + [char]0x4EFB + [char]0x610F + [char]0x6D88 + [char]0x606F
$zh3 = [char]0x8981 + [char]0x6211 + [char]0x7EE7 + [char]0x7EED + [char]0x5417
$zh4 = [char]0x8BF7 + [char]0x7EE7 + [char]0x7EED
$zh5 = [char]0x5DE5 + [char]0x5177 + [char]0x8C03 + [char]0x7528 + [char]0x5DF2 + [char]0x7528 + [char]0x5B8C
$zh6 = [char]0x672C + [char]0x8F6E + [char]0x5DE5 + [char]0x5177 + [char]0x8C03 + [char]0x7528
$zh7 = [char]0x4E0B + [char]0x4E00 + [char]0x8F6E + [char]0x7EE7 + [char]0x7EED

$zhStopPhrases = @($zh1, $zh2, $zh3, $zh4, $zh5, $zh6, $zh7)

$enStopPhrases = @(
    'reply continue', 'shall i proceed', 'please confirm',
    'may i edit', 'this turn is done'
)

$stopPhrases = $zhStopPhrases + $enStopPhrases

# --- 1. Empty commit guard (skip when --allow-empty) ---
if (-not $staged -or $staged.Count -eq 0) {
    $allowEmpty = $env:GIT_ALLOW_EMPTY -eq '1'
    if (-not $allowEmpty) {
        $issues += "No staged files. Use --allow-empty or stage something first."
    }
}

# --- 2. Agent-stop phrase scan (content-level, UTF-8 safe) ---
foreach ($f in $staged) {
    if (-not (Test-Path $f -PathType Leaf)) { continue }
    try {
        $content = [System.IO.File]::ReadAllText((Resolve-Path $f).Path, [System.Text.UTF8Encoding]::new($false))
    } catch { continue }
    foreach ($p in $stopPhrases) {
        if ($content.Contains($p)) {
            $issues += "[$f] contains agent-stop phrase: '$p' (finish the work before committing)"
        }
    }
    $bytes = [System.IO.File]::ReadAllBytes((Resolve-Path $f).Path)
    for ($i = 0; $i -lt $bytes.Length - 2; $i++) {
        if ($bytes[$i] -eq 0xEF -and $bytes[$i+1] -eq 0xBF -and $bytes[$i+2] -eq 0xBD) {
            $issues += "[$f] contains mojibake replacement char (U+FFFD) near byte offset $i - re-save as UTF-8"
            break
        }
    }
}

# --- 3. PowerShell syntax check (.ps1) ---
foreach ($f in $staged) {
    if ($f -notlike '*.ps1') { continue }
    if (-not (Test-Path $f -PathType Leaf)) { continue }
    try {
        $text = [System.IO.File]::ReadAllText((Resolve-Path $f).Path, [System.Text.UTF8Encoding]::new($false))
        $tokens = $null
        $errs = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tokens, [ref]$errs)
        if ($errs -and $errs.Count -gt 0) {
            foreach ($e in $errs) {
                $issues += "[$f] PowerShell parse error at line $($e.Extent.StartLineNumber): $($e.Message)"
            }
        }
    } catch {
        $issues += "[$f] PowerShell syntax check threw: $($_.Exception.Message)"
    }
}

# --- 4. Report ---
if ($issues.Count -gt 0) {
    Write-Host "pre-commit: BLOCKED ($($issues.Count) issue(s)):" -ForegroundColor Red
    foreach ($i in $issues) { Write-Host "  - $i" -ForegroundColor Red }
    if (-not $DryRun) { exit 1 }
} else {
    Write-Host "pre-commit: OK ($($staged.Count) file(s) staged, no issues)" -ForegroundColor Green
}
exit 0
