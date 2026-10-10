#!/usr/bin/env bash
# Check build prerequisites for Mobius on Linux (Ubuntu / Debian)
set -eo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "\n${CYAN}=== Checking Mobius Linux Build Prerequisites ===${NC}\n"

ERRORS=0
MISSING_PKGS=()

# 1. Check OS
if [[ "$(uname -s)" != "Linux" ]]; then
    echo -e "${RED}[FAIL]${NC} This script is intended for Linux (Ubuntu / Debian)."
    ERRORS=$((ERRORS + 1))
else
    echo -e "${GREEN}[ OK ]${NC} Operating system: Linux ($(uname -m))"
fi

# 2. Check Node.js
if command -v node >/dev/null 2>&1; then
    NODE_VER=$(node -v | sed 's/v//')
    NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
    if (( NODE_MAJOR >= 20 )); then
        echo -e "${GREEN}[ OK ]${NC} Node.js version: v$NODE_VER (requires >= 20, recommended 22.x)"
    else
        echo -e "${RED}[FAIL]${NC} Node.js version is v$NODE_VER. Node 20.0+ (preferably 22.x) is required."
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${RED}[FAIL]${NC} Node.js is not installed."
    ERRORS=$((ERRORS + 1))
fi

# 3. Check npm
if command -v npm >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} npm version: v$(npm -v)"
else
    echo -e "${RED}[FAIL]${NC} npm is not installed."
    ERRORS=$((ERRORS + 1))
fi

# 4. Check Python 3
if command -v python3 >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} Python 3: $(python3 --version 2>&1)"
else
    echo -e "${RED}[FAIL]${NC} Python 3 is not installed."
    MISSING_PKGS+=("python3")
    ERRORS=$((ERRORS + 1))
fi

# 5. Check Git
if command -v git >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} Git: $(git --version)"
else
    echo -e "${RED}[FAIL]${NC} Git is not installed."
    MISSING_PKGS+=("git")
    ERRORS=$((ERRORS + 1))
fi

# 6. Check C/C++ compiler and make
if command -v gcc >/dev/null 2>&1 && command -v g++ >/dev/null 2>&1 && command -v make >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} C/C++ Build tools: $(gcc --version | head -n1)"
else
    echo -e "${RED}[FAIL]${NC} build-essential (gcc, g++, make) not found."
    MISSING_PKGS+=("build-essential")
    ERRORS=$((ERRORS + 1))
fi

# 7. Check pkg-config
if command -v pkg-config >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} pkg-config installed"
else
    echo -e "${YELLOW}[WARN]${NC} pkg-config not found."
    MISSING_PKGS+=("pkg-config")
fi

# 8. Check packaging tools (fakeroot, dpkg-deb)
if command -v fakeroot >/dev/null 2>&1 && command -v dpkg-deb >/dev/null 2>&1; then
    echo -e "${GREEN}[ OK ]${NC} Debian packaging tools: fakeroot, dpkg-deb"
else
    echo -e "${YELLOW}[WARN]${NC} fakeroot or dpkg-deb missing (needed to build .deb packages)."
    MISSING_PKGS+=("fakeroot" "dpkg")
fi

# 9. Check required C libraries for VS Code native modules
check_pkg_config() {
    local name="$1"
    local apt_pkg="$2"
    if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists "$name" 2>/dev/null; then
        echo -e "${GREEN}[ OK ]${NC} Library headers: $name"
    else
        echo -e "${YELLOW}[WARN]${NC} Library headers missing: $name (Ubuntu package: $apt_pkg)"
        MISSING_PKGS+=("$apt_pkg")
    fi
}

check_pkg_config "libsecret-1" "libsecret-1-dev"
check_pkg_config "x11" "libx11-dev"
check_pkg_config "xkbfile" "libxkbfile-dev"
check_pkg_config "krb5" "libkrb5-dev"

echo ""
if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    # Deduplicate
    UNIQUE_PKGS=($(echo "${MISSING_PKGS[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    echo -e "${YELLOW}To install all missing Ubuntu / Debian packages, run:${NC}"
    echo -e "  sudo apt-get update && sudo apt-get install -y ${UNIQUE_PKGS[*]}"
    echo ""
fi

if (( ERRORS > 0 )); then
    echo -e "${RED}[FAIL] Prerequisites check failed with $ERRORS error(s).${NC}\n"
    exit 1
else
    echo -e "${GREEN}[PASS] All required prerequisites are satisfied!${NC}\n"
    exit 0
fi
