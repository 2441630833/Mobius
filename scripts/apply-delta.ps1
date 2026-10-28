# =============================================================================
# Mobius - Incremental Update Delta Installer / Applier
# Safely verifies and applies a differential patch package to an existing installation
# Includes pre-flight hash verification, atomic backup, and automatic rollback on failure
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallDir,

    [Parameter(Mandatory = $true)]
    [string]$PatchZip,

    [string]$ExpectedToTag = "",
    [string]$ExpectedSha256 = "",
    [switch]$KeepBackup = $false
)

$ErrorActionPreference = "Stop"

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction SilentlyContinue
} catch {}

function Get-FastSha256 {
    param([string]$FilePath)
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($FilePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $hashBytes = $hasher.ComputeHash($stream)
        return ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLowerInvariant()
    } finally {
        if ($stream) { $stream.Dispose() }
        $hasher.Dispose()
    }
}

function Test-DirectoryWritable {
    param([string]$Directory)
    $testFile = Join-Path $Directory (".mobius-write-test-" + [guid]::NewGuid().ToString("N"))
    try {
        [System.IO.File]::WriteAllText($testFile, "test")
        Remove-Item -LiteralPath $testFile -Force -ErrorAction SilentlyContinue
        return $true
    } catch {
        return $false
    }
}

# 1. Pre-flight Checks
if (-not (Test-Path $InstallDir)) {
    throw "Installation directory does not exist: $InstallDir"
}
$InstallDir = (Resolve-Path $InstallDir).Path

$mobiusExe = Join-Path $InstallDir "Mobius.exe"
if (-not (Test-Path $mobiusExe)) {
    throw "Mobius.exe not found in $InstallDir. Cannot apply incremental patch to an invalid installation."
}

if (-not (Test-Path $PatchZip)) {
    throw "Patch archive not found: $PatchZip"
}
$PatchZip = (Resolve-Path $PatchZip).Path

if (-not (Test-DirectoryWritable -Directory $InstallDir)) {
    throw "Installation directory is not writable (insufficient permissions): $InstallDir"
}

# Verify Patch Zip SHA-256 if expected
if ($ExpectedSha256) {
    Write-Host "Verifying patch archive checksum..." -ForegroundColor Cyan
    $actualZipHash = Get-FastSha256 -FilePath $PatchZip
    if ($actualZipHash -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "Patch archive SHA-256 mismatch! Expected $ExpectedSha256, got $actualZipHash"
    }
}

# 2. Extract Patch to Staging
$stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("mobius-patch-stage-" + [guid]::NewGuid().ToString("N"))
$backupDir = Join-Path $InstallDir ".update-backup"
$appliedFiles = @()

