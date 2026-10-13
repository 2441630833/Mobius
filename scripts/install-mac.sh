#!/usr/bin/env bash
# =============================================================================
# Mobius IDE — macOS One-Line Fast Installer & Auto-Updater
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-mac.sh | bash
#
# Flags / Options:
#   curl -fsSL .../install-mac.sh | bash -s -- --force   # Force re-download & reinstall
#   MOBIUS_FORCE=1 curl -fsSL .../install-mac.sh | bash  # Force via environment variable
# =============================================================================

set -e

REPO="2441630833/Mobius"
APP_NAME="Mobius"

# Colors
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

echo -e "\n${CYAN}${BOLD}=== Mobius: macOS Fast Installer & Auto-Updater ===${NC}\n"

# 1. Detect Architecture
ARCH="$(uname -m)"
case "$ARCH" in
    arm64)
        MAC_ARCH="arm64"
        echo -e "${GREEN}✓${NC} Detected architecture: Apple Silicon (${BOLD}arm64${NC})"
        ;;
    x86_64)
        MAC_ARCH="x64"
        echo -e "${GREEN}✓${NC} Detected architecture: Intel (${BOLD}x64${NC})"
        ;;
    *)
        echo -e "${YELLOW}!${NC} Unknown architecture $ARCH, defaulting to arm64"
        MAC_ARCH="arm64"
        ;;
esac

# 2. Determine Target Directory & Detect Existing Installation
TARGET_DIR="/Applications"
if [ ! -w "$TARGET_DIR" ]; then
    echo -e "${YELLOW}!${NC} $TARGET_DIR is not writable by current user. Will use sudo for installation."
    USE_SUDO="sudo"
else
    USE_SUDO=""
fi

INSTALLED_APP="${TARGET_DIR}/${APP_NAME}.app"
IS_INSTALLED=false
INSTALLED_VER=""
INSTALLED_TAG=""

if [ -d "$INSTALLED_APP" ]; then
    IS_INSTALLED=true
    if [ -f "$INSTALLED_APP/Contents/Info.plist" ]; then
        INSTALLED_VER=$(defaults read "$INSTALLED_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || true)
    fi
    if [ -f "$INSTALLED_APP/Contents/.mobius-installed-tag" ]; then
        INSTALLED_TAG=$(cat "$INSTALLED_APP/Contents/.mobius-installed-tag" 2>/dev/null | tr -d '[:space:]' || true)
    fi
    echo -e "${GREEN}✓${NC} Detected local installation: ${BOLD}${INSTALLED_APP}${NC}"
    echo -e "  - Current Version: ${INSTALLED_VER:-Installed} ${INSTALLED_TAG:+[$INSTALLED_TAG]}"
fi

# 3. Resolve Latest Release Information
echo -e "${CYAN}→${NC} Fetching latest release information from GitHub..."
RELEASE_DATA=$(curl -s -H "User-Agent: Mobius-Installer-macOS" "https://api.github.com/repos/${REPO}/releases" || true)

# Extract latest release tag
LATEST_TAG=$(echo "$RELEASE_DATA" | grep -o '"tag_name": *"[^"]*"' | head -n 1 | cut -d'"' -f4 || true)
if [ -z "$LATEST_TAG" ]; then
    LATEST_TAG="v1.0.4"
fi

# Try to find DMG for this architecture, fallback to zip
DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o "https://[^\"]*macOS-${MAC_ARCH}\.dmg" | head -n 1 || true)
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o "https://[^\"]*darwin-${MAC_ARCH}\.zip" | head -n 1 || true)
fi

# Fallback default if API rate-limited
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v1.0.4/Mobius-1.126.0-macOS-${MAC_ARCH}.dmg"
fi

echo -e "${GREEN}✓${NC} Remote Release: ${BOLD}${LATEST_TAG}${NC}"
echo -e "${CYAN}→${NC} Download URL: $DOWNLOAD_URL"

# 4. Check If Already Up to Date
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
    echo -e "  - 安装路径: ${INSTALLED_APP}"
    echo -e "  - 启动命令: ${CYAN}open /Applications/Mobius.app${NC}"
    echo -e "  - 若需强制重新下载安装/修复，可运行:"
    echo -e "    ${YELLOW}curl -fsSL https://raw.githubusercontent.com/${REPO}/main/scripts/install-mac.sh | bash -s -- --force${NC}\n"
    exit 0
fi

# 5. Handle Running Processes Before Overwriting
if [ "$IS_INSTALLED" = true ]; then
    echo -e "\n${CYAN}=== 正在准备同步更新 Mobius ===${NC}"
    echo -e "准备从 ${INSTALLED_VER:-已安装} (${INSTALLED_TAG:-未知}) 升级至最新版本 ${BOLD}${LATEST_TAG}${NC}..."
    if pgrep -f "Mobius.app" >/dev/null 2>&1 || pgrep -x "Mobius" >/dev/null 2>&1; then
        echo -e "${YELLOW}!${NC} 检测到 Mobius 正在运行，正在通知其安全保存并退出所有相关进程..."
        osascript -e 'tell application "Mobius" to quit' >/dev/null 2>&1 || true
        sleep 1
        pkill -f "Mobius.app" >/dev/null 2>&1 || true
        pkill -x "Mobius" >/dev/null 2>&1 || true
        killall "Mobius Helper" >/dev/null 2>&1 || true
        killall "Mobius" >/dev/null 2>&1 || true
    fi
