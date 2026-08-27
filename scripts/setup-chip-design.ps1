# Set up the Mobius chip-design toolchain (custom-fpga-mcp + FPGA flow).
#
# What this owns:
#   * chip-design/.venv with fastmcp + pyserial  -- the MCP server runs from here
#   * vendored upstream sources under vendor/    -- shallow submodule checkout
#   * chip-design/.toolchain.json                -- resolved tool paths, read by
#                                                   custom_fpga_mcp/config.py
#
# What it deliberately does NOT do:
#   * pull the F4PGA Docker image (several GB -- ask for it with -PullImage)
#   * install Docker Desktop (the daemon is a host product)
#
# Verilator + Yosys + openFPGALoader come from YosysHQ OSS CAD Suite (~570 MB),
# downloaded into tools/oss-cad-suite the same way Godot lands in tools/godot/.
# Skip that with -SkipCadSuite.
#
# nextpnr-xilinx (Windows has no F4PGA native package) comes from FPGAwars
# openXC7 (~650 MB) into tools/openxc7/. Skip that with -SkipOpenXc7.
# Verilator --build needs GNU make + g++ from w64devkit (~60 MB download)
# into tools/mingw/. Skip that with -SkipMingw.
# Docker F4PGA is an optional fallback only.
#
# Usage:
#   .\scripts\setup-chip-design.ps1                 # venv + core submodules + CAD suite + openXC7 + MinGW
#   .\scripts\setup-chip-design.ps1 -Detect         # detect only, change nothing
#   .\scripts\setup-chip-design.ps1 -SkipCadSuite   # skip the ~570 MB Verilator download
#   .\scripts\setup-chip-design.ps1 -SkipOpenXc7    # skip the ~650 MB nextpnr-xilinx download
#   .\scripts\setup-chip-design.ps1 -SkipMingw      # skip the portable make/g++ download
#   .\scripts\setup-chip-design.ps1 -PullImage      # also pull the F4PGA image (optional fallback)
#   .\scripts\setup-chip-design.ps1 -WithLitex      # also install LiteX (heavy)
#   .\scripts\setup-chip-design.ps1 -Tier all       # also init f4pga-examples + openFPGALoader
#   .\scripts\setup-chip-design.ps1 -SerialPort COM7
param(
    [switch]$Detect,
    [switch]$SkipCadSuite,
    [switch]$SkipOpenXc7,
    [switch]$SkipMingw,
    [switch]$PullImage,
    [switch]$WithLitex,
    [switch]$Force,
    [ValidateSet("core", "all")]
    [string]$Tier = "core",
    [string]$SerialPort
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ChipDir = Join-Path $Root "chip-design"
$VenvDir = Join-Path $ChipDir ".venv"
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"
$Requirements = Join-Path $ChipDir "requirements.txt"
$StateFile = Join-Path $ChipDir ".toolchain.json"
$McpParent = Join-Path $ChipDir "mcp"
$F4pgaImage = if ($env:F4PGA_IMAGE) { $env:F4PGA_IMAGE } else { "ghcr.io/chipsalliance/f4pga:latest" }

# Core submodules are needed for the flow to work at all. hotspot is research-only
# and llama.cpp/verilator/openFPGALoader are huge, so those stay opt-in via
# `git submodule update --init vendor/<name>`.
$CoreSubmodules = @(
    "vendor/fastmcp",
    "vendor/mcp-python-sdk",
    "vendor/pyserial",
    "vendor/f4pga",
    "vendor/litex",
    "vendor/litex-boards",
    "vendor/trng",
    "vendor/scsynth"
)
$OptionalSubmodules = @(
    "vendor/f4pga-examples",
    "vendor/openFPGALoader",
    "vendor/hotspot"
)

function Write-Step([string]$text) { Write-Host "==> $text" -ForegroundColor Cyan }
function Write-Ok([string]$text) { Write-Host "    OK   $text" -ForegroundColor Green }
function Write-Warn2([string]$text) { Write-Host "    WARN $text" -ForegroundColor Yellow }
function Write-Info([string]$text) { Write-Host "         $text" -ForegroundColor DarkGray }

function Find-Tool([string]$name) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $bins = @(
        (Join-Path $Root "tools\mingw\bin"),
        (Join-Path $Root "tools\openxc7\bin"),
        (Join-Path $Root "tools\oss-cad-suite\bin")
    )
    $cands = switch ($name) {
        "verilator" { @("verilator_bin.exe", "verilator.exe", "verilator") }
        "openFPGALoader" { @("openFPGALoader.exe", "openFPGALoader") }
        "yosys" { @("yosys.exe", "yosys") }
        "nextpnr-xilinx" { @("nextpnr-xilinx.exe", "nextpnr-xilinx") }
        "xc7frames2bit" { @("xc7frames2bit.exe", "xc7frames2bit") }
        "g++" { @("g++.exe", "g++") }
        "make" { @("make.exe", "mingw32-make.exe", "make") }
        default { @($name) }
    }
    foreach ($bin in $bins) {
        foreach ($c in $cands) {
            $p = Join-Path $bin $c
            if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
        }
    }
    return $null
}

