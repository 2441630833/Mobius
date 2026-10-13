#!/usr/bin/env bash
# =============================================================================
# Mobius IDE — Linux One-Line Fast Installer & Auto-Updater
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-linux.sh | bash
#
# Flags / Options:
#   curl -fsSL .../install-linux.sh | bash -s -- --force   # Force re-download & reinstall
#   MOBIUS_FORCE=1 curl -fsSL .../install-linux.sh | bash  # Force via environment variable
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

FORCE=false
CHECK_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --force|-f)
            FORCE=true
            ;;
        --check)
            CHECK_ONLY=true
            ;;
    esac
done

if [ "${MOBIUS_FORCE:-0}" = "1" ]; then
    FORCE=true
fi
if [ "${MOBIUS_CHECK:-0}" = "1" ]; then
    CHECK_ONLY=true
fi

echo -e "\n${CYAN}${BOLD}=== Mobius: Linux Fast Installer & Auto-Updater ===${NC}\n"

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

# 3. Detect Existing Installation
IS_INSTALLED=false
INSTALLED_VER=""
INSTALLED_TAG=""

if command -v mobius >/dev/null 2>&1; then
    IS_INSTALLED=true
    INSTALLED_VER=$(mobius --version 2>/dev/null | head -n 1 || true)
fi

if [ -f "/opt/mobius/.mobius-installed-tag" ]; then
    INSTALLED_TAG=$(cat "/opt/mobius/.mobius-installed-tag" 2>/dev/null | tr -d '[:space:]' || true)
elif [ -f "/usr/share/mobius/.mobius-installed-tag" ]; then
    INSTALLED_TAG=$(cat "/usr/share/mobius/.mobius-installed-tag" 2>/dev/null | tr -d '[:space:]' || true)
fi

if [ "$IS_INSTALLED" = true ]; then
    echo -e "${GREEN}✓${NC} Detected local installation: $(command -v mobius)"
    echo -e "  - Current Version: ${INSTALLED_VER:-Installed} ${INSTALLED_TAG:+[$INSTALLED_TAG]}"
fi

# 4. Fetch Latest Release Information
echo -e "${CYAN}→${NC} Fetching latest release information from GitHub..."
RELEASE_DATA=$(curl -s -H "User-Agent: Mobius-Installer-Linux" "https://api.github.com/repos/${REPO}/releases" || true)

LATEST_TAG=$(echo "$RELEASE_DATA" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)
if [ -z "$LATEST_TAG" ]; then
    LATEST_TAG="v1.0.4"
fi

if [ "$IS_DEB" = true ]; then
    DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o "https://[^\"]*${LINUX_ARCH}\.deb" | head -n 1 || true)
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v1.0.4/mobius_1.126.0_amd64.deb"
    fi
else
    DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o "https://[^\"]*linux-${TAR_ARCH}\.tar\.gz" | head -n 1 || true)
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v1.0.4/mobius-1.126.0-linux-x64.tar.gz"
    fi
fi

echo -e "${GREEN}✓${NC} Remote Release: ${BOLD}${LATEST_TAG}${NC}"
echo -e "${CYAN}→${NC} Download URL: $DOWNLOAD_URL"

# 5. Check If Already Up to Date
NEEDS_UPDATE=false
if [ "$IS_INSTALLED" = false ]; then
    NEEDS_UPDATE=true
elif [ "$FORCE" = true ]; then
    NEEDS_UPDATE=true
else
    if [ -n "$INSTALLED_TAG" ] && [ "$INSTALLED_TAG" = "$LATEST_TAG" ]; then
        NEEDS_UPDATE=false
    else
        NEEDS_UPDATE=true
    fi
fi

if [ "$CHECK_ONLY" = true ]; then
    if [ "$NEEDS_UPDATE" = true ]; then
        echo -e "\n${YELLOW}[Update Available] Latest: ${LATEST_TAG}${NC}"
    else
        echo -e "\n${GREEN}[Up to Date] Mobius is already up to date (${LATEST_TAG}).${NC}"
    fi
    exit 0
fi

