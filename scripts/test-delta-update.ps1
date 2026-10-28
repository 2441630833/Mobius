# =============================================================================
# Behavioral & Integration Tests for Mobius Incremental Update (Delta)
# Tests generate-delta.ps1, apply-delta.ps1, manifest generation, and rollback
# =============================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$scriptDir = $PSScriptRoot
$generateScript = Join-Path $scriptDir 'generate-delta.ps1'
$applyScript = Join-Path $scriptDir 'apply-delta.ps1'

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mobius-delta-tests-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $testRoot

function Assert-Condition {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        throw "ASSERTION FAILED: $Message"
    }
}

try {
    Write-Host "Running Delta Update Integration Tests in sandbox: $testRoot" -ForegroundColor Cyan

    $v1Dir = Join-Path $testRoot 'install-v1'
    $v2Dir = Join-Path $testRoot 'build-v2'
    $distDir = Join-Path $testRoot 'dist'

    $null = New-Item -ItemType Directory -Path $v1Dir, $v2Dir, $distDir

    # Create dummy app v1
    # 1. Mobius.exe (will be unchanged)
    # 2. unins000.dat (ignored file)
    # 3. resources/app/package.json (will be modified)
    # 4. resources/app/out/main.js (will be modified)
    # 5. resources/app/out/deprecated.js (will be deleted in v2)
    # 6. resources/app/models/huge-weights.bin (10 MB, unchanged)
    Set-Content -LiteralPath (Join-Path $v1Dir 'Mobius.exe') -Value 'Mobius binary v1'
    Set-Content -LiteralPath (Join-Path $v1Dir 'unins000.dat') -Value 'Inno setup uninstaller data'
    Set-Content -LiteralPath (Join-Path $v1Dir '.mobius-installed-tag') -Value 'v1.0.0'

    $null = New-Item -ItemType Directory -Path (Join-Path $v1Dir 'resources\app\out'), (Join-Path $v1Dir 'resources\app\models')
    Set-Content -LiteralPath (Join-Path $v1Dir 'resources\app\package.json') -Value '{"name":"mobius","version":"1.0.0"}'
    Set-Content -LiteralPath (Join-Path $v1Dir 'resources\app\out\main.js') -Value 'console.log("Mobius v1 main");'
    Set-Content -LiteralPath (Join-Path $v1Dir 'resources\app\out\deprecated.js') -Value 'console.log("old feature");'
    Set-Content -LiteralPath (Join-Path $v1Dir 'resources\app\models\huge-weights.bin') -Value ('0' * 100000)

    # Create dummy build v2
    # 1. Mobius.exe (same)
    # 2. resources/app/package.json (modified: version 1.0.1)
    # 3. resources/app/out/main.js (modified)
    # 4. resources/app/out/new-feature.js (added!)
    # 5. resources/app/out/deprecated.js (omitted -> deleted!)
    # 6. resources/app/models/huge-weights.bin (same)
    Set-Content -LiteralPath (Join-Path $v2Dir 'Mobius.exe') -Value 'Mobius binary v1'
    $null = New-Item -ItemType Directory -Path (Join-Path $v2Dir 'resources\app\out'), (Join-Path $v2Dir 'resources\app\models')
    Set-Content -LiteralPath (Join-Path $v2Dir 'resources\app\package.json') -Value '{"name":"mobius","version":"1.0.1"}'
    Set-Content -LiteralPath (Join-Path $v2Dir 'resources\app\out\main.js') -Value 'console.log("Mobius v2 main with speedups");'
    Set-Content -LiteralPath (Join-Path $v2Dir 'resources\app\out\new-feature.js') -Value 'console.log("brand new feature in v2");'
    Set-Content -LiteralPath (Join-Path $v2Dir 'resources\app\models\huge-weights.bin') -Value ('0' * 100000)

    # TEST 1: Generate Delta
    Write-Host "`n[Test 1] Generating manifest and delta package..." -ForegroundColor Cyan
    & $generateScript -CurrentDir $v2Dir -OutputDir $distDir -CurrentTag 'v1.0.1' -PreviousDir $v1Dir -PreviousTag 'v1.0.0' -Arch 'x64'

    $patchZip = Join-Path $distDir 'Mobius-Patch-v1.0.0-to-v1.0.1-win32-x64.zip'
    Assert-Condition (Test-Path $patchZip) "Patch zip was created at $patchZip"
    Assert-Condition (Test-Path (Join-Path $distDir 'Mobius-manifest-win32-x64.json')) "Generic manifest created"

    # Inspect patch zip contents to verify only modified/added files are inside
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($patchZip)
    $zipEntries = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') })
    $zip.Dispose()

    Assert-Condition ($zipEntries -contains 'patch-manifest.json') "Patch contains patch-manifest.json"
    Assert-Condition ($zipEntries -contains 'resources/app/package.json') "Patch contains modified package.json"
    Assert-Condition ($zipEntries -contains 'resources/app/out/main.js') "Patch contains modified main.js"
    Assert-Condition ($zipEntries -contains 'resources/app/out/new-feature.js') "Patch contains new-feature.js"
    Assert-Condition ($zipEntries -notcontains 'Mobius.exe') "Unchanged Mobius.exe is excluded from patch"
    Assert-Condition ($zipEntries -notcontains 'resources/app/models/huge-weights.bin') "Unchanged huge weights are excluded from patch"
    Write-Host "PASS: Test 1 - Delta package correctly filtered and packed only differential changes." -ForegroundColor Green

    # TEST 2: Apply Delta to v1
    Write-Host "`n[Test 2] Applying delta update to v1 installation..." -ForegroundColor Cyan
    $res = & $applyScript -InstallDir $v1Dir -PatchZip $patchZip -ExpectedToTag 'v1.0.1'
    Assert-Condition ($res -eq $true) "apply-delta returned true"

    # Verify v1Dir has been updated
    $newInstalledTag = (Get-Content (Join-Path $v1Dir '.mobius-installed-tag') -Raw).Trim()
    Assert-Condition ($newInstalledTag -eq 'v1.0.1') "Installed tag updated to v1.0.1"

    $mainJs = Get-Content (Join-Path $v1Dir 'resources\app\out\main.js') -Raw
    Assert-Condition ($mainJs.Contains('v2 main with speedups')) "main.js updated with v2 contents"

    Assert-Condition (Test-Path (Join-Path $v1Dir 'resources\app\out\new-feature.js')) "new-feature.js exists in installed folder"
    Assert-Condition (-not (Test-Path (Join-Path $v1Dir 'resources\app\out\deprecated.js'))) "deprecated.js was deleted"
    Assert-Condition (Test-Path (Join-Path $v1Dir 'Mobius.exe')) "Mobius.exe still exists"
    Assert-Condition (Test-Path (Join-Path $v1Dir 'unins000.dat')) "Inno Setup unins000.dat preserved intact"
    Assert-Condition (-not (Test-Path (Join-Path $v1Dir '.update-backup'))) ".update-backup was cleaned up"
    Write-Host "PASS: Test 2 - Delta patch applied successfully with correct adds, edits, deletes, and unins retention." -ForegroundColor Green

    # TEST 3: Corruption & Automatic Rollback
    Write-Host "`n[Test 3] Testing corruption rejection and automatic rollback..." -ForegroundColor Cyan
    # Let's create a corrupted patch zip
    $corruptZip = Join-Path $distDir 'corrupt-patch.zip'
    Copy-Item $patchZip $corruptZip

    # Extract, tamper with a file, re-zip
    $corruptStage = Join-Path $testRoot 'corrupt-stage'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($corruptZip, $corruptStage)
    Set-Content -LiteralPath (Join-Path $corruptStage 'resources\app\out\main.js') -Value 'Tampered payload'
    Remove-Item $corruptZip -Force
    [System.IO.Compression.ZipFile]::CreateFromDirectory($corruptStage, $corruptZip)
    Remove-Item $corruptStage -Recurse -Force

    # Snapshot v1 state before test 3
    $beforeMainJs = Get-Content (Join-Path $v1Dir 'resources\app\out\main.js') -Raw
    $beforeTag = (Get-Content (Join-Path $v1Dir '.mobius-installed-tag') -Raw).Trim()

    $caught = $false
    try {
        & $applyScript -InstallDir $v1Dir -PatchZip $corruptZip -ExpectedToTag 'v1.0.1'
    } catch {
        $caught = $true
        Write-Host "Caught expected corruption error: $($_.Exception.Message)" -ForegroundColor DarkGray
    }
    Assert-Condition $caught "Corrupted patch was rejected"

    # Verify rollback: files in v1Dir should be completely unaffected
    $afterMainJs = Get-Content (Join-Path $v1Dir 'resources\app\out\main.js') -Raw
    $afterTag = (Get-Content (Join-Path $v1Dir '.mobius-installed-tag') -Raw).Trim()
    Assert-Condition ($afterMainJs -eq $beforeMainJs) "main.js was preserved via rollback"
    Assert-Condition ($afterTag -eq $beforeTag) "tag was preserved via rollback"
    Write-Host "PASS: Test 3 - Checksum verification caught tampered file before applying, state rolled back safely." -ForegroundColor Green

    Write-Host "`nAll Delta Update unit and integration tests PASSED successfully!" -ForegroundColor Green

} finally {
    if (Test-Path $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
