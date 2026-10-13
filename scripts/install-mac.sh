#!/usr/bin/env bash
# =============================================================================
# Mobius IDE — macOS One-Line Fast Installer
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/2441630833/Mobius/main/scripts/install-mac.sh | bash
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

echo -e "\n${CYAN}${BOLD}=== Installing Mobius for macOS ===${NC}\n"

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

# 2. Determine Target Directory
TARGET_DIR="/Applications"
if [ ! -w "$TARGET_DIR" ]; then
    echo -e "${YELLOW}!${NC} $TARGET_DIR is not writable by current user. Will use sudo for installation."
    USE_SUDO="sudo"
else
    USE_SUDO=""
fi

# 3. Resolve Latest Release Information
echo -e "${CYAN}→${NC} Fetching latest release information..."
RELEASE_DATA=$(curl -s "https://api.github.com/repos/${REPO}/releases" || true)

# Try to find DMG for this architecture, fallback to tag if needed
DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o "https://[^\"]*macOS-${MAC_ARCH}\.dmg" | head -n 1 || true)
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL=$(echo "$RELEASE_DATA" | grep -o "https://[^\"]*darwin-${MAC_ARCH}\.zip" | head -n 1 || true)
fi

# Fallback default if API rate-limited
if [ -z "$DOWNLOAD_URL" ]; then
    DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v1.0.4/Mobius-1.126.0-macOS-${MAC_ARCH}.dmg"
fi

echo -e "${GREEN}✓${NC} Download URL resolved: $DOWNLOAD_URL"

# 4. Download Asset
TEMP_DIR="$(mktemp -d -t mobius-install-XXXXXX)"
trap 'rm -rf "$TEMP_DIR"' EXIT

FILE_NAME="$(basename "$DOWNLOAD_URL")"
DEST_FILE="$TEMP_DIR/$FILE_NAME"

echo -e "${CYAN}→${NC} Downloading ${BOLD}$FILE_NAME${NC}..."
curl -# -L -o "$DEST_FILE" "$DOWNLOAD_URL"

# 5. Extract and Install
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

# 6. Remove Gatekeeper Quarantine (Auto-Unquarantine)
echo -e "${CYAN}→${NC} Removing Gatekeeper quarantine attributes..."
$USE_SUDO xattr -cr "${TARGET_DIR}/${APP_NAME}.app" 2>/dev/null || true

# 7. Ad-hoc Sign if needed
if command -v codesign >/dev/null 2>&1; then
    $USE_SUDO codesign --force --deep --sign - "${TARGET_DIR}/${APP_NAME}.app" 2>/dev/null || true
fi

echo -e "\n${GREEN}${BOLD}🎉 Mobius has been installed successfully!${NC}"
echo -e "You can launch it anytime by:"
echo -e "  • Opening ${BOLD}Mobius${NC} in Spotlight or Launchpad"
echo -e "  • Running: ${CYAN}open /Applications/Mobius.app${NC}\n"
