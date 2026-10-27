# Mobius -- Setup Script
$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
try { $OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
$Root = Split-Path -Parent $PSScriptRoot

Write-Host "`n=== Mobius Setup ===" -ForegroundColor Cyan

# Check Node.js
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    Write-Host "ERROR: Node.js is required. Install from https://nodejs.org" -ForegroundColor Red
    exit 1
}
Write-Host "Node.js: $(node -v)" -ForegroundColor Green

# Configure Git UTF-8 encoding (prevent CP936/GBK mojibake on Windows)
try {
    git config --global core.quotepath false
    git config --global i18n.logoutputencoding utf-8
    git config --global i18n.commitencoding utf-8
    Write-Host "Git UTF-8 encoding configured (quotepath, logoutputencoding, commitencoding)." -ForegroundColor Green
} catch {
    Write-Host "Note: Could not set global git config: $($_.Exception.Message)" -ForegroundColor Yellow
}

# Copy .env.example to .env if missing
if (-not (Test-Path "$Root\.env")) {
    Write-Host "Creating .env from .env.example..." -ForegroundColor Yellow
    Copy-Item "$Root\.env.example" "$Root\.env"
    Write-Host "Edit $Root\.env and add your OPENAI_API_KEY" -ForegroundColor Yellow
}

# Create default Continue config if missing
$continueConfigDir = Join-Path $env:USERPROFILE ".continue"
$continueConfig = Join-Path $continueConfigDir "config.yaml"
if (-not (Test-Path $continueConfig)) {
    Write-Host "`nCreating default Continue config at $continueConfig" -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $continueConfigDir | Out-Null
    Copy-Item "$Root\config\continue-config.yaml" $continueConfig
}

Write-Host "`n=== Setup Complete ===" -ForegroundColor Green
Write-Host "Run the IDE:  npm start" -ForegroundColor White
Write-Host "Configure AI: Settings (gear icon) -> add API key" -ForegroundColor White
Write-Host "Codebase index: built-in MiniLM ONNX. OCR: npm run ensure:glm-ocr`n" -ForegroundColor White
