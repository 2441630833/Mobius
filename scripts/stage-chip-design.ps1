# Stage the chip-design payload (custom-fpga-mcp + RTL + SoC) into the packaged client tree.
#
# The installed IDE has no git checkout, so the launcher's walk-up search for the
# Mobius root would find nothing and Chip mode would arrive with no tools. The fix
# is to ship a self-contained, Mobius-SHAPED payload:
#
#   <install>/resources/mobius-chip/
#       package.json          <- marker: {"name":"Mobius"}
#       chip-design/          <- rtl, sim, soc, constraints, mcp, tests
#       scripts/              <- fpga-mcp-launcher/-fallback/-resolve/-cli
#       .continue/            <- rule + MCP registration
#
# Because the layout mirrors the repo, scripts/fpga-mcp-resolve.js resolves it with
# the code path it already uses in a checkout: the staged launcher sits in
# <payload>/scripts, so walking up one level lands on a directory containing
# chip-design/mcp/custom_fpga_mcp. No installed-only branch to keep in sync.
#
# Deliberately NOT staged:
#   * chip-design/.venv       — platform- and path-specific; `npm run chip:setup`
#                               builds it where the user actually runs it.
#   * chip-design/build       — bitstreams are per-board build artefacts.
#   * vendor/                 — reference sources, multi-GB with the optional tier.
#                               Pass -IncludeVendorRtl to ship just the two small
#                               RTL references (trng, scsynth).
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("x64", "arm64")]
    [string]$Arch,

    [switch]$IncludeVendorRtl,

    [switch]$Force
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
$ClientDir = Join-Path (Split-Path -Parent (Join-Path $Root "vscode")) "VSCode-win32-$Arch"
$SourceChip = Join-Path $Root "chip-design"
$Payload = Join-Path $ClientDir "resources\mobius-chip"

# Small RTL references worth shipping: they are what the agent reads when asked
# "how does a real TRNG core do this?". Everything else in vendor/ is a toolchain.
$VendorRtl = @("trng", "scsynth")

function Write-Info { param([string]$m) Write-Host "       $m" -ForegroundColor Gray }

Write-Host "`n=== Stage Chip Design ($Arch client) ===" -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $SourceChip)) {
    Write-Host "[FAIL] Missing source tree: $SourceChip" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $ClientDir)) {
    Write-Host "[FAIL] Client build output not found: $ClientDir" -ForegroundColor Red
    Write-Info "Run gulp vscode-win32-$Arch-min-ci first."
    exit 1
}

if ($env:SKIP_CHIP_STAGE -eq "1" -and -not $Force) {
    Write-Host "[SKIP] SKIP_CHIP_STAGE=1" -ForegroundColor Yellow
    exit 0
}

Write-Host "Client : $ClientDir" -ForegroundColor Gray
Write-Host "Payload: $Payload" -ForegroundColor Gray

if (Test-Path -LiteralPath $Payload) {
    Remove-Item -LiteralPath $Payload -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $Payload | Out-Null

# ---------------------------------------------------------------------------
# chip-design/ minus the build/venv artefacts
# ---------------------------------------------------------------------------
$destChip = Join-Path $Payload "chip-design"
New-Item -ItemType Directory -Force -Path $destChip | Out-Null

$chipDirs = @("rtl", "sim", "soc", "constraints", "mcp", "tests")
foreach ($name in $chipDirs) {
    $src = Join-Path $SourceChip $name
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "[FAIL] Missing $src" -ForegroundColor Red
        exit 1
    }
    Copy-Item -LiteralPath $src -Destination (Join-Path $destChip $name) -Recurse -Force
}

# __pycache__ from a dev run would otherwise ship stale bytecode compiled against
# a different interpreter version.
Get-ChildItem -LiteralPath $destChip -Recurse -Directory -Filter "__pycache__" -ErrorAction SilentlyContinue |
    Sort-Object -Property FullName -Descending |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }

foreach ($name in @("requirements.txt", "README.md")) {
    $src = Join-Path $SourceChip $name
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $destChip $name) -Force
    }
}

Write-Host "[ OK ] chip-design ($($chipDirs -join ', '))" -ForegroundColor Green

# ---------------------------------------------------------------------------
# scripts/ — only what the launcher chain needs
# ---------------------------------------------------------------------------
$destScripts = Join-Path $Payload "scripts"
New-Item -ItemType Directory -Force -Path $destScripts | Out-Null

