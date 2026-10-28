# =============================================================================
# Mobius - Incremental Update Delta & Manifest Generator
# Generates file manifests with SHA-256 and creates differential patch packages
# =============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CurrentDir,

    [string]$OutputDir = "dist",
    [string]$CurrentTag = "",
    [string]$Arch = "x64",
    [string]$PreviousManifest = "",
    [string]$PreviousDir = "",
    [string]$PreviousTag = "",
    [string]$Repo = "2441630833/Mobius",
    [switch]$FetchRemotePrevious = $false
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

function Should-IgnoreFile {
    param([string]$RelativePath)
    $normalized = $RelativePath.Replace('\', '/').TrimStart('/')
    $ignoredPatterns = @(
        '^\.update-backup',
        '^\.update-staging',
        '^\.mobius-installed-tag$',
        '^unins000\.',
        '^debug\.log$',
        '\.tmp$'
    )
    foreach ($pat in $ignoredPatterns) {
        if ($normalized -match $pat) { return $true }
    }
    return $false
}

function Build-DirectoryManifest {
    param(
        [string]$Directory,
        [string]$Tag,
        [string]$Architecture,
        [string]$Version
    )

    if (-not (Test-Path $Directory)) {
        throw "Directory does not exist: $Directory"
    }

    $basePath = (Resolve-Path $Directory).Path
    Write-Host "Scanning directory: $basePath..." -ForegroundColor Cyan

    $filesMap = [ordered]@{}
    $allFiles = Get-ChildItem -LiteralPath $basePath -Recurse -File

    $count = 0
    $total = $allFiles.Count
    foreach ($file in $allFiles) {
        $count++
        $rel = $file.FullName.Substring($basePath.Length).TrimStart('\', '/')
        $relUnix = $rel.Replace('\', '/')

        if (Should-IgnoreFile -RelativePath $relUnix) {
            continue
        }

        if ($count % 500 -eq 0 -or $count -eq $total) {
            Write-Progress -Activity "Hashing files" -Status "$count / $total files hashed" -PercentComplete ([int](($count / $total) * 100))
        }

        $hash = Get-FastSha256 -FilePath $file.FullName
        $filesMap[$relUnix] = [ordered]@{
            sha256 = $hash
            size   = $file.Length
        }
    }
    Write-Progress -Activity "Hashing files" -Completed

    $manifest = [ordered]@{
        format      = 1
        tag         = $Tag
        version     = $Version
        arch        = $Architecture
        generatedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        totalFiles  = $filesMap.Count
        files       = $filesMap
    }

    return $manifest
}

# Resolve target directory
$CurrentDir = (Resolve-Path $CurrentDir).Path

# Resolve current version
$version = ""
$pkgJsonPath = Join-Path $CurrentDir "resources\app\package.json"
if (Test-Path $pkgJsonPath) {
    try {
        $pj = Get-Content $pkgJsonPath -Raw | ConvertFrom-Json
        $version = $pj.version
    } catch {}
}
if (-not $version) {
    $version = "1.0.0"
}

if (-not $CurrentTag) {
    $CurrentTag = "v$version"
}

Write-Host "`n=== Mobius Manifest & Delta Generator ===" -ForegroundColor Cyan
Write-Host "Current Directory: $CurrentDir" -ForegroundColor DarkGray
Write-Host "Current Tag      : $CurrentTag ($version, $Arch)" -ForegroundColor DarkGray

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
$OutputDir = (Resolve-Path $OutputDir).Path

# 1. Build Current Manifest
$currentManifest = Build-DirectoryManifest -Directory $CurrentDir -Tag $CurrentTag -Architecture $Arch -Version $version
$manifestJson = $currentManifest | ConvertTo-Json -Depth 5

$manifestNamedFile = Join-Path $OutputDir "Mobius-manifest-${version}-win32-${Arch}.json"
$manifestGenericFile = Join-Path $OutputDir "Mobius-manifest-win32-${Arch}.json"

[System.IO.File]::WriteAllText($manifestNamedFile, $manifestJson, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($manifestGenericFile, $manifestJson, [System.Text.UTF8Encoding]::new($false))

Write-Host "Manifest written: $manifestNamedFile ($($currentManifest.totalFiles) files)" -ForegroundColor Green

# 2. Determine Previous Manifest for Delta Generation
$prevManifest = $null
$prevSource = ""

if ($PreviousManifest -and (Test-Path $PreviousManifest)) {
    Write-Host "Loading previous manifest from file: $PreviousManifest" -ForegroundColor Cyan
    $prevManifest = Get-Content $PreviousManifest -Raw | ConvertFrom-Json
    $prevSource = "local-manifest"
} elseif ($PreviousDir -and (Test-Path $PreviousDir)) {
    Write-Host "Building previous manifest from directory: $PreviousDir" -ForegroundColor Cyan
    $prevManifest = Build-DirectoryManifest -Directory $PreviousDir -Tag ($PreviousTag -or "previous") -Architecture $Arch -Version "previous"
    $prevSource = "local-directory"
} elseif ($FetchRemotePrevious -or ($PreviousTag -and -not $prevManifest)) {
    Write-Host "Attempting to fetch previous manifest from GitHub ($Repo)..." -ForegroundColor Cyan
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    try {
        $headers = @{ "User-Agent" = "Mobius-Delta-Generator" }
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -Headers $headers -UseBasicParsing
        $targetRelease = $null
        if ($PreviousTag) {
            $targetRelease = $releases | Where-Object { $_.tag_name -eq $PreviousTag } | Select-Object -First 1
        } else {
            # Find latest release that is not the current tag
            $targetRelease = $releases | Where-Object { $_.tag_name -ne $CurrentTag } | Select-Object -First 1
        }

        if ($targetRelease) {
            $manifestAsset = $targetRelease.assets | Where-Object { $_.name -like "Mobius-manifest-*-win32-${Arch}.json" -or $_.name -eq "Mobius-manifest-win32-${Arch}.json" } | Select-Object -First 1
            if ($manifestAsset) {
                Write-Host "Found remote manifest in $($targetRelease.tag_name): $($manifestAsset.name)" -ForegroundColor Green
                $rawJson = Invoke-RestMethod -Uri $manifestAsset.browser_download_url -Headers $headers -UseBasicParsing
                if ($rawJson -is [string]) {
                    $prevManifest = $rawJson | ConvertFrom-Json
                } else {
                    $prevManifest = $rawJson
                }
                $PreviousTag = $targetRelease.tag_name
                $prevSource = "github-release"
            }
        }
    } catch {
        Write-Warning "Could not fetch remote manifest from GitHub: $($_.Exception.Message)"
    }
}

# 3. If Previous Manifest Found, Generate Delta
if ($prevManifest -and $prevManifest.files) {
    $prevTag = if ($PreviousTag) { $PreviousTag } elseif ($prevManifest.tag) { $prevManifest.tag } else { "v-prev" }
    Write-Host "`nComparing against previous version: $prevTag (source: $prevSource)" -ForegroundColor Cyan

    $addedFiles = @()
    $modifiedFiles = @()
    $deletedFiles = @()
    $unchangedFiles = @()
    $patchFilesMap = [ordered]@{}

    # Check files in current build
    $currFiles = $currentManifest.files
    $prevFiles = $prevManifest.files

    # Normalize hashtable / psobject access
    $prevFileKeys = if ($prevFiles -is [System.Collections.IDictionary]) {
        [string[]]$prevFiles.Keys
    } else {
        [string[]]($prevFiles.PSObject.Properties | ForEach-Object { $_.Name })
    }

    $currFileKeys = if ($currFiles -is [System.Collections.IDictionary]) {
        [string[]]$currFiles.Keys
    } else {
        [string[]]($currFiles.PSObject.Properties | ForEach-Object { $_.Name })
    }

    $prevLookup = @{}
    foreach ($k in $prevFileKeys) {
        $entry = if ($prevFiles -is [System.Collections.IDictionary]) { $prevFiles[$k] } else { $prevFiles.$k }
        $prevLookup[$k] = $entry
    }

    $currLookup = @{}
    foreach ($k in $currFileKeys) {
        $entry = if ($currFiles -is [System.Collections.IDictionary]) { $currFiles[$k] } else { $currFiles.$k }
        $currLookup[$k] = $entry
    }

    foreach ($rel in $currFileKeys) {
        $currItem = $currLookup[$rel]
        if (-not $prevLookup.ContainsKey($rel)) {
            $addedFiles += $rel
            $patchFilesMap[$rel] = $currItem
        } else {
            $prevItem = $prevLookup[$rel]
            if ($currItem.sha256 -ne $prevItem.sha256) {
                $modifiedFiles += $rel
                $patchFilesMap[$rel] = $currItem
            } else {
                $unchangedFiles += $rel
            }
        }
    }

    foreach ($rel in $prevFileKeys) {
        if (-not $currLookup.ContainsKey($rel)) {
            $deletedFiles += $rel
        }
    }

    $patchTotalBytes = 0
    foreach ($k in $patchFilesMap.Keys) {
        $patchTotalBytes += $patchFilesMap[$k].size
    }

    Write-Host "Delta analysis:" -ForegroundColor Yellow
    Write-Host "  Added     : $($addedFiles.Count)" -ForegroundColor Green
    Write-Host "  Modified  : $($modifiedFiles.Count)" -ForegroundColor Green
    Write-Host "  Deleted   : $($deletedFiles.Count)" -ForegroundColor Yellow
    Write-Host "  Unchanged : $($unchangedFiles.Count)" -ForegroundColor DarkGray
    Write-Host "  Patch Size (uncompressed): $([math]::Round($patchTotalBytes / 1MB, 2)) MB" -ForegroundColor Cyan

    # Stage files for delta zip
    $stagingDir = Join-Path $OutputDir ("patch-stage-" + [guid]::NewGuid())
    try {
        New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

        $patchManifest = [ordered]@{
            format       = 1
            fromTag      = $prevTag
            toTag        = $CurrentTag
            version      = $version
            arch         = $Arch
            createdAt    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            added        = $addedFiles
            modified     = $modifiedFiles
            deleted      = $deletedFiles
            files        = $patchFilesMap
        }

        $patchManifestJson = $patchManifest | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText((Join-Path $stagingDir "patch-manifest.json"), $patchManifestJson, [System.Text.UTF8Encoding]::new($false))

        foreach ($rel in $patchFilesMap.Keys) {
            $srcPath = Join-Path $CurrentDir ($rel.Replace('/', '\'))
            $destPath = Join-Path $stagingDir ($rel.Replace('/', '\'))
            $destDir = Split-Path $destPath -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            Copy-Item -LiteralPath $srcPath -Destination $destPath -Force
        }

        # Create zip archives
        $patchZipNamed = Join-Path $OutputDir "Mobius-Patch-${prevTag}-to-${CurrentTag}-win32-${Arch}.zip"
        $patchZipGeneric = Join-Path $OutputDir "Mobius-Patch-win32-${Arch}.zip"

        if (Test-Path $patchZipNamed) { Remove-Item -LiteralPath $patchZipNamed -Force }
        if (Test-Path $patchZipGeneric) { Remove-Item -LiteralPath $patchZipGeneric -Force }

        Write-Host "Compressing delta package..." -ForegroundColor Cyan
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stagingDir, $patchZipNamed, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        Copy-Item -LiteralPath $patchZipNamed -Destination $patchZipGeneric -Force

        $zipSize = (Get-Item $patchZipNamed).Length
        Write-Host "Delta package created successfully!" -ForegroundColor Green
        Write-Host "  Patch Archive : $patchZipNamed" -ForegroundColor White
        Write-Host "  Archive Size  : $([math]::Round($zipSize / 1MB, 2)) MB" -ForegroundColor White
    } finally {
        if (Test-Path $stagingDir) {
            Remove-Item -LiteralPath $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
} else {
    Write-Host "No previous manifest or directory available. Only manifest was generated." -ForegroundColor DarkGray
}

Write-Host "`nGenerator complete." -ForegroundColor Green
