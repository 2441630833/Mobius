#!/usr/bin/env bash
# Check build prerequisites for Mobius on macOS (Apple Silicon arm64 / Intel x64)
set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "\n${CYAN}=== Checking Mobius macOS Build Prerequisites ===${NC}\n"

ERRORS=0
WARNINGS=0

# 1. Check OS
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "${RED}[FAIL]${NC} This script is intended for macOS (Darwin). Current OS: $(uname -s)"
    ERRORS=$((ERRORS + 1))
else
    MAC_VER=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
    MAC_ARCH=$(uname -m)
    echo -e "${GREEN}[ OK ]${NC} Operating system: macOS $MAC_VER ($MAC_ARCH)"
fi

# 2. Check Xcode Command Line Tools (clang & make)
if command -v xcode-select >/dev/null 2>&1 && xcode-select -p >/dev/null 2>&1; then
    CLANG_VER=$(clang --version 2>/dev/null | head -n1 || echo "installed")
    echo -e "${GREEN}[ OK ]${NC} Xcode Command Line Tools: $CLANG_VER"
else
    echo -e "${RED}[FAIL]${NC} Xcode Command Line Tools are not installed."
    echo -e "       Install via: ${YELLOW}xcode-select --install${NC}"
    ERRORS=$((ERRORS + 1))
fi

# 3. Check Node.js (requires >= 20, recommended 22.x)
if command -v node >/dev/null 2>&1; then
    NODE_VER=$(node -v | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
    if (( NODE_MAJOR >= 20 )); then
        echo -e "${GREEN}[ OK ]${NC} Node.js version: v$NODE_VER (requires >= 20, recommended 22.x)"
    else
        echo -e "${RED}[FAIL]${NC} Node.js version is v$NODE_VER. Node.js 20.0+ (preferably 22.x) is required."
        echo -e "       Install via Homebrew: ${YELLOW}brew install node@22${NC}"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${RED}[FAIL]${NC} Node.js is not installed."
    echo -e "       Install via Homebrew: ${YELLOW}brew install node@22${NC}"
    ERRORS=$((ERRORS + 1))
fi

# 4. Check npm
if command -v npm >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} npm version: v$(npm -v)"
else
    echo -e "${RED}[FAIL]${NC} npm is not installed."
    ERRORS=$((ERRORS + 1))
fi

# 5. Check Python 3 (node-gyp native addons require Python 3.10+)
if command -v python3 >/dev/null 2>&1; then
    PY_VER=$(python3 --version 2>&1)
    echo -e "${GREEN}[ OK ]${NC} Python: $PY_VER"
else
    echo -e "${RED}[FAIL]${NC} Python 3 is not installed."
    echo -e "       Install via Homebrew: ${YELLOW}brew install python@3.11${NC}"
    ERRORS=$((ERRORS + 1))
fi

# 6. Check Git
if command -v git >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} Git: $(git --version)"
else
    echo -e "${RED}[FAIL]${NC} Git is not installed."
    ERRORS=$((ERRORS + 1))
fi

# 7. Check macOS Disk Image & Packaging Utilities (hdiutil & ditto)
if command -v hdiutil >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} macOS disk utility: hdiutil"
else
    echo -e "${RED}[FAIL]${NC} hdiutil command not found (required for building .dmg disk images)."
    ERRORS=$((ERRORS + 1))
fi

if command -v ditto >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} macOS archive utility: ditto"
else
    echo -e "${YELLOW}[WARN]${NC} ditto command not found; zip fallback will be used."
    WARNINGS=$((WARNINGS + 1))
fi

# 8. Check optional DMG styling utilities
if command -v dmgbuild >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} dmgbuild installed (supports styled DMG background)"
elif command -v create-dmg >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} create-dmg installed"
else
    echo -e "${CYAN}[INFO]${NC} dmgbuild / create-dmg not found; standard hdiutil will create the DMG."
fi

echo ""
if (( ERRORS > 0 )); then
    echo -e "${RED}[FAIL] Prerequisites check failed with $ERRORS error(s).${NC}\n"
    exit 1
else
    echo -e "${GREEN}[PASS] All required prerequisites for macOS build are satisfied!${NC}\n"
    exit 0
fi