$scriptFiles = @(
    "fpga-mcp-launcher.js",
    "fpga-mcp-fallback.js",
    "fpga-mcp-resolve.js",
    "fpga-cli.js",
    "setup-chip-design.ps1",
    "setup-oss-cad-suite.ps1",
    "setup-openxc7.ps1",
    "setup-mingw.ps1"
)
foreach ($name in $scriptFiles) {
    $src = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $src)) {
        Write-Host "[FAIL] Missing $src" -ForegroundColor Red
        exit 1
    }
    Copy-Item -LiteralPath $src -Destination (Join-Path $destScripts $name) -Force
}
Write-Host "[ OK ] scripts ($($scriptFiles.Count) files)" -ForegroundColor Green

# Pin file the CAD-suite installer reads (parent of scripts/ = payload root)
$destConfig = Join-Path $Payload "config"
New-Item -ItemType Directory -Force -Path $destConfig | Out-Null
$versionPin = Join-Path $Root "config\oss-cad-suite.version"
if (Test-Path -LiteralPath $versionPin) {
    Copy-Item -LiteralPath $versionPin -Destination (Join-Path $destConfig "oss-cad-suite.version") -Force
    Write-Host "[ OK ] config/oss-cad-suite.version" -ForegroundColor Green
}
$xc7Pin = Join-Path $Root "config\openxc7.version"
if (Test-Path -LiteralPath $xc7Pin) {
    Copy-Item -LiteralPath $xc7Pin -Destination (Join-Path $destConfig "openxc7.version") -Force
    Write-Host "[ OK ] config/openxc7.version" -ForegroundColor Green
}
$mingwPin = Join-Path $Root "config\mingw.version"
if (Test-Path -LiteralPath $mingwPin) {
    Copy-Item -LiteralPath $mingwPin -Destination (Join-Path $destConfig "mingw.version") -Force
    Write-Host "[ OK ] config/mingw.version" -ForegroundColor Green
}
$mingwPkgs = Join-Path $Root "config\mingw.packages"
if (Test-Path -LiteralPath $mingwPkgs) {
    Copy-Item -LiteralPath $mingwPkgs -Destination (Join-Path $destConfig "mingw.packages") -Force
    Write-Host "[ OK ] config/mingw.packages" -ForegroundColor Green
}

# Ship the downloaded YosysHQ suite when present so Chip lint/sim work offline.
# SKIP_CAD_SUITE_STAGE=1 keeps the installer small if the suite was only for local use.
$srcSuite = Join-Path $Root "tools\oss-cad-suite"
$destSuite = Join-Path $Payload "tools\oss-cad-suite"
if ($env:SKIP_CAD_SUITE_STAGE -eq "1") {
    Write-Host "[SKIP] SKIP_CAD_SUITE_STAGE=1 (not copying tools/oss-cad-suite)" -ForegroundColor Yellow
}
elseif (Test-Path -LiteralPath (Join-Path $srcSuite "bin")) {
    Write-Host "Copying tools/oss-cad-suite (Verilator bundle, hundreds of MB) ..." -ForegroundColor Gray
    New-Item -ItemType Directory -Force -Path (Join-Path $Payload "tools") | Out-Null
    robocopy $srcSuite $destSuite /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed for tools/oss-cad-suite (exit $LASTEXITCODE)" }
    $global:LASTEXITCODE = 0
    Write-Host "[ OK ] tools/oss-cad-suite" -ForegroundColor Green
}
else {
    Write-Host "[INFO] tools/oss-cad-suite not present; users run npm run chip:cad-suite after install" -ForegroundColor DarkGray
}

$srcOpenXc7 = Join-Path $Root "tools\openxc7"
$destOpenXc7 = Join-Path $Payload "tools\openxc7"
if ($env:SKIP_OPENXC7_STAGE -eq "1") {
    Write-Host "[SKIP] SKIP_OPENXC7_STAGE=1 (not copying tools/openxc7)" -ForegroundColor Yellow
}
elseif (Test-Path -LiteralPath (Join-Path $srcOpenXc7 "bin")) {
    Write-Host "Copying tools/openxc7 (nextpnr-xilinx bundle, hundreds of MB) ..." -ForegroundColor Gray
    New-Item -ItemType Directory -Force -Path (Join-Path $Payload "tools") | Out-Null
    robocopy $srcOpenXc7 $destOpenXc7 /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed for tools/openxc7 (exit $LASTEXITCODE)" }
    $global:LASTEXITCODE = 0
    Write-Host "[ OK ] tools/openxc7" -ForegroundColor Green
}
else {
    Write-Host "[INFO] tools/openxc7 not present; users run npm run chip:openxc7 after install" -ForegroundColor DarkGray
}

