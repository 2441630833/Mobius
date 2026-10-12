#!/usr/bin/env bash
# Package Mobius for macOS (.dmg installer + portable .zip / .tar.gz)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VSCODE_DIR="$ROOT/vscode"
DIST_DIR="$ROOT/dist"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ARCH="arm64"
# Default to current machine architecture on macOS
if [[ "$(uname -s)" == "Darwin" ]]; then
    CURRENT_ARCH="$(uname -m)"
    case "$CURRENT_ARCH" in
        arm64)  ARCH="arm64" ;;
        x86_64) ARCH="x64" ;;
        *)      ARCH="arm64" ;;
    esac
fi

SKIP_BUILD=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Map arch
case "$ARCH" in
    x64|x86_64|amd64)
        ARCH="x64"
        MAC_ARCH_LABEL="x64 (Intel)"
        ;;
    arm64|aarch64|m1|m2|m3|m4)
        ARCH="arm64"
        MAC_ARCH_LABEL="arm64 (Apple Silicon)"
        ;;
    *)
        echo -e "${RED}Unsupported arch: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "\n${CYAN}=== Packaging Mobius for macOS Desktop ($MAC_ARCH_LABEL) ===${NC}\n"

mkdir -p "$DIST_DIR"

CLIENT_DIR="$ROOT/VSCode-darwin-$ARCH"

if [ "$SKIP_BUILD" -eq 0 ]; then
    echo -e "${CYAN}--- Step 1: Building Mobius client for macOS ($ARCH) ---${NC}"
    bash "$SCRIPT_DIR/build-mac.sh" --arch "$ARCH"

    pushd "$VSCODE_DIR" >/dev/null
    echo "Running gulp vscode-darwin-$ARCH-min..."
    export NODE_OPTIONS="--experimental-strip-types --max-old-space-size=8192"
    export VSCODE_SKIP_NODE_VERSION_CHECK="1"
    export npm_config_arch="$ARCH"
    export GITHUB_TOKEN="${GITHUB_TOKEN:-}"
    node ./node_modules/gulp/bin/gulp.js "vscode-darwin-$ARCH-min"
    popd >/dev/null
fi

if [ ! -d "$CLIENT_DIR" ]; then
    echo -e "${RED}[ERROR] Binary directory $CLIENT_DIR does not exist!${NC}"
    exit 1
fi

VERSION=$(node -p "require('$VSCODE_DIR/package.json').version")
NAME_LONG=$(node -p "require('$VSCODE_DIR/product.json').nameLong || 'Mobius'")
NAME_SHORT=$(node -p "require('$VSCODE_DIR/product.json').nameShort || 'Mobius'")
APP_BUNDLE_NAME="$NAME_LONG.app"
APP_PATH="$CLIENT_DIR/$APP_BUNDLE_NAME"

if [ ! -d "$APP_PATH" ]; then
    FOUND_APP=$(find "$CLIENT_DIR" -maxdepth 1 -name "*.app" | head -n 1)
    if [ -n "$FOUND_APP" ] && [ -d "$FOUND_APP" ]; then
        APP_PATH="$FOUND_APP"
        APP_BUNDLE_NAME="$(basename "$FOUND_APP")"
        echo -e "${GREEN}[ OK ] Found app bundle at:${NC} $APP_PATH"
    else
        echo -e "${RED}[ERROR] App bundle $APP_PATH does not exist in $CLIENT_DIR!${NC}"
        ls -la "$CLIENT_DIR" 2>/dev/null || true
        exit 1
    fi
fi

echo -e "Application: ${GREEN}$NAME_LONG${NC} ($APP_BUNDLE_NAME)"
echo -e "Version:     ${GREEN}$VERSION${NC}"
echo -e "Arch:        ${GREEN}$ARCH${NC} ($MAC_ARCH_LABEL)"

