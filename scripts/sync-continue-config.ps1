# Sync .env -> ~/.continue/config.yaml (does not reset model to repo template defaults)
$ErrorActionPreference = "Stop"
. "$PSScriptRoot\ollama-common.ps1"
$Root = Split-Path -Parent $PSScriptRoot
$EnvFile = Join-Path $Root ".env"
$ContinueDir = Join-Path $env:USERPROFILE ".continue"
$ContinueEnvFile = Join-Path $ContinueDir ".env"
$ConfigFile = Join-Path $ContinueDir "config.yaml"
$TemplatePath = Join-Path $Root "config\continue-config.yaml"

if (-not (Test-Path $EnvFile) -and -not (Test-Path $ContinueEnvFile)) {
    Write-Host "No .env found -- skipping Continue config sync" -ForegroundColor Yellow
    return
}

function Read-EnvFile($path) {
    $vars = @{}
    foreach ($line in Get-Content -Encoding UTF8 $path) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith("#")) { continue }
        $eq = $t.IndexOf("=")
        if ($eq -lt 0) { continue }
        $k = $t.Substring(0, $eq).Trim()
        $v = $t.Substring($eq + 1).Trim().Trim('"').Trim("'")
        if ($v) { $vars[$k] = $v }
    }
    return $vars
}

function Is-OfficialOpenAiBase([string]$baseUrl) {
    return (($baseUrl.TrimEnd('/') + '/') -eq 'https://api.openai.com/v1/')
}

function Is-OfficialAnthropicBase([string]$baseUrl) {
    return (($baseUrl.TrimEnd('/') + '/') -eq 'https://api.anthropic.com/v1/')
}

function Provider-ForYaml([string]$provider) {
    if ($provider.ToLower() -eq 'xai') { return 'xAI' }
    return $provider
}

