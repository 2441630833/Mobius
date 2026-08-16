# Shared helpers for bundled Ollama (Mobius -- Option C, dual-arch)
$ErrorActionPreference = "Stop"

$script:OllamaEmbedModel = "nomic-embed-text"
$script:OllamaOcrModel = "glm-ocr"
# Chat models (qwen*) are retired -- Ollama is embed + OCR only.
$script:OllamaRetiredModels = @(
    "qwen3.5:2b",
    "qwen3.5",
    "qwen3.5:4b",
    "qwen3-vl:4b",
    "qwen3-vl",
    "qwen2.5-coder:3b",
    "hhao/qwen2.5-coder-tools:3b",
    "hhao/qwen2.5-coder-tools",
    "MedAIBase/PaddleOCR-VL:0.9b",
    "MedAIBase/PaddleOCR-VL"
)
# Relative to manifests/registry.ollama.ai/ -- library/* or org/name paths.
$script:OllamaRetiredManifestDirs = @(
    "library\qwen3.5",
    "library\qwen3-vl",
    "library\qwen2.5-coder",
    "MedAIBase\PaddleOCR-VL"
)
$script:OllamaSupportedArches = @("amd64", "arm64")

function Get-ProjectRoot {
    return Split-Path -Parent $PSScriptRoot
}

function Get-MobiusInstallRoot {
    if ($env:MOBIUS_ROOT) {
        return $env:MOBIUS_ROOT
    }
    $repoRoot = Get-ProjectRoot
    if (Test-Path (Join-Path $repoRoot "vscode\scripts\code.bat")) {
        return $repoRoot
    }
    return $repoRoot
}

function Get-OllamaPort {
    $portFile = Join-Path (Get-MobiusInstallRoot) "config\ollama.port"
    if (-not (Test-Path $portFile)) {
        throw "Missing config/ollama.port"
    }
    return (Get-Content $portFile -Raw).Trim()
}

$script:OllamaPort = Get-OllamaPort
$script:OllamaApiBase = "http://127.0.0.1:$($script:OllamaPort)"
$script:OllamaApiBaseLocalhost = "http://localhost:$($script:OllamaPort)"

function Get-OllamaVersion {
    $versionFile = Join-Path (Get-MobiusInstallRoot) "config\ollama.version"
    if (-not (Test-Path $versionFile)) {
        throw "Missing config/ollama.version"
    }
    return (Get-Content $versionFile -Raw).Trim()
}

function Get-WindowsCpuArch {
    # PROCESSOR_ARCHITEW6432 is the native OS arch when running under WoW64 emulation.
    $native = $env:PROCESSOR_ARCHITEW6432
    if (-not $native) {
        $native = $env:PROCESSOR_ARCHITECTURE
    }
    switch ($native.ToUpperInvariant()) {
        "ARM64" { return "arm64" }
        default { return "amd64" }
    }
}

function Get-OllamaResourceDir {
    return Join-Path (Get-MobiusInstallRoot) "resources\ollama"
}

function Get-OllamaBinDir {
    param([string]$Arch = (Get-WindowsCpuArch))
    return Join-Path (Get-OllamaResourceDir) "bin-$Arch"
}

function Get-OllamaExe {
    param([string]$Arch = (Get-WindowsCpuArch))
    return Join-Path (Get-OllamaBinDir -Arch $Arch) "ollama.exe"
}

function Get-OllamaModelsDir {
    return Join-Path (Get-OllamaResourceDir) "models"
}

function Get-OllamaHomeDir {
    return Join-Path (Get-OllamaResourceDir) "home"
}

function Get-OllamaBundledVersionFile {
    return Join-Path (Get-OllamaResourceDir) ".bundled-version"
}

function Get-OllamaDownloadUrl {
    param(
        [string]$Version = (Get-OllamaVersion),
        [Parameter(Mandatory = $true)][string]$Arch
    )
    return "https://github.com/ollama/ollama/releases/download/v$Version/ollama-windows-$Arch.zip"
}