function Find-HostPython {
    # 3.10+ is the floor: fastmcp needs modern typing and we use `X | None`.
    foreach ($candidate in @("python", "python3")) {
        $exe = Find-Tool $candidate
        if (-not $exe) { continue }
        $version = & $exe -c "import sys; print('%d.%d' % sys.version_info[:2])" 2>$null
        if ($LASTEXITCODE -eq 0 -and $version) {
            $parts = $version.Trim().Split('.')
            if ([int]$parts[0] -eq 3 -and [int]$parts[1] -ge 10) { return $exe }
            Write-Warn2 "$exe is Python $version; 3.10+ required"
        }
    }
    # The py launcher can reach an interpreter that is not on PATH.
    $py = Find-Tool "py"
    if ($py) {
        $exe = & $py -3 -c "import sys; print(sys.executable)" 2>$null
        if ($LASTEXITCODE -eq 0 -and $exe) { return $exe.Trim() }
    }
    return $null
}

Write-Host ""
Write-Host "Mobius chip-design setup" -ForegroundColor White
Write-Host "Repo: $Root" -ForegroundColor DarkGray
Write-Host ""

# ---------------------------------------------------------------------------
# Submodules
# ---------------------------------------------------------------------------
if (-not $Detect) {
    Write-Step "Vendored upstream sources"
    $git = Find-Tool "git"
    if (-not $git) {
        Write-Warn2 "git not found; cannot initialise submodules"
    }
    else {
        Push-Location $Root
        try {
            $toInit = @($CoreSubmodules)
            if ($Tier -eq "all") { $toInit += $OptionalSubmodules }
            # --checkout overrides `update = none` on the optional tier (without
            # it git prints "Skipping submodule" and never clones them).
            # --depth 1 keeps this to a few hundred MB instead of several GB.
            #
            # Git writes progress to stderr. With $ErrorActionPreference=Stop,
            # piping 2>&1 turns those lines into terminating ErrorRecords, so
            # drop Stop for this one native call.
            $oldEap = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                & $git submodule update --init --checkout --depth 1 -- @toInit 2>&1 |
                    ForEach-Object { Write-Info "$_" }
                $gitExit = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $oldEap
            }
            if ($gitExit -ne 0) {
                Write-Warn2 "submodule update returned $gitExit - re-run manually if the flow misbehaves"
            }
            else {
                Write-Ok "$($toInit.Count) submodules checked out (tier=$Tier)"
            }
        }
        finally { Pop-Location }
    }
}

# ---------------------------------------------------------------------------
# OSS CAD Suite (Verilator + g++ + usually openFPGALoader)
# ---------------------------------------------------------------------------
if (-not $Detect -and -not $SkipCadSuite) {
    Write-Step "OSS CAD Suite (bundled Verilator)"
    $cadSetup = Join-Path $PSScriptRoot "setup-oss-cad-suite.ps1"
    if (Test-Path -LiteralPath $cadSetup) {
        & $cadSetup
        if ($LASTEXITCODE -ne 0) {
            Write-Warn2 "OSS CAD Suite install failed (exit $LASTEXITCODE); lint/sim stay unavailable until npm run chip:cad-suite"
        }
        else {
            Write-Ok "tools\oss-cad-suite ready"
        }
    }
    else {
        Write-Warn2 "missing scripts/setup-oss-cad-suite.ps1"
    }
}

# ---------------------------------------------------------------------------
# openXC7 (nextpnr-xilinx + prjxray on Windows)
# ---------------------------------------------------------------------------
if (-not $Detect -and -not $SkipOpenXc7) {
    Write-Step "openXC7 (bundled nextpnr-xilinx)"
    $xc7Setup = Join-Path $PSScriptRoot "setup-openxc7.ps1"
    if (Test-Path -LiteralPath $xc7Setup) {
        & $xc7Setup
        if ($LASTEXITCODE -ne 0) {
            Write-Warn2 "openXC7 install failed (exit $LASTEXITCODE); native synth stays unavailable until npm run chip:openxc7"
        }
        else {
            Write-Ok "tools\openxc7 ready"
        }
    }
    else {
        Write-Warn2 "missing scripts/setup-openxc7.ps1"
    }
}