function Env-HasAiConfig([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    $raw = Get-Content -Encoding UTF8 $path -Raw
    if ($raw -match '(?m)^AI_MODEL=') { return $true }
    if ($raw -match '(?m)^AI_ACTIVE_PROFILE=') { return $true }
    if ($raw -match '(?m)^\[[\w.-]+\]\s*$') { return $true }
    return $false
}

function Resolve-EnvFilePath {
    $wsExists = Test-Path $EnvFile
    $coExists = Test-Path $ContinueEnvFile
    if ($wsExists -and -not $coExists) { return $EnvFile }
    if (-not $wsExists -and $coExists) { return $ContinueEnvFile }
    $wsHasAi = Env-HasAiConfig $EnvFile
    $coHasAi = Env-HasAiConfig $ContinueEnvFile
    if ($wsHasAi -and -not $coHasAi) { return $EnvFile }
    if ($coHasAi -and -not $wsHasAi) { return $ContinueEnvFile }
    $wsTime = (Get-Item $EnvFile).LastWriteTimeUtc
    $coTime = (Get-Item $ContinueEnvFile).LastWriteTimeUtc
    if ($wsTime -ge $coTime) { return $EnvFile }
    return $ContinueEnvFile
}

function New-ProfileFromVars([string]$id, $vars) {
    $provider = if ($vars['AI_PROVIDER']) { $vars['AI_PROVIDER'] } elseif ($vars['OPENAI_PROVIDER']) { $vars['OPENAI_PROVIDER'] } else { 'openai' }
    $baseUrl = if ($vars['AI_BASE_URL']) { $vars['AI_BASE_URL'] } elseif ($vars['OPENAI_BASE_URL']) { $vars['OPENAI_BASE_URL'] } else { 'https://api.openai.com/v1' }
    $apiKey = if ($vars['AI_API_KEY']) { $vars['AI_API_KEY'] } else { $vars['OPENAI_API_KEY'] }
    $model = if ($vars['AI_MODEL']) { $vars['AI_MODEL'] } elseif ($vars['OPENAI_MODEL']) { $vars['OPENAI_MODEL'] } else { 'gpt-4o' }
    return @{
        id = $id
        provider = $provider
        baseUrl = $baseUrl
        apiKey = $apiKey
        model = $model
    }
}

function Read-EnvProfiles([string]$path) {
    $profiles = New-Object System.Collections.Generic.List[hashtable]
    $activeProfileId = $null
    $sectionOrder = New-Object System.Collections.Generic.List[string]
    $sectionVars = @{}
    $topLevelAi = @{}
    $currentSection = $null
    $aiKeys = @('AI_PROVIDER','AI_BASE_URL','AI_API_KEY','AI_MODEL','AI_ACTIVE_PROFILE','OPENAI_PROVIDER','OPENAI_BASE_URL','OPENAI_API_KEY','OPENAI_MODEL')

    foreach ($line in Get-Content -Encoding UTF8 $path) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        if ($t -match '^\[([^\]]+)\]$') {
            $currentSection = $Matches[1].Trim()
            if ($currentSection -and -not $sectionVars.ContainsKey($currentSection)) {
                $sectionVars[$currentSection] = @{}
                $sectionOrder.Add($currentSection) | Out-Null
            }
            continue
        }
        $eq = $t.IndexOf('=')
        if ($eq -lt 0) { continue }
        $k = $t.Substring(0, $eq).Trim()
        $v = $t.Substring($eq + 1).Trim().Trim('"').Trim("'")
        if (-not $v -and $k -ne 'AI_API_KEY' -and $k -ne 'OPENAI_API_KEY') { continue }
        if ($null -eq $currentSection) {
            if ($k -eq 'AI_ACTIVE_PROFILE') { $activeProfileId = $v; continue }
            if ($aiKeys -contains $k) { $topLevelAi[$k] = $v }
            continue
        }
        $sectionVars[$currentSection][$k] = $v
    }

    if ($sectionOrder.Count -gt 0) {
        foreach ($id in $sectionOrder) {
            $vars = $sectionVars[$id]
            if ($vars['AI_MODEL'] -or $vars['OPENAI_MODEL'] -or $vars['AI_API_KEY'] -or $vars['OPENAI_API_KEY'] -or $vars['AI_PROVIDER'] -or $vars['OPENAI_PROVIDER']) {
                $profiles.Add((New-ProfileFromVars $id $vars)) | Out-Null
            }
        }
    }

    if ($profiles.Count -eq 0) {
        if ($topLevelAi['AI_MODEL'] -or $topLevelAi['OPENAI_MODEL'] -or $topLevelAi['AI_API_KEY'] -or $topLevelAi['OPENAI_API_KEY'] -or $topLevelAi['AI_PROVIDER'] -or $topLevelAi['OPENAI_PROVIDER']) {
            $profiles.Add((New-ProfileFromVars 'default' $topLevelAi)) | Out-Null
        }
    }

    if (-not $activeProfileId -or -not ($profiles | Where-Object { $_.id -eq $activeProfileId })) {
        $activeProfileId = if ($profiles.Count -gt 0) { $profiles[0].id } else { 'default' }
    }

    return @{
        activeProfileId = $activeProfileId
        profiles = $profiles
    }
}

function Write-CanonicalEnvFromSource([string]$sourcePath) {
    $content = Get-Content -Encoding UTF8 $sourcePath -Raw
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    # Preserve workspace .env as-is; only mirror to ~/.continue/.env
    New-Item -ItemType Directory -Force -Path $ContinueDir | Out-Null
    [System.IO.File]::WriteAllText($ContinueEnvFile, $content, $utf8NoBom)
    if ($sourcePath -ne $EnvFile -and (Test-Path $EnvFile)) {
        # Do not overwrite workspace .env when source is ~/.continue
        return
    }
}

function Upsert-ProfileModelBlock {
    param(
        [string]$Yaml,
        [string]$BlockName,
        [string]$Provider,
        [string]$Model,
        [string]$ApiBase,
        [string]$ApiKey
    )
    $yamlProvider = Provider-ForYaml $Provider
    $names = Get-ModelBlockNames $Yaml
    if ($names -contains $BlockName) {
        $Yaml = Repair-NamedModelBlock -Yaml $Yaml -BlockName $BlockName -Provider $yamlProvider -Model $Model -ApiBase $ApiBase -ApiKey $ApiKey
        return $Yaml
    }
    $useResponsesLine = ''
    if ($Provider -eq 'openai' -and -not (Is-OfficialOpenAiBase $ApiBase)) {
        $useResponsesLine = "`n    useResponsesApi: false"
    }
    $block = @"
  - name: $BlockName
    provider: $yamlProvider
    model: $Model
    apiBase: $ApiBase
    apiKey: "$ApiKey"$useResponsesLine
    roles:
      - chat
      - edit
      - apply
      - autocomplete
    capabilities:
      - tool_use
"@
    if ($Yaml -match '(?m)^context:') {
        return ($Yaml -replace '(?m)^context:', "$block`n`ncontext:")
    }
    if ($Yaml -match '(?m)^models:\s*$') {
        return ($Yaml -replace '(?m)^models:\s*$', "models:`n$block")
    }
    return ($Yaml.TrimEnd() + "`n`nmodels:`n$block`n")
}