# =========================================================================
# Step 1.5: Fix Permissions & Apply Ad-hoc Code Signature for macOS
# =========================================================================
# Note: On macOS Apple Silicon (arm64), any modified or unsigned Mach-O binary
# is immediately terminated by the kernel (AMFI) with SIGKILL (Killed: 9).
# An ad-hoc code signature satisfies kernel requirements and prevents instant crashes.
echo -e "\n${CYAN}--- Step 1.5: Preparing & Signing macOS Application Bundle ---${NC}"

if [ -d "$APP_PATH/Contents/MacOS" ]; then
    chmod +x "$APP_PATH/Contents/MacOS/"* 2>/dev/null || true
fi

# Ensure all nested helper binaries are executable
find "$APP_PATH" -type f -path "*/MacOS/*" -exec chmod +x {} + 2>/dev/null || true

if command -v xattr >/dev/null 2>&1; then
    echo "Clearing extended quarantine attributes..."
    xattr -cr "$APP_PATH" 2>/dev/null || true
fi

if command -v codesign >/dev/null 2>&1; then
    echo "Applying ad-hoc code signature to $APP_BUNDLE_NAME..."
    ENTITLEMENTS="$VSCODE_DIR/build/azure-pipelines/darwin/app-entitlements.plist"
    if [ -f "$ENTITLEMENTS" ]; then
        codesign --force --deep --sign - --entitlements "$ENTITLEMENTS" "$APP_PATH" || \
        codesign --force --deep --sign - "$APP_PATH"
    else
        codesign --force --deep --sign - "$APP_PATH"
    fi
    echo -e "${GREEN}[ OK ] Successfully signed $APP_BUNDLE_NAME ad-hoc${NC}"
else
    echo -e "${YELLOW}[WARN] codesign utility not found, skipping signing${NC}"
fi

# =========================================================================
# Step 2: Build macOS .dmg Disk Image (Drag-and-Drop installer)
# =========================================================================
echo -e "\n${CYAN}--- Step 2: Creating macOS .dmg Disk Image ---${NC}"

DMG_OUTPUT="$DIST_DIR/${NAME_LONG}-${VERSION}-macOS-${ARCH}.dmg"
rm -f "$DMG_OUTPUT"

DMG_STAGE="$ROOT/.build/mac/dmg/$ARCH"
rm -rf "$DMG_STAGE"
mkdir -p "$DMG_STAGE"

echo "Staging application bundle..."
if command -v ditto >/dev/null 2>&1; then
    ditto "$APP_PATH" "$DMG_STAGE/$APP_BUNDLE_NAME"
else
    cp -R "$APP_PATH" "$DMG_STAGE/"
fi

# Create Applications shortcut for easy drag-to-install
ln -s /Applications "$DMG_STAGE/Applications"

# Copy disk icon if available
if [ -f "$VSCODE_DIR/resources/darwin/code.icns" ]; then
    cp -f "$VSCODE_DIR/resources/darwin/code.icns" "$DMG_STAGE/.VolumeIcon.icns" 2>/dev/null || true
fi

echo "Building DMG using hdiutil..."
if command -v hdiutil >/dev/null 2>&1; then
    hdiutil create \
        -volname "$NAME_LONG" \
        -srcfolder "$DMG_STAGE" \
        -ov \
        -format UDZO \
        "$DMG_OUTPUT"
    echo -e "${GREEN}[ OK ] DMG disk image created:${NC} $DMG_OUTPUT"
else
    echo -e "${YELLOW}[WARN] hdiutil not found, skipping DMG creation${NC}"
fi

# Clean temporary stage
rm -rf "$DMG_STAGE"

# =========================================================================
# Step 3: Build Portable .zip (Preserving Mach-O symlinks and permissions)
# =========================================================================
echo -e "\n${CYAN}--- Step 3: Packaging Portable .zip Archive ---${NC}"
ZIP_OUTPUT="$DIST_DIR/${NAME_LONG}-${VERSION}-darwin-${ARCH}.zip"
rm -f "$ZIP_OUTPUT"

