function Resolve-NodeDirectory {
    param([string]$PreferredDir)

    if ($PreferredDir -and (Test-Path (Join-Path $PreferredDir "node.exe"))) {
        return $PreferredDir
    }

    $cmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($cmd -and $cmd.Source -and (Test-Path $cmd.Source)) {
        return (Split-Path -Parent $cmd.Source)
    }

    foreach ($candidate in @(
            $env:NVM_SYMLINK,
            (Join-Path $env:ProgramFiles "nodejs"),
            "D:\nodejs",
            (Join-Path ${env:ProgramFiles(x86)} "nodejs")
        )) {
        if ($candidate -and (Test-Path (Join-Path $candidate "node.exe"))) {
            return $candidate
        }
    }

    return $null
}

function Ensure-NodeOnPath {
    param([string]$PreferredDir)

    $nodeDir = Resolve-NodeDirectory -PreferredDir $PreferredDir
    if (-not $nodeDir) {
        return $false
    }

    if ($env:PATH -notlike "*$nodeDir*") {
        $env:PATH = "$nodeDir;$env:PATH"
    }

    return [bool](Get-Command node.exe -ErrorAction SilentlyContinue)
}

function Import-VsDevEnvironment {
    $nodeDirBefore = $null
    $nodeCmd = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($nodeCmd -and $nodeCmd.Source) {
        $nodeDirBefore = Split-Path -Parent $nodeCmd.Source
    }

    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vsWhere)) { return $false }

    $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null
    if (-not $vsPath) {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Workload.VCTools -property installationPath 2>$null
    }
    if (-not $vsPath) { return $false }

    $vcvars = Join-Path $vsPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) { return $false }

    cmd /c "`"$vcvars`" >nul && set" | ForEach-Object {
        if ($_ -match '^(.*?)=(.*)$') {
            Set-Item -Path "env:$($matches[1])" -Value $matches[2]
        }
    }
    # vcvars replaces PATH and often drops Node -- put it back
    Ensure-NodeOnPath -PreferredDir $nodeDirBefore | Out-Null
    Add-SignToolToPath
    return $true
}

function Add-SignToolToPath {
    if (Get-Command signtool.exe -ErrorAction SilentlyContinue) { return $true }

    $windowsSdkBin = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (Test-Path $windowsSdkBin) {
        $signTool = Get-ChildItem $windowsSdkBin -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($signTool) {
            $sdkDir = Split-Path $signTool.FullName -Parent
            $env:PATH = "$sdkDir;$env:PATH"
            return $true
        }
    }

    $fallbackDir = "${env:ProgramFiles(x86)}\Microsoft SDKs\ClickOnce\SignTool"
    $fallback = Join-Path $fallbackDir "signtool.exe"
    if (Test-Path $fallback) {
        $env:PATH = "$fallbackDir;$env:PATH"
        return $true
    }

    return $false
}

function Ensure-BuildSourceVersion {
    param(
        [string]$RepoDir
    )

    if ($env:BUILD_SOURCEVERSION -and $env:BUILD_SOURCEVERSION -match '^[0-9a-f]{40}$') {
        return $env:BUILD_SOURCEVERSION
    }

    if (-not $RepoDir) {
        $RepoDir = Join-Path (Split-Path -Parent $PSScriptRoot) "vscode"
    }

    $commit = & git -C $RepoDir rev-parse HEAD 2>$null
    if (-not $commit -or $commit -notmatch '^[0-9a-f]{40}$') {
        throw "Unable to resolve git commit for BUILD_SOURCEVERSION (repo: $RepoDir)"
    }

    $env:BUILD_SOURCEVERSION = $commit.Trim()
    Write-Host "BUILD_SOURCEVERSION=$($env:BUILD_SOURCEVERSION)" -ForegroundColor Gray
    return $env:BUILD_SOURCEVERSION
}