function Get-OllamaZipPathForArch {
    param([Parameter(Mandatory = $true)][string]$Arch)

    $envVar = "OLLAMA_ZIP_PATH_$($Arch.ToUpper())"
    $fromEnv = [Environment]::GetEnvironmentVariable($envVar)
    if ($fromEnv) {
        return $fromEnv
    }

    if ($env:OLLAMA_ZIP_PATH -and $Arch -eq (Get-WindowsCpuArch)) {
        return $env:OLLAMA_ZIP_PATH
    }

    return Join-Path (Get-OllamaResourceDir) "ollama-windows-$Arch.zip"
}

function Invoke-OllamaDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [int]$MaxAttempts = 3
    )

    $ProgressPreference = "SilentlyContinue"
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            if ($attempt -gt 1) {
                $waitSec = [math]::Min(30, 5 * $attempt)
                Write-Host "Retry $attempt/$MaxAttempts in ${waitSec}s..." -ForegroundColor Yellow
                Start-Sleep -Seconds $waitSec
            }
            Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
            return
        } catch {
            if ($attempt -eq $MaxAttempts) { throw }
            Write-Host "Download attempt $attempt failed: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
}

function Move-LegacyOllamaBin {
    $legacyDir = Join-Path (Get-OllamaResourceDir) "bin"
    $legacyExe = Join-Path $legacyDir "ollama.exe"
    $amd64Dir = Get-OllamaBinDir -Arch "amd64"
    $amd64Exe = Join-Path $amd64Dir "ollama.exe"

    if ((Test-Path $legacyExe) -and -not (Test-Path $amd64Exe)) {
        Write-Host "Migrating legacy resources/ollama/bin -> bin-amd64" -ForegroundColor Yellow
        if (Test-Path $amd64Dir) {
            Remove-Item -Recurse -Force $amd64Dir
        }
        Move-Item -Path $legacyDir -Destination $amd64Dir
    }
}

function Install-OllamaFromZip {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$Arch
    )

    $binDir = Get-OllamaBinDir -Arch $Arch
    $ollamaExe = Join-Path $binDir "ollama.exe"
    $resourceDir = Get-OllamaResourceDir
    $extractTemp = Join-Path $resourceDir "_extract_tmp_$Arch"

    if (-not (Test-Path $ZipPath)) {
        throw "Zip not found: $ZipPath"
    }

    Initialize-OllamaDirectories
    if (Test-Path $extractTemp) {
        Remove-Item -Recurse -Force $extractTemp
    }
    New-Item -ItemType Directory -Force -Path $extractTemp | Out-Null

    try {
        Write-Host "Extracting $Arch to $binDir ..." -ForegroundColor Yellow
        Expand-Archive -Path $ZipPath -DestinationPath $extractTemp -Force

        $foundExe = Get-ChildItem -Path $extractTemp -Recurse -Filter "ollama.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $foundExe) {
            throw "ollama.exe not found inside archive: $ZipPath"
        }

        if (Test-Path $binDir) {
            Remove-Item -Recurse -Force $binDir
        }
        New-Item -ItemType Directory -Force -Path $binDir | Out-Null

        $sourceDir = $foundExe.Directory.FullName
        Get-ChildItem -Path $sourceDir -Force | ForEach-Object {
            Copy-Item -Path $_.FullName -Destination $binDir -Recurse -Force
        }

        if (-not (Test-Path $ollamaExe)) {
            throw "Failed to install ollama.exe to $binDir"
        }

        Write-Host "[ OK ] Ollama $Arch binary bundled" -ForegroundColor Green
    } finally {
        if (Test-Path $extractTemp) {
            Remove-Item -Recurse -Force $extractTemp -ErrorAction SilentlyContinue
        }
    }
}

function Initialize-OllamaDirectories {
    Move-LegacyOllamaBin

    $dirs = @(
        (Get-OllamaResourceDir),
        (Get-OllamaModelsDir),
        (Get-OllamaHomeDir)
    )
    foreach ($arch in $script:OllamaSupportedArches) {
        $dirs += Get-OllamaBinDir -Arch $arch
    }

    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
        }
    }
}

function Set-OllamaEnvironment {
    param([string]$Arch = (Get-WindowsCpuArch))

    $env:OLLAMA_HOME = Get-OllamaHomeDir
    $env:OLLAMA_MODELS = Get-OllamaModelsDir
    $env:OLLAMA_HOST = "127.0.0.1:$script:OllamaPort"
    $binDir = Get-OllamaBinDir -Arch $Arch
    if ($env:PATH -notlike "*$binDir*") {
        $env:PATH = "$binDir;$env:PATH"
    }
}