function Normalize-Provider([string]$provider, [string]$baseUrl) {
    $base = $baseUrl.TrimEnd('/').ToLower()
    if ($base.Contains('siliconflow.cn') -or $base.Contains('silinex.work')) {
        return 'siliconflow'
    }
    $official = (Is-OfficialOpenAiBase $baseUrl) `
        -or (Is-OfficialAnthropicBase $baseUrl) `
        -or $base.Contains('generativelanguage.googleapis.com') `
        -or $base.Contains('api.x.ai')
    $openAiCompatible = @('openai','openrouter','deepseek','groq','mistral','ollama','xai','siliconflow')
    if (-not $official -and ($openAiCompatible -notcontains $provider)) {
        return 'openai'
    }
    return $provider
}

function Update-FirstModelBlock([string]$yaml, [string]$model, [string]$provider, [string]$baseUrl, [string]$apiKey) {
    $yamlProvider = Provider-ForYaml $provider
    $pattern = '(models:\s*\r?\n\s+- name: )([^\r\n]+)(\s*\r?\n\s+provider: )([^\r\n]+)(\s*\r?\n\s+model: )([^\r\n]+)(\s*\r?\n(?:\s+useResponsesApi: [^\r\n]+\r?\n)?\s+apiBase: )([^\r\n]+)(\s*\r?\n\s+apiKey: )([^\r\n]+)'
    if ($yaml -match $pattern) {
        return [regex]::Replace(
            $yaml,
            $pattern,
            "`${1}$model`${3}$yamlProvider`${5}$model`${7}$baseUrl`${9}`"$apiKey`"",
            1
        )
    }

    $lines = $yaml -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $inModels = $false
    $updatingFirstModel = $false
    $updatedFirstModel = $false
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($inModels) {
            if ($trimmed -and -not $trimmed.StartsWith('-') -and -not $trimmed.StartsWith('#') -and -not $line.StartsWith(' ') -and -not $line.StartsWith("`t")) {
                $inModels = $false
            }
        }
        if (-not $inModels) {
            if ($trimmed -eq 'models:' -or $trimmed.StartsWith('models:')) {
                $inModels = $true
            }
            $out.Add($line)
            continue
        }

        if ($updatingFirstModel -and $trimmed.StartsWith('- name:')) {
            $updatingFirstModel = $false
            $out.Add($line)
            continue
        }
        if (-not $updatingFirstModel -and -not $updatedFirstModel -and $trimmed.StartsWith('- name:')) {
            $out.Add(($line -replace '- name:\s*.+', "- name: $model"))
            $updatingFirstModel = $true
            $updatedFirstModel = $true
            continue
        }
        if ($updatingFirstModel) {
            if ($line -match '^\s+provider:\s*') {
                $out.Add(($line -replace 'provider:\s*.+', "provider: $yamlProvider"))
                continue
            }
            if ($line -match '^\s+model:\s*') {
                $out.Add(($line -replace 'model:\s*.+', "model: $model"))
                continue
            }
            if ($line -match '^\s+apiBase:\s*') {
                $out.Add(($line -replace 'apiBase:\s*.+', "apiBase: $baseUrl"))
                continue
            }
            if ($line -match '^\s+apiKey:\s*') {
                $out.Add(($line -replace 'apiKey:\s*.+', "apiKey: `"$apiKey`""))
                $updatingFirstModel = $false
                continue
            }
            if ($trimmed -and -not $trimmed.StartsWith('-') -and -not $line.StartsWith(' ') -and -not $line.StartsWith("`t")) {
                $inModels = $false
                $updatingFirstModel = $false
            }
        }
        $out.Add($line)
    }
    return ($out -join "`n")
}

