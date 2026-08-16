$ErrorActionPreference = "Stop"

# raise-ulimit.ps1 -- wrapper around `gulp vscode-win32-x64-min` that adds the
# Node-side headroom needed to avoid EMFILE on Windows when the gulp task
# scans large node_modules trees (e.g. continue/core/node_modules/openai/...).
#
# The gulp task itself has also been edited to `ignore: ['continue/**', ...]`
# in vscode/gulpfile.mjs, so this script is the second line of defence:
# bump Node's old-space, bump the libuv threadpool, and hand off to gulp.
#
# Usage: called by `npm run compile:safe` -- do not invoke directly.
$nodeOldSpace = "8192"
$uvThreadpool = "8"

Write-Host "[raise-ulimit] node --max-old-space-size=$nodeOldSpace" -ForegroundColor Cyan
Write-Host "[raise-ulimit] UV_THREADPOOL_SIZE=$uvThreadpool" -ForegroundColor Cyan

$env:NODE_OPTIONS = "--max-old-space-size=$nodeOldSpace --experimental-strip-types"
$env:UV_THREADPOOL_SIZE = $uvThreadpool
$env:VSCODE_SKIP_NODE_VERSION_CHECK = "1"

# Resolve gulp relative to the repo root (this script lives in scripts/, the
# gulp binary lives in vscode/node_modules/gulp/bin/gulp.js).
$repoRoot = Split-Path -Parent $PSScriptRoot
$vscodeDir = Join-Path $repoRoot "vscode"
$gulpJs = Join-Path $vscodeDir "node_modules\gulp\bin\gulp.js"

if (-not (Test-Path $gulpJs)) {
    Write-Host "[raise-ulimit] gulp not found at $gulpJs -- run 'npm run install:vscode' first." -ForegroundColor Red
    exit 1
}

Push-Location $vscodeDir
try {
    & node $gulpJs $args
    exit $LASTEXITCODE
} finally {
    Pop-Location
}