fi

# 6. Download Asset
TEMP_DIR="$(mktemp -d -t mobius-install-XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

FILE_NAME="$(basename "$DOWNLOAD_URL")"
DEST_FILE="$TEMP_DIR/$FILE_NAME"

echo -e "\n${CYAN}→${NC} Downloading ${BOLD}$FILE_NAME${NC} (${LATEST_TAG})..."
curl -# -L -o "$DEST_FILE" "$DOWNLOAD_URL"

# 7. Extract and Install
echo -e "${CYAN}→${NC} Installing to ${BOLD}${TARGET_DIR}/${APP_NAME}.app${NC}..."

if [[ "$DEST_FILE" == *.dmg ]]; then
    MOUNT_POINT="$TEMP_DIR/dmg_mount"
    mkdir -p "$MOUNT_POINT"
    hdiutil attach "$DEST_FILE" -mountpoint "$MOUNT_POINT" -nobrowse -quiet
    
    if [ -d "$MOUNT_POINT/${APP_NAME}.app" ]; then
        $USE_SUDO rm -rf "${TARGET_DIR}/${APP_NAME}.app"
        $USE_SUDO cp -R "$MOUNT_POINT/${APP_NAME}.app" "${TARGET_DIR}/"
    else
        FOUND_APP=$(find "$MOUNT_POINT" -maxdepth 1 -name "*.app" | head -n 1)
        if [ -n "$FOUND_APP" ]; then
            $USE_SUDO rm -rf "${TARGET_DIR}/${APP_NAME}.app"
            $USE_SUDO cp -R "$FOUND_APP" "${TARGET_DIR}/${APP_NAME}.app"
        else
            echo -e "${RED}✗ Failed to find application in DMG.${NC}"
            hdiutil detach "$MOUNT_POINT" -quiet || true
            exit 1
        fi
    fi
    hdiutil detach "$MOUNT_POINT" -quiet || true
elif [[ "$DEST_FILE" == *.zip ]]; then
    unzip -q -o "$DEST_FILE" -d "$TEMP_DIR/unpacked"
    FOUND_APP=$(find "$TEMP_DIR/unpacked" -maxdepth 2 -name "*.app" | head -n 1)
    if [ -n "$FOUND_APP" ]; then
        $USE_SUDO rm -rf "${TARGET_DIR}/${APP_NAME}.app"
        $USE_SUDO cp -R "$FOUND_APP" "${TARGET_DIR}/${APP_NAME}.app"
    else
        echo -e "${RED}✗ Failed to find application in ZIP.${NC}"
        exit 1
    fi
fi

# 8. Record Installed Tag
echo "$LATEST_TAG" | $USE_SUDO tee "${TARGET_DIR}/${APP_NAME}.app/Contents/.mobius-installed-tag" >/dev/null 2>&1 || true

# 9. Remove Gatekeeper Quarantine (Auto-Unquarantine)
echo -e "${CYAN}→${NC} Removing Gatekeeper quarantine attributes..."
$USE_SUDO xattr -cr "${TARGET_DIR}/${APP_NAME}.app" 2>/dev/null || true

# 10. Ensure Latest Transparent Application Icon
echo -e "${CYAN}→${NC} Ensuring latest transparent application icon..."
RAW_ICNS_URL="https://raw.githubusercontent.com/2441630833/Mobius-vscode/main/resources/darwin/code.icns"
ICNS_TEMP="$TEMP_DIR/code.icns"
if curl -fsSL -o "$ICNS_TEMP" "$RAW_ICNS_URL" 2>/dev/null && [ -s "$ICNS_TEMP" ]; then
    for icon_name in "Code.icns" "Code - OSS.icns" "Mobius.icns" "mobius.icns" "electron.icns"; do
        $USE_SUDO cp -f "$ICNS_TEMP" "${TARGET_DIR}/${APP_NAME}.app/Contents/Resources/$icon_name" 2>/dev/null || true
    done
fi

# 11. Touch App Bundle & Refresh macOS Icon Cache
$USE_SUDO touch "${TARGET_DIR}/${APP_NAME}.app" 2>/dev/null || true
killall Dock >/dev/null 2>&1 || true

# 12. Ad-hoc Sign if needed
if command -v codesign >/dev/null 2>&1; then
    $USE_SUDO codesign --force --deep --sign - "${TARGET_DIR}/${APP_NAME}.app" 2>/dev/null || true
fi

if [ "$IS_INSTALLED" = true ]; then
    echo -e "\n${GREEN}${BOLD}[Success] Mobius 已成功同步更新至最新版本 (${LATEST_TAG})！${NC}"
    echo -e "您的插件、工作区与个人数据均完整保留。"
else
    echo -e "\n${GREEN}${BOLD}[Success] Mobius has been installed successfully (${LATEST_TAG})!${NC}"
fi

echo -e "You can launch it anytime by:"
echo -e "  - Opening ${BOLD}Mobius${NC} in Spotlight or Launchpad"
echo -e "  - Running: ${CYAN}open /Applications/Mobius.app${NC}\n"
