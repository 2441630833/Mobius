#!/usr/bin/env bash
# ==============================================================================
# Mobius - 苹果桌面端 / macOS (Desktop) 打包脚本快捷入口
# Note: Mobius Desktop IDE is built on VS Code OSS / Electron for macOS (Darwin).
# For mobile devices (iOS / iPadOS), use Web/Server mode (npm run web) via Safari.
# ==============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "\033[0;36m[Mobius]\033[0m 正在启动苹果桌面端 (macOS Desktop) 打包流程..."
echo -e "\033[0;33m[提示]\033[0m Mobius 桌面端基于 VS Code OSS / Electron 架构，支持 Apple Silicon (M1/M2/M3/M4 arm64) 与 Intel (x64) 桌面系统打包 (.dmg & .zip)。"
echo -e "       如需在 iPhone/iPad (iOS/iPadOS) 移动端访问 Mobius，请部署 Mobius Web 服务端并在 Safari 中访问。\n"

exec bash "$SCRIPT_DIR/package-mac.sh" "$@"
