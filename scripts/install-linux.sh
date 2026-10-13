#!/usr/bin/env bash
# =============================================================================
# Mobius IDE — Linux One-Line Fast Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-linux.sh | bash
# =============================================================================

set -e

REPO="2441630833/Mobius"
APP_NAME="mobius"

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "\n${CYAN}${BOLD}=== Installing Mobius for Linux ===${NC}\n"

# 1. Detect Architecture
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)
        LINUX_ARCH="amd64"
        TAR_ARCH="x64"
        echo -e "${GREEN}✓${NC} Detected architecture: x86_64 (${BOLD}x64${NC})"
        ;;
    aarch64|arm64)
        LINUX_ARCH="arm64"
        TAR_ARCH="arm64"
        echo -e "${GREEN}✓${NC} Detected architecture: AArch64 (${BOLD}arm64${NC})"
        ;;
    *)
        echo -e "${YELLOW}!${NC} Unknown architecture $ARCH, defaulting to x86_64"
        LINUX_ARCH="amd64"
        TAR_ARCH="x64"
        ;;
esac

# 2. Determine Package Format
IS_DEB=false
if command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    IS_DEB=true
    echo -e "${GREEN}✓${NC} Detected Debian/Ubuntu system (.deb)"
fi

TEMP_DIR="$(mktemp -d -t mobius-install-XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

echo -e "${CYAN}→${NC} Fetching latest release information..."
RELEASE_DATA=$(curl -s "https://api.github.com/repos/${REPO}/releases" || true)

if [ "$IS_DEB" = true ]; then
    DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o "https://[^\"]*${LINUX_ARCH}\.deb" | head -n 1 || true)
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v1.0.4/mobius_1.126.0_amd64.deb"
    fi
    
    DEST_FILE="$TEMP_DIR/mobius.deb"
    echo -e "${CYAN}→${NC} Downloading package from: $DOWNLOAD_URL"
    curl -# -L -o "$DEST_FILE" "$DOWNLOAD_URL"
    
    echo -e "${CYAN}→${NC} Installing via dpkg / apt..."
    if [ "$EUID" -ne 0 ]; then
        sudo dpkg -i "$DEST_FILE" || sudo apt-get install -f -y
    else
        dpkg -i "$DEST_FILE" || apt-get install -f -y
    fi
else
    DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o "https://[^\"]*linux-${TAR_ARCH}\.tar\.gz" | head -n 1 || true)
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v1.0.4/mobius-1.126.0-linux-x64.tar.gz"
    fi
    
    DEST_FILE="$TEMP_DIR/mobius.tar.gz"
    echo -e "${CYAN}→${NC} Downloading tarball from: $DOWNLOAD_URL"
    curl -# -L -o "$DEST_FILE" "$DOWNLOAD_URL"
    
    INSTALL_DIR="/opt/mobius"
    echo -e "${CYAN}→${NC} Extracting to ${INSTALL_DIR}..."
    if [ "$EUID" -ne 0 ]; then
        sudo mkdir -p "$INSTALL_DIR"
        sudo tar -xzf "$DEST_FILE" -C "$INSTALL_DIR" --strip-components=1
        sudo ln -sf "$INSTALL_DIR/bin/mobius" /usr/local/bin/mobius
    else
        mkdir -p "$INSTALL_DIR"
        tar -xzf "$DEST_FILE" -C "$INSTALL_DIR" --strip-components=1
        ln -sf "$INSTALL_DIR/bin/mobius" /usr/local/bin/mobius
    fi
fi

echo -e "\n${GREEN}${BOLD}🎉 Mobius has been installed successfully!${NC}"
echo -e "You can launch it anytime by running: ${CYAN}mobius${NC}\n"
