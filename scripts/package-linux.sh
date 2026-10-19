#!/usr/bin/env bash
# Package Mobius for Linux / Ubuntu (.deb + portable .tar.gz)
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

ARCH="x64"
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
    x64|amd64|x86_64)
        ARCH="x64"
        DEB_ARCH="amd64"
        ;;
    arm64|aarch64)
        ARCH="arm64"
        DEB_ARCH="arm64"
        ;;
    *)
        echo -e "${RED}Unsupported arch: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "\n${CYAN}=== Packaging Mobius for Linux Ubuntu ($DEB_ARCH) ===${NC}\n"

mkdir -p "$DIST_DIR"

CLIENT_DIR="$ROOT/VSCode-linux-$ARCH"

if [ "$SKIP_BUILD" -eq 0 ]; then
    echo -e "${CYAN}--- Step 1: Building Mobius client ---${NC}"
    bash "$SCRIPT_DIR/build-linux.sh" --arch "$ARCH"

    pushd "$VSCODE_DIR" >/dev/null
    echo "Running gulp vscode-linux-$ARCH-min..."
    export NODE_OPTIONS="--experimental-strip-types --max-old-space-size=8192"
    node ./node_modules/gulp/bin/gulp.js "vscode-linux-$ARCH-min"
    popd >/dev/null
fi

if [ ! -d "$CLIENT_DIR" ]; then
    echo -e "${RED}[ERROR] Binary directory $CLIENT_DIR does not exist!${NC}"
    exit 1
fi

VERSION=$(node -p "require('$VSCODE_DIR/package.json').version")
APP_NAME=$(node -p "require('$VSCODE_DIR/product.json').applicationName || 'mobius'")
NAME_LONG=$(node -p "require('$VSCODE_DIR/product.json').nameLong || 'Mobius'")
NAME_SHORT=$(node -p "require('$VSCODE_DIR/product.json').nameShort || 'Mobius'")
ICON_NAME=$(node -p "require('$VSCODE_DIR/product.json').linuxIconName || 'mobius'")
URL_PROTOCOL=$(node -p "require('$VSCODE_DIR/product.json').urlProtocol || 'mobius'")

echo -e "Application: ${GREEN}$NAME_LONG${NC} ($APP_NAME)"
echo -e "Version:     ${GREEN}$VERSION${NC}"
echo -e "Arch:        ${GREEN}$DEB_ARCH${NC}"

# Fail before shipping if the actual target runtime cannot load node-pty or
# exchange data with a shell. Also covers --skip-build and cached client trees.
echo "Verifying packaged terminal on linux-$ARCH..."
ELECTRON_RUN_AS_NODE=1 "$CLIENT_DIR/$APP_NAME" "$SCRIPT_DIR/verify-linux-terminal.cjs" "$CLIENT_DIR" "$ARCH"

# =========================================================================
# Step 2: Build Debian .deb Package
# =========================================================================
echo -e "\n${CYAN}--- Step 2: Packaging Ubuntu / Debian .deb ---${NC}"

STAGE_DIR="$ROOT/.build/linux/deb/$DEB_ARCH/$APP_NAME-$DEB_ARCH"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR/DEBIAN"
mkdir -p "$STAGE_DIR/usr/share/$APP_NAME"
mkdir -p "$STAGE_DIR/usr/share/applications"
mkdir -p "$STAGE_DIR/usr/share/pixmaps"
mkdir -p "$STAGE_DIR/usr/share/mime/packages"
mkdir -p "$STAGE_DIR/usr/share/bash-completion/completions"
mkdir -p "$STAGE_DIR/usr/share/zsh/vendor-completions"
mkdir -p "$STAGE_DIR/usr/bin"

echo "Copying client binaries to /usr/share/$APP_NAME..."
cp -a "$CLIENT_DIR/." "$STAGE_DIR/usr/share/$APP_NAME/"