function Remove-NamedModelBlock {
    param(
        [string]$Yaml,
        [string]$BlockName
    )

    $escapedName = [regex]::Escape($BlockName)
    $namePattern = "^\s*-\s+name:\s*$escapedName\s*$"
    $lines = $Yaml -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $inBlock = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($line -match $namePattern) {
            $inBlock = $true
            continue
        }
        if ($inBlock) {
            if ($trimmed.StartsWith('- name:')) {
                $inBlock = $false
                $out.Add($line)
                continue
            }
            if ($trimmed -and -not $trimmed.StartsWith('-') -and -not $line.StartsWith(' ') -and -not $line.StartsWith("`t")) {
                $inBlock = $false
                $out.Add($line)
                continue
            }
            continue
        }
        $out.Add($line)
    }

    return ($out -join "`n")
}

function Remove-RetiredLocalChatBlocks {
    param([string]$Yaml)

    foreach ($name in @(
        'Qwen3.5 2B (Local)',
        'Qwen3.5 4B (Local)',
        'Qwen3-VL 4B (Local)',
        'Qwen2.5-Coder 3B (Local)',
        'Qwen2.5-Coder-Tools 3B (Local)'
    )) {
        $Yaml = Remove-NamedModelBlock -Yaml $Yaml -BlockName $name
    }
    return ($Yaml -replace "`n{3,}", "`n`n")
}

