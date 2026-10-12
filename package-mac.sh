#!/usr/bin/env bash
# ==============================================================================
# Mobius - 一键自动化打包 macOS 苹果桌面端安装包 (.dmg & .zip)
# One-click macOS desktop packaging script for Mobius
# ==============================================================================
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

echo -e "\n${CYAN}${BOLD}=====================================================${NC}"
echo -e "${CYAN}${BOLD}       Mobius - macOS 桌面端一键打包程序             ${NC}"
echo -e "${CYAN}${BOLD}=====================================================${NC}\n"

# 1. 检查操作系统
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo -e "${RED}[错误] 本脚本必须在 macOS (Darwin) 系统中运行。${NC}"
    echo -e "当前操作系统为: $(uname -s)"
    exit 1
fi

MAC_VER=$(sw_vers -productVersion 2>/dev/null || echo "")
MAC_ARCH=$(uname -m)
echo -e "运行平台: macOS ${MAC_VER} (${MAC_ARCH})\n"

# 2. 检查并自动补全 Git 子模块
echo -e "${CYAN}--> [1/4] 检查项目子模块 (Git submodules)...${NC}"
if [ ! -f "$ROOT/vscode/package.json" ] || [ ! -d "$ROOT/continue/extensions/vscode" ]; then
    echo -e "${YELLOW}[提示] 检测到子模块未初始化（vscode 或 continue 为空），正在自动拉取...${NC}"
    git -C "$ROOT" submodule update --init --recursive
    echo -e "${GREEN}[ OK ] 子模块初始化完成！${NC}"
else
    echo -e "${GREEN}[ OK ] 子模块已就绪。${NC}"
fi

# 3. 检查系统构建依赖 (Xcode Command Line Tools, Python 3)
echo -e "\n${CYAN}--> [2/4] 检查系统构建依赖与工具链...${NC}"
if ! command -v xcode-select >/dev/null 2>&1 || ! xcode-select -p >/dev/null 2>&1; then
    echo -e "${YELLOW}[警告] 未检测到 Xcode Command Line Tools，正在启动安装...${NC}"
    xcode-select --install || true
    echo -e "${YELLOW}请在弹出的系统对话框中确认安装 Xcode Command Line Tools 后重新运行本脚本。${NC}"
    exit 1
else
    echo -e "${GREEN}[ OK ] Xcode Command Line Tools 已就绪。${NC}"
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RED}[错误] 未检测到 Python 3 (用于编译原生模块)，请先安装：${NC}"
    echo -e "  brew install python@3.11"
    exit 1
else
    echo -e "${GREEN}[ OK ] Python 3: $(python3 --version 2>&1)${NC}"
fi

# 4. 检查 Node.js 环境 (需 >= 20，推荐 22.x)
echo -e "\n${CYAN}--> [3/4] 检查 Node.js 与 npm 环境...${NC}"
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
    if (( NODE_MAJOR < 20 )); then
        echo -e "${YELLOW}[警告] 当前 Node.js 版本 ($(node -v)) 过低，Mobius 需要 Node.js >= 20 (推荐 22.x)${NC}"
        if command -v brew >/dev/null 2>&1; then
            echo -e "${CYAN}通过 Homebrew 升级 Node.js...${NC}"
            brew install node@22
        else
            echo -e "${RED}[错误] 请通过 nvm 或安装包升级 Node.js 至 22.x LTS 后重试。${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}[ OK ] Node.js 版本: $(node -v), npm: v$(npm -v)${NC}"
    fi
else
    echo -e "${RED}[错误] 未检测到 Node.js，请先安装 Node.js 22 LTS:${NC}"
    echo -e "  brew install node@22"
    exit 1
fi

# 5. 执行完整编译与打包
echo -e "\n${CYAN}--> [4/4] 开始一键编译与打包 Mobius macOS 桌面版...${NC}"
chmod +x "$ROOT/scripts"/*.sh
bash "$ROOT/scripts/package-mac.sh" "$@"

echo -e "\n${GREEN}${BOLD}=====================================================${NC}"
echo -e "${GREEN}${BOLD}       Mobius macOS 桌面版打包成功！                 ${NC}"
echo -e "${GREEN}${BOLD}=====================================================${NC}"
echo -e "生成的安装文件保存在: ${CYAN}$ROOT/dist/${NC}"
ls -lh "$ROOT/dist"

echo -e "\n${YELLOW}${BOLD}安装说明：${NC}"
echo -e "1. 双击打开 ${CYAN}dist/Mobius-*-macOS-*.dmg${NC} 镜像文件；"
echo -e "2. 将 ${BOLD}Mobius.app${NC} 图标拖拽至 ${BOLD}Applications (应用程序)${NC} 文件夹即可完成安装！"
echo -e "3. 如需在终端直接运行或解压便携版，可解压 ${CYAN}dist/Mobius-*-darwin-*.zip${NC}。\n"
