#!/usr/bin/env bash
# Build Mobius for macOS (VS Code OSS + Continue on Darwin)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VSCODE_DIR="$ROOT/vscode"
CONTINUE_DIR="$ROOT/continue"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "\n${CYAN}=== Building Mobius on macOS ===${NC}"

# Detect Arch
ARCH="$(uname -m)"
case "$ARCH" in
    arm64)   ARCH="arm64" ;;
    x86_64)  ARCH="x64" ;;
    *)       echo -e "${YELLOW}[WARN] Unknown architecture: $ARCH, defaulting to arm64${NC}"; ARCH="arm64" ;;
esac

# Allow overriding arch via flag
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

echo -e "Target architecture: ${GREEN}darwin-$ARCH${NC}\n"

# 1. Check prerequisites
bash "$SCRIPT_DIR/check-prerequisites-mac.sh"
if [ $? -ne 0 ]; then
    echo -e "${RED}[FAIL] Prerequisites check failed.${NC}"
    exit 1
fi

# 2. Sync brand assets
echo -e "\n${CYAN}=== [1/4] Syncing brand assets ===${NC}"
mkdir -p "$VSCODE_DIR/resources/darwin" "$VSCODE_DIR/src/vs/workbench/browser/media"
if [ -f "$ROOT/static/images/logo.png" ]; then
    cp -f "$ROOT/static/images/logo.png" "$VSCODE_DIR/src/vs/workbench/browser/media/logo.png"
    echo -e "${GREEN}[ OK ]${NC} Synced logo.png"
fi

# 3. Build Continue extension
echo -e "\n${CYAN}=== [2/4] Building Continue extension for macOS ===${NC}"
if [ -d "$CONTINUE_DIR/extensions/vscode" ]; then
    pushd "$CONTINUE_DIR" >/dev/null
    export CONTINUE_VSCODE_TARGET="darwin-$ARCH"
    export HUSKY="0"

    echo "Installing Continue root dependencies..."
    npm install --ignore-scripts

    echo "Building Continue internal packages..."
    node ./scripts/build-packages.js

    echo "Building Continue Core..."
    pushd core >/dev/null
    npm install --ignore-scripts
    npm run build || npm link
    popd >/dev/null

    echo "Building Continue GUI..."
    pushd gui >/dev/null
    npm install --ignore-scripts
    npm link @continuedev/core || npm install file:../core --no-save --ignore-scripts
    npm run build
    popd >/dev/null

    echo "Building Continue VS Code extension wrapper..."
    pushd extensions/vscode >/dev/null
    npm install --ignore-scripts
    npm link @continuedev/core 2>/dev/null || true

    # Download sqlite and ripgrep for darwin if missing
    mkdir -p ../../core/node_modules/sqlite3
    export SKIP_INSTALLS="false"
    node scripts/prepackage.js --target "darwin-$ARCH"

    # Build extension output
    mkdir -p build out
    npm run esbuild

    if [ ! -f "out/extension.js" ]; then
        echo -e "${RED}[ERROR] out/extension.js was not created${NC}"
        popd >/dev/null
        popd >/dev/null
        exit 1
    fi
    popd >/dev/null # extensions/vscode
    popd >/dev/null # continue

    # Link Continue into VS Code
    TARGET_EXT="$VSCODE_DIR/extensions/continue"
    rm -rf "$TARGET_EXT"
    mkdir -p "$(dirname "$TARGET_EXT")"
    ln -sfn "$CONTINUE_DIR/extensions/vscode" "$TARGET_EXT"
    echo -e "${GREEN}[ OK ] Linked continue -> vscode/extensions/continue${NC}"
else
    echo -e "${YELLOW}[WARN] continue/extensions/vscode not found, skipping Continue build${NC}"
fi

# 4. Build VS Code OSS
echo -e "\n${CYAN}=== [3/4] Building VS Code workbench ===${NC}"
pushd "$VSCODE_DIR" >/dev/null

export NODE_OPTIONS="--experimental-strip-types --max-old-space-size=8192"
export VSCODE_SKIP_NODE_VERSION_CHECK="1"
export npm_config_arch="$ARCH"

if [ ! -d "node_modules" ] || [ ! -f "node_modules/gulp/bin/gulp.js" ]; then
    echo "Installing VS Code node dependencies..."
    npm install --ignore-scripts
fi

# Ensure build tooling (@vscode/vsce) is installed
if [ ! -d "build/node_modules" ] || [ ! -f "build/node_modules/@vscode/vsce/package.json" ]; then
    echo "Installing VS Code build dependencies (@vscode/vsce)..."
    (cd build && npm install --ignore-scripts)
fi

# Ensure extension tooling (esbuild) is installed
if [ ! -d "extensions/node_modules" ] || [ ! -f "extensions/node_modules/esbuild/package.json" ]; then
    echo "Installing VS Code extensions dependencies (esbuild)..."
    (cd extensions && npm install --ignore-scripts)
fi

# Ensure @vscode/policy-watcher has fallback shim so missing native binary does not crash startup
POLICY_WATCHER_SRC="$VSCODE_DIR/node_modules/@vscode/policy-watcher/index.js"
if [ -f "$POLICY_WATCHER_SRC" ]; then
    cat << 'EOF' > "$POLICY_WATCHER_SRC"
let w;
try {
  w = require('bindings')('vscode-policy-watcher');
} catch (e) {
  w = function (p, d, cb) {
    if (typeof cb === 'function') {
      setImmediate(() => cb({}));
    }
    return { dispose: function () {} };
  };
}
exports.createWatcher = w;
EOF
fi

echo "Running postinstall..."
if ! node build/npm/postinstall.ts; then
    echo -e "${YELLOW}[WARN] postinstall failed, ensuring critical subproject dependencies directly...${NC}"
    for subdir in build extensions extensions/git extensions/git-base extensions/github extensions/github-authentication extensions/configuration-editing extensions/json-language-features extensions/markdown-language-features; do
        if [ -f "$subdir/package.json" ]; then
            (cd "$subdir" && npm install --ignore-scripts) || true
        fi
    done
fi

echo "Compiling VS Code client..."
npm run compile-client

popd >/dev/null

echo -e "\n${GREEN}=== [4/4] Mobius build complete for macOS ($ARCH)! ===${NC}"
echo -e "To package for macOS (.dmg + .zip), run:"
echo -e "  ${YELLOW}bash scripts/package-mac.sh${NC}\n"
echo -e "To run in development mode, run:"
echo -e "  ${YELLOW}bash scripts/launch-ide-mac.sh${NC}\n"
