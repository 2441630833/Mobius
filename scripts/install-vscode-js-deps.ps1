# Fallback: npm install --ignore-scripts in all VS Code sub-projects (extensions, build/, etc.)
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$VsCodeDir = Join-Path $Root "vscode"

$subdirs = @(
    "build", "build/rspack", "build/vite",
    "extensions", "extensions/configuration-editing", "extensions/css-language-features",
    "extensions/css-language-features/server", "extensions/debug-auto-launch",
    "extensions/debug-server-ready", "extensions/emmet", "extensions/extension-editing",
    "extensions/git", "extensions/git-base", "extensions/github", "extensions/github-authentication",
    "extensions/grunt", "extensions/gulp", "extensions/html-language-features",
    "extensions/html-language-features/server", "extensions/ipynb", "extensions/jake",
    "extensions/json-language-features", "extensions/json-language-features/server",
    "extensions/markdown-language-features", "extensions/markdown-math", "extensions/media-preview",
    "extensions/merge-conflict", "extensions/mermaid-markdown-features",
    "extensions/microsoft-authentication", "extensions/notebook-renderers", "extensions/npm",
    "extensions/php-language-features", "extensions/references-view", "extensions/search-result",
    "extensions/simple-browser", "extensions/tunnel-forwarding", "extensions/terminal-suggest",
    "extensions/typescript-language-features", "extensions/vscode-api-tests",
    "extensions/vscode-colorize-tests", "extensions/vscode-colorize-perf-tests",
    "extensions/vscode-test-resolver",
    "remote", "remote/web",
    "test/automation", "test/integration/browser", "test/monaco", "test/smoke", "test/mcp",
    ".vscode/extensions/vscode-selfhost-import-aid",
    ".vscode/extensions/vscode-selfhost-test-provider",
    ".vscode/extensions/vscode-extras",
    ".vscode/extensions/vscode-pr-pinger"
)

Push-Location $VsCodeDir
$env:NODE_OPTIONS = "--experimental-strip-types"
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"

Write-Host "Installing JS dependencies in VS Code sub-projects (--ignore-scripts)..." -ForegroundColor Cyan
$failed = @()
foreach ($dir in $subdirs) {
    $pkg = Join-Path (Join-Path $VsCodeDir $dir) "package.json"
    if (-not (Test-Path $pkg)) { continue }
    Write-Host "  $dir" -ForegroundColor Gray
    Push-Location (Join-Path $VsCodeDir $dir)
    npm install --ignore-scripts 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $failed += $dir }
    Pop-Location
}

Pop-Location

if ($failed.Count -gt 0) {
    Write-Host "[WARN] Some sub-projects failed: $($failed -join ', ')" -ForegroundColor Yellow
}

if (-not (Test-Path (Join-Path $VsCodeDir "extensions\node_modules\esbuild\package.json"))) {
    Write-Host "[FAIL] extensions/node_modules/esbuild missing (required for compile)" -ForegroundColor Red
    exit 1
}

Write-Host "[ OK ] Sub-project dependencies installed (esbuild present)" -ForegroundColor Green
