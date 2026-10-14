#!/usr/bin/env bash
# Launch Mobius on Linux (dev mode from source)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VSCODE_DIR="$ROOT/vscode"

if [ ! -f "$VSCODE_DIR/scripts/code.sh" ]; then
    echo "VS Code source not found at $VSCODE_DIR"
    exit 1
fi

if [ ! -f "$VSCODE_DIR/out/main.js" ]; then
    echo "VS Code is not compiled. Please run: bash scripts/build-linux.sh"
    exit 1
fi

export VSCODE_SKIP_NODE_VERSION_CHECK="1"
export GIT_TERMINAL_PROMPT="0"
export GCM_INTERACTIVE="never"

unset NODE_OPTIONS
unset ELECTRON_RUN_AS_NODE

if [ "$MOBIUS_SKIP_COPILOT" = "1" ]; then
    export VSCODE_SKIP_BUILTIN_EXTENSIONS="GitHub.copilot-chat,GitHub.copilot,vscode.github-authentication"
else
    export VSCODE_SKIP_BUILTIN_EXTENSIONS="GitHub.copilot,vscode.github-authentication"
fi

echo "Launching Mobius dev client..."
EXTRA_ARGS=()
if [[ ! "$*" =~ --locale ]]; then
    EXTRA_ARGS+=(--locale=zh-cn)
fi
if [ $# -eq 0 ]; then
    exec "$VSCODE_DIR/scripts/code.sh" --agents --disable-workspace-trust "${EXTRA_ARGS[@]}"
else
    exec "$VSCODE_DIR/scripts/code.sh" "$@" "${EXTRA_ARGS[@]}"
fi