try {
    Write-Host "Extracting differential patch to staging..." -ForegroundColor Cyan
    [System.IO.Compression.ZipFile]::ExtractToDirectory($PatchZip, $stagingDir)

    $patchManifestPath = Join-Path $stagingDir "patch-manifest.json"
    if (-not (Test-Path $patchManifestPath)) {
        throw "Invalid patch package: missing patch-manifest.json"
    }

    $patchManifest = Get-Content $patchManifestPath -Raw | ConvertFrom-Json
    $toTag = $patchManifest.toTag
    $fromTag = $patchManifest.fromTag

    if ($ExpectedToTag -and $toTag -and ($toTag -ne $ExpectedToTag)) {
        throw "Patch target version mismatch! Manifest toTag is '$toTag', expected '$ExpectedToTag'"
    }

    Write-Host "Patch Details:" -ForegroundColor DarkGray
    Write-Host "  From Version : $fromTag" -ForegroundColor DarkGray
    Write-Host "  To Version   : $toTag" -ForegroundColor DarkGray
    Write-Host "  Files Count  : $($patchManifest.modified.Count + $patchManifest.added.Count) modified/added, $($patchManifest.deleted.Count) deleted" -ForegroundColor DarkGray

    # 3. Verify all staged files against manifest checksums
    Write-Host "Validating staged payload checksums..." -ForegroundColor Cyan
    $patchFiles = $patchManifest.files

    $fileKeys = if ($patchFiles -is [System.Collections.IDictionary]) {
        [string[]]$patchFiles.Keys
    } else {
        [string[]]($patchFiles.PSObject.Properties | ForEach-Object { $_.Name })
    }

    foreach ($rel in $fileKeys) {
        $stagedFilePath = Join-Path $stagingDir ($rel.Replace('/', '\'))
        if (-not (Test-Path $stagedFilePath)) {
            throw "Staged file missing from patch archive: $rel"
        }
        $expectedHash = if ($patchFiles -is [System.Collections.IDictionary]) { $patchFiles[$rel].sha256 } else { $patchFiles.$rel.sha256 }
        $actualHash = Get-FastSha256 -FilePath $stagedFilePath
        if ($actualHash -ne $expectedHash) {
            throw "Corrupted file in patch payload ($rel): expected hash $expectedHash, got $actualHash"
        }
    }

    # 4. Create Backup of files that will be overwritten or deleted
    Write-Host "Creating safety backup of modified files..." -ForegroundColor Cyan
    if (Test-Path $backupDir) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

    $backupList = @()
    foreach ($rel in $fileKeys) {
        $destFile = Join-Path $InstallDir ($rel.Replace('/', '\'))
        if (Test-Path -LiteralPath $destFile) {
            $backupFile = Join-Path $backupDir ($rel.Replace('/', '\'))
            $backupFileDir = Split-Path $backupFile -Parent
            if (-not (Test-Path $backupFileDir)) {
                New-Item -ItemType Directory -Path $backupFileDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $destFile -Destination $backupFile -Force
            $backupList += $rel
        }
    }

    if ($patchManifest.deleted) {
        foreach ($rel in $patchManifest.deleted) {
            $destFile = Join-Path $InstallDir ($rel.Replace('/', '\'))
            if (Test-Path -LiteralPath $destFile) {
                $backupFile = Join-Path $backupDir ($rel.Replace('/', '\'))
                $backupFileDir = Split-Path $backupFile -Parent
                if (-not (Test-Path $backupFileDir)) {
                    New-Item -ItemType Directory -Path $backupFileDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $destFile -Destination $backupFile -Force
                $backupList += $rel
            }
        }
    }
    Write-Host "Safety backup created ($($backupList.Count) existing files backed up)." -ForegroundColor DarkGray

    # 5. Apply Updates (Atomic Copy)
    Write-Host "Applying updates to $InstallDir..." -ForegroundColor Cyan

    # Copy files
    foreach ($rel in $fileKeys) {
        $stagedFilePath = Join-Path $stagingDir ($rel.Replace('/', '\'))
        $destFile = Join-Path $InstallDir ($rel.Replace('/', '\'))
        $destFileDir = Split-Path $destFile -Parent
        if (-not (Test-Path $destFileDir)) {
            New-Item -ItemType Directory -Path $destFileDir -Force | Out-Null
        }
        Copy-Item -LiteralPath $stagedFilePath -Destination $destFile -Force
        $appliedFiles += $rel
    }

    # Delete removed files
    if ($patchManifest.deleted) {
        foreach ($rel in $patchManifest.deleted) {
            $destFile = Join-Path $InstallDir ($rel.Replace('/', '\'))
            if (Test-Path -LiteralPath $destFile) {
                Remove-Item -LiteralPath $destFile -Force -ErrorAction SilentlyContinue
            }
        }
    }

    # Verify critical files exist
    if (-not (Test-Path (Join-Path $InstallDir "Mobius.exe"))) {
        throw "Post-patch verification failed: Mobius.exe is missing"
    }

    $productJson = Join-Path $InstallDir "resources\app\product.json"
    $pkgJson = Join-Path $InstallDir "resources\app\package.json"
    if ((-not (Test-Path $productJson)) -and (-not (Test-Path $pkgJson))) {
        throw "Post-patch verification failed: Core application manifests missing"
    }

    # Record updated tag
    $tagFile = Join-Path $InstallDir ".mobius-installed-tag"
    Set-Content -LiteralPath $tagFile -Value $toTag -Encoding UTF8 -Force

    # Record patch history
    $patchHistoryFile = Join-Path $InstallDir ".mobius-patch-history.json"
    $historyEntry = [ordered]@{
        fromTag   = $fromTag
        toTag     = $toTag
        appliedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }
    try {
        $history = @()
        if (Test-Path $patchHistoryFile) {
            $history = @(Get-Content $patchHistoryFile -Raw | ConvertFrom-Json)
        }
        $history += $historyEntry
        Set-Content -LiteralPath $patchHistoryFile -Value ($history | ConvertTo-Json -Depth 3) -Encoding UTF8 -Force
    } catch {}

    # Cleanup backup on complete success unless requested to keep
    if (-not $KeepBackup -and (Test-Path $backupDir)) {
        Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Host "`n[Success] Incremental update to $toTag completed successfully!" -ForegroundColor Green
    return $true

} catch {
    Write-Warning "`n[FAILURE] Error applying incremental patch: $($_.Exception.Message)"
    Write-Warning "Initiating automatic rollback to preserve working installation..."

    # Perform Rollback
    if (Test-Path $backupDir) {
        try {
            $backedFiles = Get-ChildItem -LiteralPath $backupDir -Recurse -File
            foreach ($bf in $backedFiles) {
                $rel = $bf.FullName.Substring($backupDir.Length).TrimStart('\', '/')
                $dest = Join-Path $InstallDir $rel
                $destDir = Split-Path $dest -Parent
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                Copy-Item -LiteralPath $bf.FullName -Destination $dest -Force
            }
            Write-Host "Rollback completed. Restored $($backedFiles.Count) files." -ForegroundColor Yellow
        } catch {
            Write-Error "CRITICAL: Rollback encountered an error: $($_.Exception.Message)"
        } finally {
            Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    throw $_
} finally {
    if (Test-Path $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
