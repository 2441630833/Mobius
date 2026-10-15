# Restore PPT Master in an existing Windows Mobius installation.
[CmdletBinding()]
param(
    [string]$ClientDir = (Join-Path $env:LOCALAPPDATA 'Programs\Mobius')
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$appRoot = Join-Path $ClientDir 'resources\app'
$output = Join-Path $appRoot 'out'
$archive = Join-Path $Root 'vscode\resources\ppt-master\ppt-master-6.7.0.tar.gz'
$skillsParent = Join-Path $output 'vs\workbench\contrib\continue\mobius\skills'
$skillDir = Join-Path $skillsParent 'ppt-master'

if (-not (Test-Path -LiteralPath (Join-Path $appRoot 'product.json') -PathType Leaf)) {
    throw "Mobius application not found at $appRoot. Pass -ClientDir with its installation directory."
}
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    throw "Bundled PPT Master archive not found: $archive"
}

$bundles = @(
    (Join-Path $output 'vs\workbench\workbench.desktop.main.js'),
    (Join-Path $output 'vs\sessions\sessions.desktop.main.js')
)
# Validate all patch targets before writing any bundle.
$patches = @()
foreach ($bundle in $bundles) {
    if (-not (Test-Path -LiteralPath $bundle -PathType Leaf)) {
        throw "Mobius bundle not found: $bundle"
    }
    $body = [System.IO.File]::ReadAllText($bundle)
    $legacyMarker = '- Powered by the ppt-master engine (.agents/skills/ppt-master/).'
    if ($body.Contains($legacyMarker)) {
        $absoluteSkillDir = $skillDir.Replace('\', '/')
        # These strings live inside a JavaScript template literal.
        $escapedSkillDir = $absoluteSkillDir.Replace('`', '\`').Replace('${', '\${')
        $replacement = "- Powered by the bundled ppt-master engine ($escapedSkillDir/).`n" +
            "- SKILL_DIR is the absolute installation directory above. Read `"$escapedSkillDir/SKILL.md`" first and follow its mandatory load order and workflow. Resolve all skill resources against SKILL_DIR; keep presentation outputs in the user's workspace."
        $body = $body.Replace($legacyMarker, $replacement).Replace('.agents/skills/ppt-master/', "$escapedSkillDir/")
        $patches += @{ Path = $bundle; Body = $body }
    } elseif (-not $body.Contains('- Powered by the bundled ppt-master engine')) {
        throw "Unrecognized PPT runtime in $bundle; rebuild Mobius rather than patching an unknown bundle."
    }
}

New-Item -ItemType Directory -Path $skillsParent -Force | Out-Null
& tar -xzf $archive -C $skillsParent
if ($LASTEXITCODE -ne 0) { throw 'Extracting the bundled PPT Master skill failed.' }
if (-not (Test-Path -LiteralPath (Join-Path $skillDir 'SKILL.md') -PathType Leaf)) {
    throw 'Extracted PPT Master SKILL.md is missing.'
}

foreach ($patch in $patches) {
    $backup = "$($patch.Path).ppt-master.bak"
    if (-not (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $patch.Path -Destination $backup
    }
    [System.IO.File]::WriteAllText($patch.Path, $patch.Body, [System.Text.UTF8Encoding]::new($false))
}
$agentSource = Join-Path $Root 'vscode\src\vs\workbench\contrib\continue\mobius\agents\PPT.agent.md'
$agentDestination = Join-Path $output 'vs\workbench\contrib\continue\mobius\agents\PPT.agent.md'
New-Item -ItemType Directory -Path (Split-Path -Parent $agentDestination) -Force | Out-Null
Copy-Item -LiteralPath $agentSource -Destination $agentDestination -Force

Write-Host "PPT Master restored: $skillDir"
Write-Host "Patched $($patches.Count) legacy bundles. Reload the Mobius window to use the restored PPT mode."