$srcMingw = Join-Path $Root "tools\mingw"
$destMingw = Join-Path $Payload "tools\mingw"
if ($env:SKIP_MINGW_STAGE -eq "1") {
    Write-Host "[SKIP] SKIP_MINGW_STAGE=1 (not copying tools/mingw)" -ForegroundColor Yellow
}
elseif (Test-Path -LiteralPath (Join-Path $srcMingw "bin")) {
    Write-Host "Copying tools/mingw (portable make + g++) ..." -ForegroundColor Gray
    New-Item -ItemType Directory -Force -Path (Join-Path $Payload "tools") | Out-Null
    robocopy $srcMingw $destMingw /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "robocopy failed for tools/mingw (exit $LASTEXITCODE)" }
    $global:LASTEXITCODE = 0
    Write-Host "[ OK ] tools/mingw" -ForegroundColor Green
}
else {
    Write-Host "[INFO] tools/mingw not present; users run npm run chip:mingw after install" -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# .continue/ — the rule and the MCP registration travel with the payload
# ---------------------------------------------------------------------------
$destContinue = Join-Path $Payload ".continue"
New-Item -ItemType Directory -Force -Path (Join-Path $destContinue "rules") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $destContinue "mcpServers") | Out-Null

$rule = Join-Path $Root ".continue\rules\chip-design-mode.md"
if (Test-Path -LiteralPath $rule) {
    Copy-Item -LiteralPath $rule -Destination (Join-Path $destContinue "rules\chip-design-mode.md") -Force
}
$mcpReg = Join-Path $Root ".continue\mcpServers\custom-fpga.json"
if (Test-Path -LiteralPath $mcpReg) {
    Copy-Item -LiteralPath $mcpReg -Destination (Join-Path $destContinue "mcpServers\custom-fpga.json") -Force
}
Write-Host "[ OK ] .continue (rule + MCP registration)" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Optional: the two small vendored RTL references
# ---------------------------------------------------------------------------
if ($IncludeVendorRtl) {
    $destVendor = Join-Path $Payload "vendor"
    foreach ($name in $VendorRtl) {
        $src = Join-Path $Root "vendor\$name"
        if (-not (Test-Path -LiteralPath $src)) {
            Write-Host "[WARN] vendor/$name not initialised - skipping" -ForegroundColor Yellow
            continue
        }
        New-Item -ItemType Directory -Force -Path $destVendor | Out-Null
        # Skip .git: a submodule's history is many times the size of its sources
        # and is meaningless once detached from the superproject.
        $dst = Join-Path $destVendor $name
        robocopy $src $dst /E /XD ".git" /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed for vendor/$name (exit $LASTEXITCODE)" }
        Write-Host "[ OK ] vendor/$name" -ForegroundColor Green
    }
    $global:LASTEXITCODE = 0
}

# ---------------------------------------------------------------------------
# Root marker so the resolver recognises the payload
# ---------------------------------------------------------------------------
$marker = [ordered]@{
    name        = "Mobius"
    private     = $true
    description = "Mobius chip-design payload (custom-fpga-mcp + FPGA token sampler)"
    scripts     = [ordered]@{
        "chip:setup"     = "powershell -ExecutionPolicy Bypass -File scripts/setup-chip-design.ps1"
        "chip:cad-suite" = "powershell -ExecutionPolicy Bypass -File scripts/setup-oss-cad-suite.ps1"
        "chip:openxc7"   = "powershell -ExecutionPolicy Bypass -File scripts/setup-openxc7.ps1"
        "chip:mingw"     = "powershell -ExecutionPolicy Bypass -File scripts/setup-mingw.ps1"
        "chip:detect" = "node scripts/fpga-cli.js detect"
        "chip:lint"   = "node scripts/fpga-cli.js lint"
        "chip:test"   = "node scripts/fpga-cli.js test"
        "chip:serve"  = "node scripts/fpga-mcp-launcher.js"
    }
}
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText(
    (Join-Path $Payload "package.json"),
    ($marker | ConvertTo-Json -Depth 5),
    $utf8NoBom
)