function Test-OllamaArchBundled {
    param([Parameter(Mandatory = $true)][string]$Arch)
    return Test-Path (Get-OllamaExe -Arch $Arch)
}

function Test-OllamaBundled {
    param([string]$Arch = (Get-WindowsCpuArch))
    return Test-OllamaArchBundled -Arch $Arch
}

function Test-OllamaAllArchesBundled {
    param([string]$Version = (Get-OllamaVersion))

    $marker = Get-OllamaBundledVersionFile
    if (-not (Test-Path $marker)) {
        return $false
    }
    if ((Get-Content $marker -Raw).Trim() -ne $Version) {
        return $false
    }

    foreach ($arch in $script:OllamaSupportedArches) {
        if (-not (Test-OllamaArchBundled -Arch $arch)) {
            return $false
        }
    }
    return $true
}

function Test-OllamaServer {
    param([int]$TimeoutSec = 2)
    try {
        $null = Invoke-RestMethod -Uri "$script:OllamaApiBase/api/version" -TimeoutSec $TimeoutSec
        return $true
    } catch {
        return $false
    }
}

function Wait-OllamaServer {
    param(
        [int]$TimeoutSec = 120,
        [string]$Label = "Ollama"
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        if (Test-OllamaServer) {
            return $true
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 1
    }
    Write-Host ""
    Write-Host "[FAIL] Timed out waiting for $Label on $script:OllamaApiBase" -ForegroundColor Red
    return $false
}

function Start-BundledOllamaServer {
    $arch = Get-WindowsCpuArch

    if (-not (Test-OllamaBundled -Arch $arch)) {
        throw "Bundled Ollama ($arch) not found at $(Get-OllamaExe -Arch $arch). Run: npm run bundle:ollama"
    }

    if (Test-OllamaServer) {
        return $null
    }

    Initialize-OllamaDirectories
    Set-OllamaEnvironment -Arch $arch

    Write-Host "Starting bundled Ollama ($arch) (ollama serve)..." -ForegroundColor Yellow
    $proc = Start-Process -FilePath (Get-OllamaExe -Arch $arch) `
        -ArgumentList "serve" `
        -WorkingDirectory (Get-OllamaBinDir -Arch $arch) `
        -WindowStyle Hidden `
        -PassThru

    if (-not (Wait-OllamaServer -Label "bundled Ollama ($arch)")) {
        if ($proc -and -not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        }
        throw "Bundled Ollama ($arch) failed to start"
    }

    Write-Host "[ OK ] Bundled Ollama ($arch) ready at $script:OllamaApiBase" -ForegroundColor Green
    return $proc
}

function Get-OllamaReferencedBlobNames {
    param([string]$ModelsDir = (Get-OllamaModelsDir))

    $blobNames = New-Object 'System.Collections.Generic.HashSet[string]'
    $manifestRoot = Join-Path $ModelsDir "manifests"
    if (-not (Test-Path $manifestRoot)) {
        return $blobNames
    }

    Get-ChildItem -Path $manifestRoot -Recurse -File | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        foreach ($match in [regex]::Matches($content, '"digest":"sha256:([a-f0-9]+)"')) {
            [void]$blobNames.Add("sha256-$($match.Groups[1].Value)")
        }
    }
    return $blobNames
}

function Remove-OllamaOrphanBlobs {
    param([switch]$Quiet)

    $blobsDir = Join-Path (Get-OllamaModelsDir) "blobs"
    if (-not (Test-Path $blobsDir)) {
        return
    }

    $referenced = Get-OllamaReferencedBlobNames
    foreach ($blob in Get-ChildItem $blobsDir -File) {
        if ($referenced.Contains($blob.Name)) {
            continue
        }
        if (-not $Quiet) {
            Write-Host "Removing orphan blob: $($blob.Name)" -ForegroundColor Yellow
        }
        try {
            Remove-Item $blob.FullName -Force -ErrorAction Stop
        } catch {
            if (-not $Quiet) {
                Write-Host "Skipping locked blob (retry after stopping Ollama): $($blob.Name)" -ForegroundColor DarkYellow
            }
        }
    }
}