if command -v ditto >/dev/null 2>&1; then
    echo "Creating zip archive with ditto (preserving macOS attributes)..."
    ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_OUTPUT"
    echo -e "${GREEN}[ OK ] Zip archive created:${NC} $ZIP_OUTPUT"
else
    echo "Creating zip archive with zip..."
    pushd "$CLIENT_DIR" >/dev/null
    zip -r -y -q "$ZIP_OUTPUT" "$APP_BUNDLE_NAME"
    popd >/dev/null
    echo -e "${GREEN}[ OK ] Zip archive created:${NC} $ZIP_OUTPUT"
fi

# =========================================================================
# Step 4: Build Portable .tar.gz
# =========================================================================
echo -e "\n${CYAN}--- Step 4: Packaging Portable .tar.gz ---${NC}"
TAR_OUTPUT="$DIST_DIR/${NAME_LONG}-${VERSION}-darwin-${ARCH}.tar.gz"
rm -f "$TAR_OUTPUT"

echo "Creating tarball..."
tar -czf "$TAR_OUTPUT" -C "$CLIENT_DIR" "$APP_BUNDLE_NAME"
echo -e "${GREEN}[ OK ] Tarball created:${NC} $TAR_OUTPUT"

# =========================================================================
# Step 5: Checksums
# =========================================================================
echo -e "\n${CYAN}--- Step 5: Checksums ---${NC}"
pushd "$DIST_DIR" >/dev/null
HASH_TOOL=""
if command -v shasum >/dev/null 2>&1; then
    HASH_TOOL="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    HASH_TOOL="sha256sum"
fi

if [ -n "$HASH_TOOL" ]; then
    FILES_TO_HASH=()
    [ -f "$(basename "$DMG_OUTPUT")" ] && FILES_TO_HASH+=("$(basename "$DMG_OUTPUT")")
    [ -f "$(basename "$ZIP_OUTPUT")" ] && FILES_TO_HASH+=("$(basename "$ZIP_OUTPUT")")
    [ -f "$(basename "$TAR_OUTPUT")" ] && FILES_TO_HASH+=("$(basename "$TAR_OUTPUT")")
    
    if [ ${#FILES_TO_HASH[@]} -gt 0 ]; then
        $HASH_TOOL "${FILES_TO_HASH[@]}" >> SHA256SUMS.txt
        # Deduplicate checksum lines
        sort -u SHA256SUMS.txt -o SHA256SUMS.txt
        echo -e "${GREEN}[ OK ] SHA256SUMS.txt updated${NC}"
        cat SHA256SUMS.txt
    fi
fi
popd >/dev/null

echo -e "\n${GREEN}=== Packaging Complete for macOS ($ARCH)! ===${NC}"
[ -f "$DMG_OUTPUT" ] && echo -e "macOS Disk Image (DMG): ${CYAN}$DMG_OUTPUT${NC}"
[ -f "$ZIP_OUTPUT" ] && echo -e "macOS Portable Zip:     ${CYAN}$ZIP_OUTPUT${NC}"
[ -f "$TAR_OUTPUT" ] && echo -e "macOS Portable Tarball: ${CYAN}$TAR_OUTPUT${NC}"
echo -e "\nTo install on macOS, double-click the DMG and drag ${BOLD}$NAME_LONG.app${NC} into Applications,"
echo -e "or run in terminal:"
echo -e "  ${YELLOW}hdiutil attach $DMG_OUTPUT${NC}"
echo -e "  ${YELLOW}cp -R /Volumes/$NAME_LONG/$APP_BUNDLE_NAME /Applications/${NC}"
echo -e "  ${YELLOW}hdiutil detach /Volumes/$NAME_LONG${NC}\n"
echo -e "If macOS blocks opening unnotarized app on first launch, run:"
echo -e "  ${YELLOW}sudo xattr -rd com.apple.quarantine /Applications/$APP_BUNDLE_NAME${NC}"
echo -e "  ${YELLOW}sudo codesign --force --deep --sign - /Applications/$APP_BUNDLE_NAME${NC}\n"
