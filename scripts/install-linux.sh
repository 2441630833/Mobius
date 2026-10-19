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
    x86_64|amd64)
        LINUX_ARCH="amd64"
        TAR_ARCH="x64"
        ARCH_DESC="x86_64 (amd64 / x64)"
        ;;
    aarch64|arm64)
        LINUX_ARCH="arm64"
        TAR_ARCH="arm64"
        ARCH_DESC="AArch64 (arm64)"
        ;;
    *)
        echo -e "${RED}[ERROR] Unsupported architecture: $ARCH. Mobius supports x86_64 and arm64.${NC}"
        exit 1
        ;;
esac

# 2. Determine Package Format
IS_DEB=false
if command -v dpkg >/dev/null 2>&1 && command -v apt-get >/dev/null 2>&1; then
    IS_DEB=true
    DPKG_ARCH=$(dpkg --print-architecture 2>/dev/null || true)
    if [ "$DPKG_ARCH" = "arm64" ] || [ "$DPKG_ARCH" = "aarch64" ]; then
        LINUX_ARCH="arm64"
        TAR_ARCH="arm64"
        ARCH_DESC="AArch64 (arm64)"
    elif [ "$DPKG_ARCH" = "amd64" ] || [ "$DPKG_ARCH" = "x86_64" ]; then
        LINUX_ARCH="amd64"
        TAR_ARCH="x64"
        ARCH_DESC="x86_64 (amd64 / x64)"
    fi
    echo -e "${GREEN}✓${NC} Detected Debian/Ubuntu system (.deb, arch: ${BOLD}${LINUX_ARCH}${NC})"
else
    echo -e "${GREEN}✓${NC} Detected architecture: ${ARCH_DESC}"
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
echo -e "${CYAN}→${NC} Fetching release information from GitHub..."

# Step 4a: Retrieve latest release metadata from GitHub API or HTTP redirect
LATEST_RELEASE_JSON=""
LATEST_TAG=""

if command -v curl >/dev/null 2>&1; then
    # First try latest release endpoint
    API_RESPONSE=$(curl -fsSL -H "User-Agent: Mobius-Installer-Linux" "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)
    if echo "$API_RESPONSE" | grep -q '"tag_name"'; then
        LATEST_RELEASE_JSON="$API_RESPONSE"
        LATEST_TAG=$(echo "$API_RESPONSE" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)
    fi
fi

# Fallback: resolve release tag via HTTP redirect header if API is rate-limited or fails
if [ -z "$LATEST_TAG" ]; then
    REDIRECT_LOC=$(curl -sSI "https://github.com/${REPO}/releases/latest" 2>/dev/null | grep -i "^location:" | head -n 1 | tr -d '\r\n')
    if [ -n "$REDIRECT_LOC" ]; then
        LATEST_TAG=$(echo "$REDIRECT_LOC" | sed -e 's/.*tag\///' | tr -d ' /')
    fi
fi

if [ -z "$LATEST_TAG" ]; then
    LATEST_TAG="v1.0.6"
fi

# Step 4b: Find asset URL for the target architecture
DOWNLOAD_URL=""

# Priority 1: Match from latest release JSON
if [ -n "$LATEST_RELEASE_JSON" ]; then
    if [ "$IS_DEB" = true ]; then
        DOWNLOAD_URL=$(echo "$LATEST_RELEASE_JSON" | grep -o "https://[^\"]*${LINUX_ARCH}\.deb" | head -n 1 || true)
    else
        DOWNLOAD_URL=$(echo "$LATEST_RELEASE_JSON" | grep -o "https://[^\"]*linux-${TAR_ARCH}\.tar\.gz" | head -n 1 || true)
    fi
fi

# Priority 2: Probe direct asset URL for LATEST_TAG if not obtained via API
if [ -z "$DOWNLOAD_URL" ]; then
    if [ "$IS_DEB" = true ]; then
        CANDIDATE_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/mobius_1.126.0_${LINUX_ARCH}.deb"
    else
        CANDIDATE_URL="https://github.com/${REPO}/releases/download/${LATEST_TAG}/mobius-1.126.0-linux-${TAR_ARCH}.tar.gz"
    fi
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -I -L "$CANDIDATE_URL" 2>/dev/null || true)
    if [ "$HTTP_CODE" = "200" ]; then
        DOWNLOAD_URL="$CANDIDATE_URL"
    fi
fi

# Priority 3: Fallback query across all recent releases to locate the newest release containing this arch
if [ -z "$DOWNLOAD_URL" ]; then
    ALL_RELEASES=$(curl -fsSL -H "User-Agent: Mobius-Installer-Linux" "https://api.github.com/repos/${REPO}/releases" 2>/dev/null || true)
    if [ -n "$ALL_RELEASES" ]; then
        if [ "$IS_DEB" = true ]; then
            DOWNLOAD_URL=$(echo "$ALL_RELEASES" | grep -o "https://[^\"]*${LINUX_ARCH}\.deb" | head -n 1 || true)
        else
            DOWNLOAD_URL=$(echo "$ALL_RELEASES" | grep -o "https://[^\"]*linux-${TAR_ARCH}\.tar\.gz" | head -n 1 || true)
        fi
        if [ -n "$DOWNLOAD_URL" ]; then
            RELEASE_TAG_FROM_URL=$(echo "$DOWNLOAD_URL" | grep -o 'releases/download/[^/]*' | cut -d'/' -f3 || true)
            if [ -n "$RELEASE_TAG_FROM_URL" ]; then
                LATEST_TAG="$RELEASE_TAG_FROM_URL"
            fi
        fi
    fi