# ---------------------------------------------------------------------------
# MinGW (GNU make + g++ for Verilator --build)
# ---------------------------------------------------------------------------
if (-not $Detect -and -not $SkipMingw) {
    Write-Step "MinGW (bundled make + g++)"
    $mingwSetup = Join-Path $PSScriptRoot "setup-mingw.ps1"
    if (Test-Path -LiteralPath $mingwSetup) {
        & $mingwSetup
        if ($LASTEXITCODE -ne 0) {
            Write-Warn2 "MinGW install failed (exit $LASTEXITCODE); fpga_simulate --build stays unavailable until npm run chip:mingw"
        }
        else {
            Write-Ok "tools\mingw ready"
        }
    }
    else {
        Write-Warn2 "missing scripts/setup-mingw.ps1"
    }
}

# ---------------------------------------------------------------------------
# Python venv
# ---------------------------------------------------------------------------
if (-not $Detect) {
    Write-Step "Python environment"
    if ($Force -and (Test-Path -LiteralPath $VenvDir)) {
        Write-Info "removing existing venv (-Force)"
        Remove-Item -LiteralPath $VenvDir -Recurse -Force
    }

    if (-not (Test-Path -LiteralPath $VenvPython)) {
        $hostPython = Find-HostPython
        if (-not $hostPython) {
            Write-Warn2 "No Python 3.10+ found. Install it from python.org or the Store, then re-run."
        }
        else {
            Write-Info "creating venv with $hostPython"
            & $hostPython -m venv $VenvDir
            if ($LASTEXITCODE -ne 0) { throw "venv creation failed (exit $LASTEXITCODE)" }
        }
    }

    if (Test-Path -LiteralPath $VenvPython) {
        Write-Info "installing $Requirements"
        & $VenvPython -m pip install --upgrade pip --quiet 2>&1 | ForEach-Object { Write-Info $_ }
        & $VenvPython -m pip install -r $Requirements --quiet 2>&1 | ForEach-Object { Write-Info $_ }
        if ($LASTEXITCODE -ne 0) { throw "pip install failed (exit $LASTEXITCODE)" }

        & $VenvPython -c "import fastmcp, serial" 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $ver = (& $VenvPython -c "import fastmcp; print(fastmcp.__version__)" 2>$null)
            Write-Ok "fastmcp $ver + pyserial importable from $VenvPython"
        }
        else {
            Write-Warn2 "venv built but fastmcp/pyserial did not import; try -Force"
        }

        if ($WithLitex) {
            # Editable installs from vendor/ so the SoC flow uses the pinned commits.
            Write-Info "installing LiteX (this takes a while)"
            & $VenvPython -m pip install -e (Join-Path $Root "vendor\litex") -e (Join-Path $Root "vendor\litex-boards") --quiet 2>&1 |
                ForEach-Object { Write-Info $_ }
            if ($LASTEXITCODE -eq 0) { Write-Ok "LiteX + litex-boards installed (editable)" }
            else { Write-Warn2 "LiteX install failed; the standalone flow still works" }
        }
    }
}

# ---------------------------------------------------------------------------
# Host tools
# ---------------------------------------------------------------------------
Write-Step "Host tools"

$docker = Find-Tool "docker"
if ($docker) {
    $serverVersion = & $docker version --format "{{.Server.Version}}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $serverVersion) {
        Write-Ok "docker $($serverVersion.Trim()) (daemon reachable)"
    }
    else {
        # A stopped daemon needs a completely different fix from a missing CLI.
        Write-Warn2 "docker CLI found but the daemon is not responding - start Docker Desktop"
    }
}
else {
    Write-Warn2 "docker not found - optional (native openXC7 is the Windows synth path)"
    Write-Info "preferred: npm run chip:openxc7   fallback: Docker Desktop"
}

$loader = Find-Tool "openFPGALoader"
if ($loader) { Write-Ok "openFPGALoader: $loader" }
else {
    Write-Warn2 "openFPGALoader not found - required to flash the Arty A7"
    Write-Info "npm run chip:cad-suite bundles it with Verilator, or install a host binary."
    Write-Info "USB/JTAG passthrough does not work in Docker Desktop."
}