function Remove-OllamaRetiredModels {
    param([switch]$Quiet)

    $registryRoot = Join-Path (Get-OllamaModelsDir) "manifests\registry.ollama.ai"
    foreach ($relPath in $script:OllamaRetiredManifestDirs) {
        $manifestDir = Join-Path $registryRoot $relPath
        if (-not (Test-Path $manifestDir)) {
            continue
        }
        if (-not $Quiet) {
            Write-Host "Removing retired Ollama manifest: $manifestDir" -ForegroundColor Yellow
        }
        Remove-Item -Recurse -Force $manifestDir
    }

    if (Test-OllamaServer) {
        Set-OllamaEnvironment
        $ollamaExe = Get-OllamaExe
        $installed = @()
        try {
            $resp = Invoke-RestMethod -Uri "$script:OllamaApiBase/api/tags" -TimeoutSec 5
            $installed = @($resp.models | ForEach-Object { $_.name })
        } catch {
            $installed = @()
        }

        foreach ($model in $script:OllamaRetiredModels) {
            $isInstalled = $false
            foreach ($name in $installed) {
                if ($name -eq $model -or $name -like "$model*") {
                    $isInstalled = $true
                    break
                }
            }
            if (-not $isInstalled) {
                continue
            }

            if (-not $Quiet) {
                Write-Host "Uninstalling retired Ollama model: $model" -ForegroundColor Yellow
            }
            $prevErrorAction = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                & $ollamaExe @("rm", $model) 2>&1 | Out-Null
            } finally {
                $ErrorActionPreference = $prevErrorAction
            }
        }
    }

    Remove-OllamaOrphanBlobs -Quiet:$Quiet
}

function Test-OllamaOcrModel {
    try {
        $resp = Invoke-RestMethod -Uri "$script:OllamaApiBase/api/tags" -TimeoutSec 5
        foreach ($model in @($resp.models)) {
            if ($model.name -eq $script:OllamaOcrModel -or $model.name -like "$($script:OllamaOcrModel)*") {
                return $true
            }
            # Ollama may normalize org/name casing
            if ($model.name -ieq $script:OllamaOcrModel) {
                return $true
            }
        }
        return $false
    } catch {
        return $false
    }
}

function Ensure-OllamaOcrModel {
    param([switch]$Quiet)

    if (Test-OllamaOcrModel) {
        if (-not $Quiet) {
            Write-Host "[ OK ] Local OCR model: $script:OllamaOcrModel" -ForegroundColor Green
        }
        return
    }

    if (-not $Quiet) {
        Write-Host "Pulling $script:OllamaOcrModel (bundled local OCR)..." -ForegroundColor Yellow
    }
    Invoke-OllamaCli -Arguments @("pull", $script:OllamaOcrModel)
}

function Test-OllamaEmbedModel {
    try {
        $resp = Invoke-RestMethod -Uri "$script:OllamaApiBase/api/tags" -TimeoutSec 5
        foreach ($model in @($resp.models)) {
            if ($model.name -eq $script:OllamaEmbedModel -or $model.name -like "$($script:OllamaEmbedModel)*") {
                return $true
            }
        }
        return $false
    } catch {
        return $false
    }
}

function Invoke-OllamaCli {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $arch = Get-WindowsCpuArch
    if (-not (Test-OllamaBundled -Arch $arch)) {
        throw "Bundled Ollama ($arch) not found. Run: npm run bundle:ollama"
    }

    Set-OllamaEnvironment -Arch $arch
    & (Get-OllamaExe -Arch $arch) @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "ollama $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
}

function Ensure-OllamaEmbedModel {
    param([switch]$Quiet)

    if (Test-OllamaEmbedModel) {
        if (-not $Quiet) {
            Write-Host "[ OK ] Embedding model: $script:OllamaEmbedModel" -ForegroundColor Green
        }
        return
    }

    if (-not $Quiet) {
        Write-Host "Pulling $script:OllamaEmbedModel (codebase embeddings)..." -ForegroundColor Yellow
    }
    Invoke-OllamaCli -Arguments @("pull", $script:OllamaEmbedModel)
}