fi

# Step 4c: Strict Architecture Safety Check (NEVER cross-install or mismatch)
if [ -z "$DOWNLOAD_URL" ]; then
    echo -e "\n${RED}${BOLD}[错误] 未能找到适用于 ${LINUX_ARCH} (${TAR_ARCH}) 架构的安装包！${NC}"
    echo -e "当前系统检测架构: ${YELLOW}${LINUX_ARCH} (${TAR_ARCH})${NC}"
    echo -e "GitHub 最新发布版本: ${CYAN}${LATEST_TAG}${NC}"
    echo -e "原因说明: GitHub Release 尚未包含针对 ${BOLD}${LINUX_ARCH}${NC} 架构的构建文件。"
    echo -e "请查看 GitHub Releases 页面: ${CYAN}https://github.com/${REPO}/releases${NC}"
    echo -e "待 GitHub Action 编译完成后即可重新执行本脚本一键安装。"
    exit 1
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

    # Ensure desktop file exists for tarball
    if [ ! -f /usr/share/applications/mobius.desktop ]; then
        DESKTOP_CONTENT="[Desktop Entry]\nName=Mobius\nComment=Mobius Agentic Development Environment\nExec=/usr/local/bin/mobius %F\nIcon=mobius\nType=Application\nStartupNotify=true\nStartupWMClass=mobius\nCategories=Development;IDE;\nMimeType=text/plain;inode/directory;"
        if [ "$EUID" -ne 0 ]; then
            echo -e "$DESKTOP_CONTENT" | sudo tee /usr/share/applications/mobius.desktop >/dev/null 2>&1 || true
        else
            echo -e "$DESKTOP_CONTENT" | tee /usr/share/applications/mobius.desktop >/dev/null 2>&1 || true
        fi
    fi
fi

# 7. Setup Desktop Shortcut if Desktop directory exists
COPIED_TO_DESKTOP=""
TARGET_USER="${SUDO_USER:-$USER}"
if [ -n "$TARGET_USER" ]; then
    TARGET_HOME=$(getent passwd "$TARGET_USER" 2>/dev/null | cut -d: -f6)
fi
TARGET_HOME="${TARGET_HOME:-$HOME}"

DESKTOP_DIR=""
for candidate in "$TARGET_HOME/Desktop" "$TARGET_HOME/桌面"; do
    if [ -d "$candidate" ]; then
        DESKTOP_DIR="$candidate"
        break
    fi
done

if [ -n "$DESKTOP_DIR" ] && [ -f "/usr/share/applications/mobius.desktop" ]; then
    DESKTOP_FILE="$DESKTOP_DIR/mobius.desktop"
    if [ "$EUID" -ne 0 ]; then
        cp -f "/usr/share/applications/mobius.desktop" "$DESKTOP_FILE" 2>/dev/null || true
        chmod +x "$DESKTOP_FILE" 2>/dev/null || true
        if command -v gio >/dev/null 2>&1; then
            gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
        fi
    else
        cp -f "/usr/share/applications/mobius.desktop" "$DESKTOP_FILE" 2>/dev/null || true
        chmod +x "$DESKTOP_FILE" 2>/dev/null || true
        if [ -n "$SUDO_USER" ]; then
            chown "$SUDO_USER:$SUDO_USER" "$DESKTOP_FILE" 2>/dev/null || true
            if command -v gio >/dev/null 2>&1; then
                sudo -u "$SUDO_USER" gio set "$DESKTOP_FILE" metadata::trusted true 2>/dev/null || true
            fi
        fi
    fi
    if [ -f "$DESKTOP_FILE" ]; then
        COPIED_TO_DESKTOP="$DESKTOP_FILE"
    fi
fi

if [ "$IS_INSTALLED" = true ]; then
    echo -e "\n${GREEN}${BOLD}[Success] Mobius 已成功同步更新至最新版本 (${LATEST_TAG})！${NC}"
    echo -e "您的扩展插件、用户配置与工作区数据均完整保留。"
else
    echo -e "\n${GREEN}${BOLD}[Success] Mobius has been installed successfully (${LATEST_TAG})!${NC}"
fi

echo -e "\n${GREEN}${BOLD}=== 启动方式 / How to Launch ===${NC}"
echo -e "1. ${BOLD}终端运行${NC}: 输入 ${CYAN}mobius${NC} 回车即可启动图形界面 (或 ${CYAN}mobius . &${NC} 在后台打开当前目录)"
echo -e "2. ${BOLD}系统应用菜单${NC}: 按键盘 ${CYAN}Super / Win${NC} 键，搜索 ${CYAN}Mobius${NC} 点击图标打开（可右键选择「添加到收藏夹」固定至 Dock 侧边栏）"
if [ -n "$COPIED_TO_DESKTOP" ]; then
    echo -e "3. ${BOLD}桌面图标${NC}: 已自动放置快捷图标至桌面 (${CYAN}$COPIED_TO_DESKTOP${NC})"
    echo -e "   - 若双击提示未受信任，请在桌面上右键该图标点击「${YELLOW}允许启动 / Allow Launching${NC}」即可正常双击打开"
else
    echo -e "3. ${BOLD}桌面图标${NC}: 如需在桌面背景放置图标，可运行:"
    echo -e "   ${CYAN}cp /usr/share/applications/mobius.desktop ~/Desktop/ && chmod +x ~/Desktop/mobius.desktop${NC}"
    echo -e "   (然后在桌面上右键点击图标选择「${YELLOW}允许启动 / Allow Launching${NC}」)"
fi
echo ""