if [ "$NEEDS_UPDATE" = false ]; then
    echo -e "\n${GREEN}${BOLD}✓ 本地 Mobius 已是最新版本 (${LATEST_TAG})！无需重复下载。${NC}"
    echo -e "  - 启动命令: ${CYAN}mobius${NC}"
    echo -e "  - 若需强制重新下载安装/修复，可运行:"
    echo -e "    ${YELLOW}curl -fsSL https://raw.githubusercontent.com/${REPO}/main/scripts/install-linux.sh | bash -s -- --force${NC}\n"
    exit 0
fi

# 6. Handle Running Processes Before Overwriting
if [ "$IS_INSTALLED" = true ]; then
    echo -e "\n${CYAN}=== 正在准备同步更新 Mobius ===${NC}"
    echo -e "准备从 ${INSTALLED_VER:-已安装} (${INSTALLED_TAG:-未知}) 升级至最新版本 ${BOLD}${LATEST_TAG}${NC}..."
    if pgrep -x "mobius" >/dev/null 2>&1; then
        echo -e "${YELLOW}!${NC} 检测到 Mobius 正在运行，正在关闭以防止文件锁定..."
        killall "mobius" 2>/dev/null || true
        sleep 1
    fi
fi

TEMP_DIR="$(mktemp -d -t mobius-install-XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

if [ "$IS_DEB" = true ]; then
    DEST_FILE="$TEMP_DIR/mobius.deb"
    echo -e "\n${CYAN}→${NC} Downloading package (${LATEST_TAG}): $DOWNLOAD_URL"
    curl -# -L -o "$DEST_FILE" "$DOWNLOAD_URL"
    
    echo -e "${CYAN}→${NC} Installing via dpkg / apt..."
    if [ "$EUID" -ne 0 ]; then
        sudo dpkg -i "$DEST_FILE" || sudo apt-get install -f -y
        echo "$LATEST_TAG" | sudo tee "/usr/share/mobius/.mobius-installed-tag" >/dev/null 2>&1 || true
    else
        dpkg -i "$DEST_FILE" || apt-get install -f -y
        echo "$LATEST_TAG" | tee "/usr/share/mobius/.mobius-installed-tag" >/dev/null 2>&1 || true
    fi
else
    DEST_FILE="$TEMP_DIR/mobius.tar.gz"
    echo -e "\n${CYAN}→${NC} Downloading tarball (${LATEST_TAG}): $DOWNLOAD_URL"
    curl -# -L -o "$DEST_FILE" "$DOWNLOAD_URL"
    
    INSTALL_DIR="/opt/mobius"
    echo -e "${CYAN}→${NC} Extracting to ${INSTALL_DIR}..."
    if [ "$EUID" -ne 0 ]; then
        sudo mkdir -p "$INSTALL_DIR"
        sudo tar -xzf "$DEST_FILE" -C "$INSTALL_DIR" --strip-components=1
        sudo ln -sf "$INSTALL_DIR/bin/mobius" /usr/local/bin/mobius
        echo "$LATEST_TAG" | sudo tee "$INSTALL_DIR/.mobius-installed-tag" >/dev/null 2>&1 || true
    else
        mkdir -p "$INSTALL_DIR"
        tar -xzf "$DEST_FILE" -C "$INSTALL_DIR" --strip-components=1
        ln -sf "$INSTALL_DIR/bin/mobius" /usr/local/bin/mobius
        echo "$LATEST_TAG" | tee "$INSTALL_DIR/.mobius-installed-tag" >/dev/null 2>&1 || true
    fi
fi

if [ "$IS_INSTALLED" = true ]; then
    echo -e "\n${GREEN}${BOLD}[Success] Mobius 已成功同步更新至最新版本 (${LATEST_TAG})！${NC}"
    echo -e "您的扩展插件、用户配置与工作区数据均完整保留。"
else
    echo -e "\n${GREEN}${BOLD}[Success] Mobius has been installed successfully (${LATEST_TAG})!${NC}"
fi

echo -e "You can launch it anytime by running: ${CYAN}mobius${NC}\n"