function Test-OllamaEmbedApi {
    try {
        $body = @{ model = $script:OllamaEmbedModel; input = @("test") } | ConvertTo-Json -Compress
        $resp = Invoke-RestMethod -Uri "$script:OllamaApiBase/api/embed" `
            -Method POST -ContentType "application/json" -Body $body -TimeoutSec 30
        return [bool]$resp.embeddings
    } catch {
        return $false
    }
}

# Load nomic-embed-text into llama-server before the IDE floods /api/embed.
# Without this, early embed requests get "dial tcp 127.0.0.1:3111: connection refused"
# and can wedge Ollama so local chat hangs with no response.
function Wait-OllamaEmbedReady {
    param(
        [int]$TimeoutSec = 90,
        [switch]$Quiet
    )

    if (-not (Test-OllamaEmbedModel)) {
        return $false
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    if (-not $Quiet) {
        Write-Host "Warming embedding model ($script:OllamaEmbedModel)..." -ForegroundColor Yellow -NoNewline
    }
    while ((Get-Date) -lt $deadline) {
        if (Test-OllamaEmbedApi) {
            if (-not $Quiet) {
                Write-Host " ready" -ForegroundColor Green
            }
            return $true
        }
        if (-not $Quiet) {
            Write-Host "." -NoNewline
        }
        Start-Sleep -Seconds 1
    }
    if (-not $Quiet) {
        Write-Host ""
        Write-Host "[WARN] Embedding warm-up timed out -- codebase indexing may fail until the runner starts" -ForegroundColor Yellow
    }
    return $false
}

function Install-OllamaArchBundle {
    param(
        [Parameter(Mandatory = $true)][string]$Arch,
        [Parameter(Mandatory = $true)][string]$Version
    )

    $url = Get-OllamaDownloadUrl -Version $Version -Arch $Arch
    $zipPath = Get-OllamaZipPathForArch -Arch $Arch
    $envVar = "OLLAMA_ZIP_PATH_$($Arch.ToUpper())"
    $hasLocalZip = [bool][Environment]::GetEnvironmentVariable($envVar) -or (
        $env:OLLAMA_ZIP_PATH -and $Arch -eq (Get-WindowsCpuArch)
    )

    if ($hasLocalZip) {
        Write-Host "Using local zip for $Arch : $zipPath" -ForegroundColor Cyan
        Install-OllamaFromZip -ZipPath $zipPath -Arch $Arch
        return
    }

    $sizeHint = if ($Arch -eq "arm64") { "~15 MB" } else { "~1.4 GB" }
    Write-Host "Downloading Ollama v$Version for Windows $Arch ($sizeHint)..." -ForegroundColor Yellow
    Write-Host "URL: $url" -ForegroundColor Gray

    try {
        Invoke-OllamaDownload -Url $url -OutFile $zipPath
        Write-Host "[ OK ] Download complete ($Arch)" -ForegroundColor Green
        Install-OllamaFromZip -ZipPath $zipPath -Arch $Arch
    } catch {
        Write-Host ""
        Write-Host "[FAIL] Download failed for $Arch : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        Write-Host "Manual fallback for $Arch :" -ForegroundColor Yellow
        Write-Host "  1. Download: $url" -ForegroundColor White
        Write-Host "  2. Run: `$env:OLLAMA_ZIP_PATH_$($Arch.ToUpper())='<path-to-zip>'; npm run bundle:ollama" -ForegroundColor White
        Write-Host ""
        throw
    } finally {
        if (-not $hasLocalZip -and (Test-Path $zipPath)) {
            Remove-Item -Force $zipPath -ErrorAction SilentlyContinue
        }
    }
}

function Assert-OllamaBundled {
    $arch = Get-WindowsCpuArch
    if (Test-OllamaBundled -Arch $arch) { return }

    Write-Host ""
    Write-Host "Bundled Ollama ($arch) is not installed in resources/ollama/bin-$arch/." -ForegroundColor Red
    Write-Host "Run once (downloads amd64 ~1.4 GB + arm64 ~15 MB):" -ForegroundColor Yellow
    Write-Host "  npm run bundle:ollama" -ForegroundColor White
    Write-Host ""
    Write-Host "@codebase indexing requires this step. Chat/Agent still work without it." -ForegroundColor Gray
    Write-Host ""
    exit 1
}