$verilator = Find-Tool "verilator"
if ($verilator) { Write-Ok "verilator: $verilator" }
else {
    Write-Warn2 "verilator not found - needed for fpga_lint / fpga_simulate"
    Write-Info "Run: npm run chip:cad-suite   (downloads YosysHQ OSS CAD Suite into tools/oss-cad-suite)"
}

$gxx = Find-Tool "g++"
$make = Find-Tool "make"
if ($gxx -and $make) {
    Write-Ok "g++: $gxx"
    Write-Ok "make: $make"
}
else {
    Write-Warn2 "make/g++ not found - needed for fpga_simulate --build"
    Write-Info "Run: npm run chip:mingw   (downloads w64devkit into tools/mingw)"
}

$yosys = Find-Tool "yosys"
if ($yosys) { Write-Ok "yosys: $yosys" }
else {
    Write-Warn2 "yosys not found - needed for native fpga_synthesize"
    Write-Info "Run: npm run chip:cad-suite"
}

$pnr = Find-Tool "nextpnr-xilinx"
if ($pnr) { Write-Ok "nextpnr-xilinx: $pnr" }
else {
    Write-Warn2 "nextpnr-xilinx not found - needed for native fpga_synthesize (no Docker)"
    Write-Info "Run: npm run chip:openxc7   (FPGAwars openXC7 into tools/openxc7)"
}

if ($PullImage) {
    if ($docker) {
        Write-Step "F4PGA image"
        Write-Info "pulling $F4pgaImage (several GB)"
        & $docker pull $F4pgaImage 2>&1 | ForEach-Object { Write-Info $_ }
        if ($LASTEXITCODE -eq 0) { Write-Ok "$F4pgaImage pulled" }
        else { Write-Warn2 "pull failed (exit $LASTEXITCODE)" }
    }
    else {
        Write-Warn2 "-PullImage needs a working docker CLI"
    }
}

# ---------------------------------------------------------------------------
# Toolchain state
# ---------------------------------------------------------------------------
# -Detect promises to change nothing, and a serial port passed on the command
# line is a deliberate write even in detect mode.
if (-not $Detect -or $SerialPort) {
    Write-Step "Recording resolved paths"

    $state = [ordered]@{}
    if ($docker) { $state["docker"] = $docker }
    if ($loader) { $state["openFPGALoader"] = $loader }
    if ($verilator) { $state["verilator"] = $verilator }
    if ($yosys) { $state["yosys"] = $yosys }
    if ($pnr) { $state["nextpnr-xilinx"] = $pnr }
    if (Test-Path -LiteralPath $VenvPython) { $state["python"] = $VenvPython }
    if ($SerialPort) { $state["serial_port"] = $SerialPort }
    $state["f4pga_image"] = $F4pgaImage
    $state["updated"] = (Get-Date).ToString("o")

    # UTF-8 without BOM and written via .NET so the cp936 console codepage cannot
    # corrupt paths containing non-ASCII characters.
    $json = $state | ConvertTo-Json -Depth 4
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($StateFile, $json, $utf8NoBom)
    Write-Ok "wrote $StateFile"
}

# ---------------------------------------------------------------------------
# Verify through the server's own probe
# ---------------------------------------------------------------------------
Write-Step "Toolchain report (from custom_fpga_mcp)"

$reportPython = if (Test-Path -LiteralPath $VenvPython) { $VenvPython } else { Find-HostPython }
if ($reportPython) {
    # The detect path is stdlib-only, so it works even when the venv is broken --
    # which is exactly when you need it.
    $env:PYTHONPATH = $McpParent
    $env:PYTHONIOENCODING = "utf-8"
    & $reportPython -m custom_fpga_mcp setup 2>&1 | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
    Remove-Item Env:\PYTHONPATH -ErrorAction SilentlyContinue
}
else {
    Write-Warn2 "no interpreter available to run the report"
}

Write-Host ""
Write-Host "Next steps" -ForegroundColor White
Write-Host "  1. Reload the IDE window so it re-spawns the custom-fpga MCP server." -ForegroundColor Gray
Write-Host "  2. Switch the agent to Chip mode and ask it to run fpga_detect." -ForegroundColor Gray
Write-Host "  3. No board? fpga_lint / fpga_simulate need Verilator (npm run chip:cad-suite)." -ForegroundColor Gray
Write-Host "  4. Synthesis on Windows: npm run chip:openxc7 (no Docker)." -ForegroundColor Gray
Write-Host ""