# Ensure main executable permissions
chmod 755 "$STAGE_DIR/usr/share/$APP_NAME/$APP_NAME" 2>/dev/null || true
if [ -f "$STAGE_DIR/usr/share/$APP_NAME/chrome-sandbox" ]; then
    chmod 4755 "$STAGE_DIR/usr/share/$APP_NAME/chrome-sandbox" 2>/dev/null || chmod 755 "$STAGE_DIR/usr/share/$APP_NAME/chrome-sandbox"
fi

# Create /usr/bin symlink
ln -sf "/usr/share/$APP_NAME/bin/$APP_NAME" "$STAGE_DIR/usr/bin/$APP_NAME"

# Copy Icon
if [ -f "$VSCODE_DIR/resources/linux/code.png" ]; then
    cp "$VSCODE_DIR/resources/linux/code.png" "$STAGE_DIR/usr/share/pixmaps/$ICON_NAME.png"
elif [ -f "$ROOT/static/images/logo.png" ]; then
    cp "$ROOT/static/images/logo.png" "$STAGE_DIR/usr/share/pixmaps/$ICON_NAME.png"
fi

# Desktop entries
sed \
    -e "s|@@NAME_LONG@@|$NAME_LONG|g" \
    -e "s|@@NAME_SHORT@@|$NAME_SHORT|g" \
    -e "s|@@NAME@@|$APP_NAME|g" \
    -e "s|@@EXEC@@|/usr/share/$APP_NAME/$APP_NAME|g" \
    -e "s|@@ICON@@|$ICON_NAME|g" \
    -e "s|@@URLPROTOCOL@@|$URL_PROTOCOL|g" \
    "$VSCODE_DIR/resources/linux/code.desktop" > "$STAGE_DIR/usr/share/applications/$APP_NAME.desktop"

sed \
    -e "s|@@NAME_LONG@@|$NAME_LONG|g" \
    -e "s|@@NAME_SHORT@@|$NAME_SHORT|g" \
    -e "s|@@NAME@@|$APP_NAME|g" \
    -e "s|@@EXEC@@|/usr/share/$APP_NAME/$APP_NAME|g" \
    -e "s|@@ICON@@|$ICON_NAME|g" \
    -e "s|@@URLPROTOCOL@@|$URL_PROTOCOL|g" \
    "$VSCODE_DIR/resources/linux/code-url-handler.desktop" > "$STAGE_DIR/usr/share/applications/$APP_NAME-url-handler.desktop"

# MIME
sed \
    -e "s|@@NAME_LONG@@|$NAME_LONG|g" \
    -e "s|@@NAME@@|$APP_NAME|g" \
    "$VSCODE_DIR/resources/linux/code-workspace.xml" > "$STAGE_DIR/usr/share/mime/packages/$APP_NAME-workspace.xml"

# Shell completions
if [ -f "$VSCODE_DIR/resources/completions/bash/code" ]; then
    sed -e "s|@@APPNAME@@|$APP_NAME|g" "$VSCODE_DIR/resources/completions/bash/code" > "$STAGE_DIR/usr/share/bash-completion/completions/$APP_NAME"
fi
if [ -f "$VSCODE_DIR/resources/completions/zsh/_code" ]; then
    sed -e "s|@@APPNAME@@|$APP_NAME|g" "$VSCODE_DIR/resources/completions/zsh/_code" > "$STAGE_DIR/usr/share/zsh/vendor-completions/_$APP_NAME"
fi

# Scripts: postinst, prerm, postrm
for script in postinst prerm postrm; do
    tmpl="$VSCODE_DIR/resources/linux/debian/$script.template"
    if [ -f "$tmpl" ]; then
        sed \
            -e "s|@@NAME@@|$APP_NAME|g" \
            -e "s|@@ARCHITECTURE@@|$DEB_ARCH|g" \
            "$tmpl" > "$STAGE_DIR/DEBIAN/$script"
        chmod 755 "$STAGE_DIR/DEBIAN/$script"
    fi
done

