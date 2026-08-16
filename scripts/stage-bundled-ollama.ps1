# Stage bundled Ollama + default Continue config into VS Code min-ci output tree
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("x64", "arm64")]
    [string]$Arch
)

$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ollama-common.ps1"

$Root = Get-ProjectRoot
$ClientDir = Join-Path (Split-Path -Parent (Join-Path $Root "vscode")) "VSCode-win32-$Arch"

if (-not (Test-Path $ClientDir)) {
    Write-Host "[FAIL] Client build output not found: $ClientDir" -ForegroundColor Red
    Write-Host "       Run gulp vscode-win32-$Arch-min-ci first." -ForegroundColor Yellow
    exit 1
}

$SourceOllama = Get-OllamaResourceDir
if (-not (Test-OllamaAllArchesBundled)) {
    Write-Host "[FAIL] Bundled Ollama incomplete under $SourceOllama" -ForegroundColor Red
    Write-Host "       Run: npm run bundle:ollama" -ForegroundColor Yellow
    exit 1
}

$DestOllama = Join-Path $ClientDir "resources\ollama"
$DestConfigDir = Join-Path $ClientDir "config"
$SourceConfig = Join-Path $Root "config\continue-config.yaml"
$versionFile = Get-OllamaBundledVersionFile

function Test-StagedOllamaReusable {
    if (-not (Test-Path $DestOllama)) { return $false }
    $required = @(
        (Join-Path $DestOllama "bin-amd64\ollama.exe"),
        (Join-Path $DestOllama "bin-arm64\ollama.exe"),
        (Join-Path $DestOllama "models\manifests")
    )
    foreach ($path in $required) {
        if (-not (Test-Path $path)) { return $false }
    }
    if (-not (Test-Path $versionFile)) { return $false }
    $destVersion = Join-Path $DestOllama ".bundled-version"
    if (-not (Test-Path $destVersion)) { return $false }
    $srcVer = (Get-Content $versionFile -Raw).Trim()
    $dstVer = (Get-Content $destVersion -Raw).Trim()
    return ($srcVer -eq $dstVer -and $srcVer -ne "")
}

Write-Host "`n=== Stage Bundled Ollama ($Arch client) ===" -ForegroundColor Cyan
Write-Host "Client : $ClientDir" -ForegroundColor Gray
Write-Host "Ollama : $DestOllama" -ForegroundColor Gray