function Repair-NamedModelBlock {
    param(
        [string]$Yaml,
        [string]$BlockName,
        [string]$Provider,
        [string]$Model,
        [string]$ApiBase,
        [string]$ApiKey = $null,
        [switch]$RemoveApiKey,
        [switch]$RemoveApiBase,
        [switch]$RemoveUseResponsesApi
    )

    $escapedName = [regex]::Escape($BlockName)
    $namePattern = "^\s*-\s+name:\s*$escapedName\s*$"
    $lines = $Yaml -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $inBlock = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($line -match $namePattern) {
            $inBlock = $true
            $out.Add($line)
            continue
        }
        if ($inBlock) {
            if ($trimmed.StartsWith('- name:')) {
                $inBlock = $false
                $out.Add($line)
                continue
            }
            if ($trimmed -and -not $trimmed.StartsWith('-') -and -not $line.StartsWith(' ') -and -not $line.StartsWith("`t")) {
                $inBlock = $false
                $out.Add($line)
                continue
            }
            if ($RemoveApiKey -and $line -match '^\s+apiKey:\s*') { continue }
            if ($RemoveUseResponsesApi -and $line -match '^\s+useResponsesApi:\s*') { continue }
            if ($RemoveApiBase -and $line -match '^\s+apiBase:\s*') { continue }
            if ($line -match '^\s+provider:\s*') {
                $out.Add(($line -replace 'provider:\s*.+', "provider: $Provider"))
                continue
            }
            if ($line -match '^\s+model:\s*') {
                $out.Add(($line -replace 'model:\s*.+', "model: $Model"))
                continue
            }
            if ($line -match '^\s+apiBase:\s*') {
                if (-not $ApiBase) { continue }
                $out.Add(($line -replace 'apiBase:\s*.+', "apiBase: $ApiBase"))
                continue
            }
            if ($ApiKey -and $line -match '^\s+apiKey:\s*') {
                $out.Add(($line -replace 'apiKey:\s*.+', "apiKey: `"$ApiKey`""))
                continue
            }
        }
        $out.Add($line)
    }
    return ($out -join "`n")
}

function Set-PrimaryModelSelection([string]$modelName) {
    $ctxPath = Join-Path $ContinueDir "index\globalContext.json"
    if (-not (Test-Path $ctxPath)) { return }
    $json = Get-Content -Encoding UTF8 $ctxPath -Raw
    # Clear retired local chat titles from stored selection.
    $json = $json -replace 'Qwen3\.5 [24]B \(Local\)', $modelName
    $json = $json -replace 'Qwen3-VL 4B \(Local\)', $modelName
    $json = $json -replace 'Qwen2\.5-Coder(?:-Tools)? 3B \(Local\)', $modelName
    if ($json -notmatch 'selectedModelsByProfileId') {
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($ctxPath, $json, $utf8NoBom)
        return
    }
    foreach ($role in @('chat', 'edit', 'apply', 'autocomplete')) {
        $pattern = "(`"$role`"\s*:\s*)`"[^`"]*`""
        $json = [regex]::Replace($json, $pattern, "`${1}`"$modelName`"", 1)
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($ctxPath, $json, $utf8NoBom)
}

function Clear-LocalChatModelSelection {
    $ctxPath = Join-Path $ContinueDir "index\globalContext.json"
    if (-not (Test-Path $ctxPath)) { return }
    $json = Get-Content -Encoding UTF8 $ctxPath -Raw
    $json = $json -replace '"chat"\s*:\s*"Qwen[^"]*\(Local\)"', '"chat": ""'
    $json = $json -replace '"edit"\s*:\s*"Qwen[^"]*\(Local\)"', '"edit": ""'
    $json = $json -replace '"apply"\s*:\s*"Qwen[^"]*\(Local\)"', '"apply": ""'
    $json = $json -replace '"autocomplete"\s*:\s*"Qwen[^"]*\(Local\)"', '"autocomplete": ""'
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($ctxPath, $json, $utf8NoBom)
}

function Repair-EmbedRoleModelBlock([string]$Yaml) {
    $lines = $Yaml -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $lines.Count) {
        $line = $lines[$i]
        if ($line -match '^\s*-\s+name:\s*') {
            $blockStart = $i
            $i++
            $rolesEmbed = $false
            while ($i -lt $lines.Count) {
                $inner = $lines[$i]
                $trimmed = $inner.Trim()
                if ($trimmed.StartsWith('- name:') -and $i -gt $blockStart) { break }
                if ($trimmed -and -not $trimmed.StartsWith('-') -and -not $inner.StartsWith(' ') -and -not $inner.StartsWith("`t")) { break }
                if ($inner -match '^\s+roles:\s*$') {
                    $next = if ($i + 1 -lt $lines.Count) { $lines[$i + 1].Trim() } else { '' }
                    if ($next -eq '- embed') { $rolesEmbed = $true }
                }
                $i++
            }
            if ($rolesEmbed) {
                $out.Add("  - name: local-embed")
                $out.Add("    provider: transformers.js")
                $out.Add("    model: all-MiniLM-L6-v2")
                $out.Add("    roles:")
                $out.Add("      - embed")
                $out.Add("")
                continue
            }
            for ($j = $blockStart; $j -lt $i; $j++) { $out.Add($lines[$j]) }
            continue
        }
        $out.Add($line)
        $i++
    }
    return ($out -join "`n")
}

function Ensure-OllamaEmbedBlock([string]$yaml) {
    if ($yaml -match '(?m)- name:\s*local-embed') {
        return Repair-NamedModelBlock `
            -Yaml $yaml `
            -BlockName 'local-embed' `
            -Provider 'transformers.js' `
            -Model 'all-MiniLM-L6-v2' `
            -RemoveApiKey `
            -RemoveApiBase `
            -RemoveUseResponsesApi
    }

    $repaired = Repair-EmbedRoleModelBlock $yaml
    if ($repaired -ne $yaml) { return $repaired }

    $embedBlock = @"

  - name: local-embed
    provider: transformers.js
    model: all-MiniLM-L6-v2
    roles:
      - embed
"@

    if ($yaml -match '(?m)^context:') {
        return ($yaml -replace '(?m)^context:', "$embedBlock`n`ncontext:")
    }
    return ($yaml + $embedBlock)
}

function Set-EmbedModelSelection {
    $ctxPath = Join-Path $ContinueDir "index\globalContext.json"
    if (-not (Test-Path $ctxPath)) { return }
    $json = Get-Content -Encoding UTF8 $ctxPath -Raw
    if ($json -notmatch '"embed"\s*:') { return }
    $json = [regex]::Replace($json, '"embed"\s*:\s*"[^"]*"', '"embed": "local-embed"')
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($ctxPath, $json, $utf8NoBom)
}

function Normalize-ModelsSection([string]$Yaml) {
    # Invalid YAML: `models: []` with list items below -- Continue cannot parse this.
    return ($Yaml -replace '(?m)^models:\s*\[\s*\]\s*$', 'models:')
}

function Get-ModelBlockNames([string]$Yaml) {
    $lines = $Yaml -split "`r?`n"
    $inModels = $false
    $names = @()
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if (-not $inModels) {
            if ($trimmed -eq 'models:' -or $trimmed.StartsWith('models:')) { $inModels = $true }
            continue
        }
        if ($trimmed -and -not $trimmed.StartsWith('-') -and -not $line.StartsWith(' ') -and -not $line.StartsWith("`t")) {
            break
        }
        if ($line -match '^\s+-\s+name:\s*(.+)$') {
            $names += $Matches[1].Trim()
        }
    }
    return ,$names
}

function Test-ConfigYamlBroken([string]$Yaml) {
    if ($Yaml -match '(?m)^models:\s*\[\s*\]\s*$') { return $true }
    $names = Get-ModelBlockNames $Yaml
    if ($names.Count -gt 0 -and ($names | Select-Object -Unique).Count -ne $names.Count) { return $true }
    # Detect mojibake corruption: the legitimate first line has only 1 non-ASCII
    # character (the em-dash in '# Mobius - Continue Configuration').
    # GBK-round-trip corruption produces many CJK characters in the first line.
    $firstLine = ($Yaml -split "`r?`n")[0]
    $nonAsciiCount = [regex]::Matches($firstLine, '[^\x00-\x7F]').Count
    if ($nonAsciiCount -gt 5) {
        return $true
    }
    return $false
}

function Remove-DuplicateModelBlocks([string]$Yaml) {
    $lines = $Yaml -split "`r?`n"
    $out = New-Object System.Collections.Generic.List[string]
    $inModels = $false
    $seenNames = @{}
    $skipBlock = $false

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ($inModels) {
            if ($trimmed -and -not $trimmed.StartsWith('-') -and -not $trimmed.StartsWith('#') -and -not $line.StartsWith(' ') -and -not $line.StartsWith("`t")) {
                $inModels = $false
            }
        }
        if (-not $inModels) {
            if ($trimmed -eq 'models:' -or $trimmed.StartsWith('models:')) { $inModels = $true }
            $out.Add($line)
            continue
        }

        if ($line -match '^\s+-\s+name:\s*(.+)$') {
            $blockName = $Matches[1].Trim()
            if ($seenNames.ContainsKey($blockName)) {
                $skipBlock = $true
                continue
            }
            $seenNames[$blockName] = $true
            $skipBlock = $false
            $out.Add($line)
            continue
        }

        if ($skipBlock) {
            if ($trimmed -and -not $trimmed.StartsWith('-') -and -not $line.StartsWith(' ') -and -not $line.StartsWith("`t")) {
                $inModels = $false
                $skipBlock = $false
                $out.Add($line)
            }
            continue
        }

        if ($trimmed -and -not $trimmed.StartsWith('-') -and -not $line.StartsWith(' ') -and -not $line.StartsWith("`t")) {
            $inModels = $false
        }
        $out.Add($line)
    }
    return ($out -join "`n")
}