$readme = @'
# Mobius chip-design payload

The FPGA token sampler that Chip mode drives: an on-die thermal-noise TRNG feeding
a stochastic-computing softmax, sampled over UART, with the host LLM supplying the
logits and consuming the returned token id.

This copy ships inside Mobius so the tooling exists on a machine with no git
checkout. Nothing here has been built yet -- there is no Python venv and no
bitstream, because both are specific to the machine and the board.

## Getting started

Open this folder as a workspace, then:

    npm run chip:setup      # Python venv + OSS CAD Suite + openXC7 + MinGW + tool detection
    npm run chip:cad-suite  # Verilator + Yosys bundle only (~570 MB, once)
    npm run chip:openxc7    # nextpnr-xilinx + chipdb (~650 MB, once; no Docker)
    npm run chip:mingw      # portable GNU make + g++ for Verilator --build

`chip:setup` downloads YosysHQ OSS CAD Suite into `tools/oss-cad-suite` (skip
with `-SkipCadSuite`), FPGAwars openXC7 into `tools/openxc7` (skip with
`-SkipOpenXc7`), and w64devkit make/g++ into `tools/mingw` (skip with
`-SkipMingw`). Docker is an optional fallback, not required for synthesis.

## No board attached?

That is the common case, and most of the flow still works. `chip:lint` and
`chip:simulate` exercise the RTL and the statistical behaviour of the sampler
under Verilator -- the distribution check there is what actually catches a wrong
sampler, since a wired-up-but-wrong design answers every frame perfectly.

Synthesis uses host Yosys + openXC7 (`nextpnr-xilinx`); Docker F4PGA is only a
fallback. Flashing needs openFPGALoader on the host, never in a container,
because USB/JTAG passthrough does not work in Docker Desktop.

## Layout

    chip-design/rtl/          synthesisable Verilog (TRNG, SC softmax, UART)
    chip-design/sim/          Verilator statistical testbench
    chip-design/soc/          optional LiteX SoC variant
    chip-design/constraints/  Arty A7-35T pin constraints
    chip-design/mcp/          the custom-fpga-mcp server
    chip-design/tests/        host-side unit tests (no hardware needed)
    scripts/                  launcher, diagnostic fallback, CLI shim, setup

The UART framing in `rtl/sampler_uart_top.v` and `mcp/custom_fpga_mcp/protocol.py`
are two halves of one contract. Changing one without the other does not crash --
it silently returns wrong tokens.
'@
[System.IO.File]::WriteAllText((Join-Path $Payload "README.md"), $readme, $utf8NoBom)

# ---------------------------------------------------------------------------
# Validate the payload the way the resolver will read it
# ---------------------------------------------------------------------------
$required = @(
    (Join-Path $Payload "package.json"),
    (Join-Path $Payload "scripts\fpga-mcp-launcher.js"),
    (Join-Path $Payload "scripts\fpga-mcp-resolve.js"),
    (Join-Path $Payload "chip-design\mcp\custom_fpga_mcp\server.py"),
    (Join-Path $Payload "chip-design\rtl\sampler_uart_top.v"),
    (Join-Path $Payload "chip-design\requirements.txt")
)
foreach ($path in $required) {
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Host "[FAIL] Staged payload validation failed: $path" -ForegroundColor Red
        exit 1
    }
}

# The launcher must resolve the payload root from inside it. If this fails the
# payload is shaped wrong and Chip mode would silently fall back in the installer.
$probe = Join-Path $destScripts "fpga-mcp-resolve.js"
$resolved = & node -e @"
const r = require(process.argv[1]);
process.chdir(require('path').dirname(process.argv[1]));
process.stdout.write(r.findRepoRoot() || '');
"@ $probe 2>&1
if (-not $resolved -or -not (Test-Path -LiteralPath $resolved)) {
    Write-Host "[FAIL] Staged launcher cannot resolve its own payload root" -ForegroundColor Red
    Write-Info "resolver returned: '$resolved'"
    exit 1
}
Write-Host "[ OK ] Resolver finds payload at $resolved" -ForegroundColor Green

$sizeMb = [math]::Round(
    ((Get-ChildItem -LiteralPath $Payload -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 2
)
Write-Host "[ OK ] Chip design payload staged ($sizeMb MB)" -ForegroundColor Green
Write-Info "Users run 'npm run chip:setup' inside resources\mobius-chip to finish setup."