# Default: reuse already-staged Ollama when version matches (models rarely change).
# Force a refresh with FORCE_OLLAMA_STAGE=1. Explicit skip with SKIP_OLLAMA_STAGE=1.
$forceStage = $env:FORCE_OLLAMA_STAGE -eq "1"
$skipStage = $env:SKIP_OLLAMA_STAGE -eq "1"
if (-not $forceStage -and ($skipStage -or (Test-StagedOllamaReusable))) {
    $reason = if ($skipStage) { "SKIP_OLLAMA_STAGE=1" } else { "version unchanged, already staged" }
    Write-Host "[SKIP] Reusing staged Ollama ($reason)" -ForegroundColor Yellow
} else {
    if (Test-Path $DestOllama) {
        Remove-Item -Recurse -Force $DestOllama
    }
    New-Item -ItemType Directory -Force -Path $DestOllama | Out-Null

    foreach ($name in @("bin-amd64", "bin-arm64", "models")) {
        $src = Join-Path $SourceOllama $name
        if (-not (Test-Path $src)) {
            Write-Host "[FAIL] Missing $src" -ForegroundColor Red
            exit 1
        }
        Write-Host "Copying $name ..." -ForegroundColor Yellow
        Copy-Item -Path $src -Destination (Join-Path $DestOllama $name) -Recurse -Force
    }

    if (Test-Path $versionFile) {
        Copy-Item -Path $versionFile -Destination (Join-Path $DestOllama ".bundled-version") -Force
    }

    $destHome = Join-Path $DestOllama "home"
    New-Item -ItemType Directory -Force -Path $destHome | Out-Null

    $required = @(
        (Join-Path $DestOllama "bin-amd64\ollama.exe"),
        (Join-Path $DestOllama "bin-arm64\ollama.exe"),
        (Join-Path $DestOllama "models\manifests")
    )
    foreach ($path in $required) {
        if (-not (Test-Path $path)) {
            Write-Host "[FAIL] Staged bundle validation failed: $path" -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "[ OK ] Bundled Ollama staged for installer ($DestOllama)" -ForegroundColor Green
}

if (Test-Path $SourceConfig) {
    New-Item -ItemType Directory -Force -Path $DestConfigDir | Out-Null
    $destConfigYaml = Join-Path $DestConfigDir "continue-config.yaml"
    Copy-Item -Path $SourceConfig -Destination $destConfigYaml -Force
    foreach ($cfgName in @("ollama.port", "ollama.version")) {
        $cfgSrc = Join-Path $Root "config\$cfgName"
        if (Test-Path $cfgSrc) {
            Copy-Item -Path $cfgSrc -Destination (Join-Path $DestConfigDir $cfgName) -Force
        }
    }
    Write-Host "Copied Continue + Ollama config -> $DestConfigDir" -ForegroundColor Green

    # Ship workspace .env into the installer so end users get Cloud models by default.
    $sourceEnv = Join-Path $Root ".env"
    if (-not (Test-Path $sourceEnv)) {
        Write-Host "[FAIL] Missing $sourceEnv -- packaged installs need default Cloud model settings." -ForegroundColor Red
        Write-Host "       Copy .env.example to .env and set AI_API_KEY before packaging." -ForegroundColor Yellow
        exit 1
    }

    $envVars = @{}
    foreach ($line in Get-Content $sourceEnv) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith("#")) { continue }
        $eq = $t.IndexOf("=")
        if ($eq -lt 0) { continue }
        $k = $t.Substring(0, $eq).Trim()
        $v = $t.Substring($eq + 1).Trim().Trim('"').Trim("'")
        if ($v) { $envVars[$k] = $v }
    }

    $apiKey = if ($envVars.AI_API_KEY) { $envVars.AI_API_KEY } else { $envVars.OPENAI_API_KEY }
    $provider = if ($envVars.AI_PROVIDER) { $envVars.AI_PROVIDER } elseif ($envVars.OPENAI_PROVIDER) { $envVars.OPENAI_PROVIDER } else { "openai" }
    $baseUrl = if ($envVars.AI_BASE_URL) { $envVars.AI_BASE_URL } elseif ($envVars.OPENAI_BASE_URL) { $envVars.OPENAI_BASE_URL } else { "https://api.openai.com/v1" }
    $model = if ($envVars.AI_MODEL) { $envVars.AI_MODEL } elseif ($envVars.OPENAI_MODEL) { $envVars.OPENAI_MODEL } else { "gpt-4o" }

    if (-not $apiKey -or $provider -eq "ollama") {
        # No cloud key configured (or explicitly ollama-only). This is a supported
        # scenario -- .env.example ships with AI_API_KEY empty and the Onboarding
        # card prompts for a key on first launch. Package a placeholder config
        # instead of refusing to build; baking a real key into an installer that
        # gets distributed would leak it to anyone who unpacks it.
        if ($provider -eq "ollama" -and $apiKey) {
            Write-Host "[WARN] AI_PROVIDER=ollama in .env -- no packaged Cloud model; Onboarding will prompt for a key." -ForegroundColor Yellow
        } else {
            Write-Host "[WARN] AI_API_KEY empty in .env -- packaging placeholder; Onboarding will prompt for a key on first launch." -ForegroundColor Yellow
        }
        $apiKey = ""
        $provider = "openai"
        $baseUrl = "https://api.openai.com/v1"
        $model = "gpt-4o"
    }

    $canonicalEnv = @"
# Mobius - model configuration (shipped with installer)
AI_PROVIDER=$provider
AI_BASE_URL=$baseUrl
AI_API_KEY=$apiKey
AI_MODEL=$model
"@
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $destEnv = Join-Path $DestConfigDir ".env"
    [System.IO.File]::WriteAllText($destEnv, $canonicalEnv, $utf8NoBom)

    # Bake cloud settings into the packaged Continue template (not just the placeholder).
    $yaml = Get-Content -Encoding UTF8 $destConfigYaml -Raw
    $yaml = $yaml -replace '<YOUR_OPENAI_API_KEY>', $apiKey
    $yamlProvider = if ($provider.ToLower() -eq 'xai') { 'xAI' } else { $provider }
    # Allow comment lines between `models:` and the first `- name:` entry.
    $pattern = '(models:\s*\r?\n(?:[ \t]*#[^\r\n]*\r?\n)*)([ \t]*- name: )([^\r\n]+)(\s*\r?\n\s+provider: )([^\r\n]+)(\s*\r?\n\s+model: )([^\r\n]+)(\s*\r?\n(?:\s+useResponsesApi: [^\r\n]+\r?\n)?\s+apiBase: )([^\r\n]+)(\s*\r?\n\s+apiKey: )([^\r\n]+)'
    if ($yaml -match $pattern) {
        $yaml = [regex]::Replace(
            $yaml,
            $pattern,
            "`${1}`${2}$model`${4}$yamlProvider`${6}$model`${8}$baseUrl`${10}`"$apiKey`"",
            1
        )
        Write-Host "[ OK ] Baked Cloud model into continue-config.yaml ($model)" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Could not rewrite first model block in continue-config.yaml; .env still packaged" -ForegroundColor Yellow
    }
    [System.IO.File]::WriteAllText($destConfigYaml, $yaml, $utf8NoBom)
    Write-Host "[ OK ] Packaged default Cloud model ($model @ $baseUrl) -> $DestConfigDir" -ForegroundColor Green
} else {
    Write-Host "[WARN] Missing config template: $SourceConfig" -ForegroundColor Yellow
}