# Calculate installed size in KB
INSTALLED_SIZE=$(du -sk "$STAGE_DIR/usr" | cut -f1)

# Generate DEBIAN/control
DEPS="ca-certificates, libasound2 (>= 1.0.17), libatk-bridge2.0-0 (>= 2.5.3), libatk1.0-0 (>= 2.11.90), libc6 (>= 2.28), libcairo2 (>= 1.6.0), libcurl4 | libcurl3, libdbus-1-3 (>= 1.9.14), libexpat1, libgbm1 (>= 17.1.0~rc2), libglib2.0-0 (>= 2.39.4), libgtk-3-0 (>= 3.9.10), libnss3 (>= 3.26), libpango-1.0-0 (>= 1.14.0), libstdc++6 (>= 6), libx11-6, libxcomposite1, libxdamage1, libxext6, libxfixes3, libxrandr2, libxkbcommon0, libxkbfile1"
RECOMMENDS="libvulkan1, bubblewrap, socat"

cat <<EOF > "$STAGE_DIR/DEBIAN/control"
Package: $APP_NAME
Version: $VERSION
Section: devel
Priority: optional
Architecture: $DEB_ARCH
Maintainer: Mobius Team <support@mobius.dev>
Installed-Size: $INSTALLED_SIZE
Depends: $DEPS
Recommends: $RECOMMENDS
Homepage: https://github.com/physical-ai/physical-ai-ide
Description: Mobius - AI-powered IDE with Self-Evolving Agents
 Mobius is an intelligent development environment based on VS Code OSS
 and Continue, featuring auto-accumulating skills, intent routing, and
 recursive self-improvement.
EOF

DEB_OUTPUT="$DIST_DIR/${APP_NAME}_${VERSION}_${DEB_ARCH}.deb"
rm -f "$DEB_OUTPUT"

echo "Building deb package with dpkg-deb..."
if command -v fakeroot >/dev/null 2>&1; then
    fakeroot dpkg-deb -Zxz -b "$STAGE_DIR" "$DEB_OUTPUT"
else
    dpkg-deb -Zxz -b "$STAGE_DIR" "$DEB_OUTPUT"
fi

echo -e "${GREEN}[ OK ] Deb package created:${NC} $DEB_OUTPUT"

# =========================================================================
# Step 3: Build Portable .tar.gz
# =========================================================================
echo -e "\n${CYAN}--- Step 3: Packaging Portable .tar.gz ---${NC}"
TAR_OUTPUT="$DIST_DIR/${APP_NAME}-${VERSION}-linux-${ARCH}.tar.gz"
rm -f "$TAR_OUTPUT"

echo "Creating tarball..."
tar -czf "$TAR_OUTPUT" -C "$ROOT" "VSCode-linux-$ARCH"
echo -e "${GREEN}[ OK ] Tarball created:${NC} $TAR_OUTPUT"

# =========================================================================
# Step 4: Checksums
# =========================================================================
echo -e "\n${CYAN}--- Step 4: Checksums ---${NC}"
pushd "$DIST_DIR" >/dev/null
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$(basename "$DEB_OUTPUT")" "$(basename "$TAR_OUTPUT")" > SHA256SUMS.txt
    echo -e "${GREEN}[ OK ] SHA256SUMS.txt generated${NC}"
    cat SHA256SUMS.txt
fi
popd >/dev/null

echo -e "\n${GREEN}=== Packaging Complete! ===${NC}"
echo -e "Debian/Ubuntu package: ${CYAN}$DEB_OUTPUT${NC}"
echo -e "Portable archive:      ${CYAN}$TAR_OUTPUT${NC}"
echo -e "\nTo install on Ubuntu, run:"
echo -e "  ${YELLOW}sudo apt install $DEB_OUTPUT${NC}"
echo -e "or:"
echo -e "  ${YELLOW}sudo dpkg -i $DEB_OUTPUT && sudo apt-get install -f${NC}\n"