function Apply-UseResponsesApi([string]$yaml, [string]$provider, [string]$baseUrl) {
    if ($provider -ne 'openai') {
        return ($yaml -replace '\r?\n    useResponsesApi: .+\r?\n', "`n")
    }
    if (Is-OfficialOpenAiBase $baseUrl) {
        return ($yaml -replace '\r?\n    useResponsesApi: .+\r?\n', "`n")
    }
    if ($yaml -notmatch 'useResponsesApi:') {
        return ($yaml -replace '(?m)^(\s+model: [^\r\n]+)', "`$1`n    useResponsesApi: false")
    }
    return ($yaml -replace 'useResponsesApi: .+', 'useResponsesApi: false')
}

$sourceEnvPath = Resolve-EnvFilePath
Write-Host "Syncing Continue config from $(Split-Path $sourceEnvPath -Leaf)..." -ForegroundColor Cyan
$parsed = Read-EnvProfiles $sourceEnvPath
$profiles = @($parsed.profiles)
$activeProfileId = $parsed.activeProfileId

if ($profiles.Count -eq 0) {
    Write-Host "No AI profiles in .env -- cloud chat model not synced; configure AI_ACTIVE_PROFILE + [profile] sections" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $ContinueDir | Out-Null
    if (Test-Path $ConfigFile) {
        $yaml = Get-Content -Encoding UTF8 $ConfigFile -Raw
    } elseif (Test-Path $TemplatePath) {
        $yaml = Get-Content -Encoding UTF8 $TemplatePath -Raw
    } else {
        return
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    $yaml = Remove-RetiredLocalChatBlocks -Yaml $yaml
    $yaml = Ensure-OllamaEmbedBlock $yaml
    [System.IO.File]::WriteAllText($ConfigFile, $yaml, $utf8NoBom)
    Set-EmbedModelSelection
    Clear-LocalChatModelSelection
    Write-Host "Stripped local chat models; ensured embed-only Ollama block in $ConfigFile" -ForegroundColor Cyan
    return
}

# Active profile first
$profiles = @($profiles | Sort-Object { if ($_.id -eq $activeProfileId) { 0 } else { 1 } })
$active = $profiles | Where-Object { $_.id -eq $activeProfileId } | Select-Object -First 1
if (-not $active) { $active = $profiles[0] }

$hasAnyKey = $false
foreach ($p in $profiles) {
    if ($p.apiKey) { $hasAnyKey = $true; break }
}
if (-not $hasAnyKey) {
    Write-Host "AI_API_KEY empty in all profiles -- cloud chat model not synced" -ForegroundColor Yellow
    return
}

New-Item -ItemType Directory -Force -Path $ContinueDir | Out-Null

if (Test-Path $ConfigFile) {
    $yaml = Get-Content -Encoding UTF8 $ConfigFile -Raw
    $yaml = Normalize-ModelsSection $yaml
    if ((Test-ConfigYamlBroken $yaml) -and (Test-Path $TemplatePath)) {
        Write-Host "Repairing broken ~/.continue/config.yaml from config/continue-config.yaml + .env" -ForegroundColor Yellow
        $yaml = Get-Content -Encoding UTF8 $TemplatePath -Raw
        $yaml = $yaml -replace '<YOUR_OPENAI_API_KEY>', $active.apiKey
    }
    $yaml = Remove-DuplicateModelBlocks $yaml
} elseif (Test-Path $TemplatePath) {
    $yaml = Get-Content -Encoding UTF8 $TemplatePath -Raw
    $yaml = $yaml -replace '<YOUR_OPENAI_API_KEY>', $active.apiKey
} else {
    $yaml = @"
name: Mobius
version: 1.0.0
schema: v1

models:

context:
  - provider: code
  - provider: docs
  - provider: diff
  - provider: terminal
  - provider: problems
  - provider: folder
  - provider: codebase

rules:
  - alwaysApply: true
    rule: |
      Act autonomously like Cursor Agent: use tools, do not ask clarifying questions, implement directly.
"@
}

foreach ($p in $profiles) {
    if (-not $p.apiKey) { continue }
    $provider = Normalize-Provider $p.provider $p.baseUrl
    if ($provider -eq 'ollama') { continue }
    $blockName = $p.id
    # Drop legacy bare model name and old profileId/model titles for this profile
    $yaml = Remove-NamedModelBlock -Yaml $yaml -BlockName $p.model
    $yaml = Remove-NamedModelBlock -Yaml $yaml -BlockName "$($p.id)/$($p.model)"
    $yaml = Upsert-ProfileModelBlock -Yaml $yaml -BlockName $blockName -Provider $provider -Model $p.model -ApiBase $p.baseUrl -ApiKey $p.apiKey
}

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$yaml = Normalize-ModelsSection $yaml
$yaml = Remove-DuplicateModelBlocks $yaml
$yaml = Remove-RetiredLocalChatBlocks -Yaml $yaml
$selectionModel = $active.id
$yaml = Ensure-OllamaEmbedBlock $yaml
if ($yaml -notmatch '(?m)- name:\s*local-embed') {
    $embedBlock = @"

  - name: local-embed
    provider: transformers.js
    model: all-MiniLM-L6-v2
    roles:
      - embed
"@
    if ($yaml -match '(?m)^context:') {
        $yaml = $yaml -replace '(?m)^context:', "$embedBlock`n`ncontext:"
    } else {
        $yaml = $yaml + $embedBlock
    }
}
[System.IO.File]::WriteAllText($ConfigFile, $yaml, $utf8NoBom)
Write-CanonicalEnvFromSource $sourceEnvPath
Set-EmbedModelSelection
Set-PrimaryModelSelection $selectionModel
Write-Host "Synced $($profiles.Count) profile(s); default '$selectionModel' from $(Split-Path $sourceEnvPath -Leaf) -> $ConfigFile" -ForegroundColor Green
Write-Host "In-process embed: local-embed (transformers.js all-MiniLM-L6-v2)" -ForegroundColor Cyan
Write-Host "Ollama OCR: glm-ocr (Agents image preprocess only)" -ForegroundColor Cyan