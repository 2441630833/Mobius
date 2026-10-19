#!/usr/bin/env bash
# ==============================================================================
# Mobius - 一键自动化打包 Ubuntu GUI 桌面安装包 (.deb & .tar.gz)
# One-click Ubuntu packaging script for Mobius
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
echo -e "${CYAN}${BOLD}       Mobius - Ubuntu 本地一键打包程序              ${NC}"
echo -e "${CYAN}${BOLD}=====================================================${NC}\n"

# 1. 检查操作系统
if [[ "$(uname -s)" != "Linux" ]]; then
    echo -e "${RED}[错误] 本脚本必须在 Linux (Ubuntu / Debian) 系统中运行。${NC}"
    exit 1
fi

# 2. 检查并自动补全 Git 子模块
echo -e "${CYAN}--> [1/4] 检查项目子模块 (Git submodules)...${NC}"
if [ ! -f "$ROOT/vscode/package.json" ] || [ ! -d "$ROOT/continue/extensions/vscode" ]; then
    echo -e "${YELLOW}[提示] 检测到子模块未初始化（vscode 或 continue 为空），正在自动拉取...${NC}"
    git -C "$ROOT" submodule update --init --recursive
    echo -e "${GREEN}[ OK ] 子模块初始化完成！${NC}"
else
    echo -e "${GREEN}[ OK ] 子模块已就绪。${NC}"
fi

# 3. 检查系统依赖包
echo -e "\n${CYAN}--> [2/4] 检查系统构建依赖...${NC}"
REQUIRED_PKGS=(
    "build-essential"
    "pkg-config"
    "git"
    "python3"
    "curl"
    "libsecret-1-dev"
    "libx11-dev"
    "libxkbfile-dev"
    "libkrb5-dev"
    "fakeroot"
    "dpkg-dev"
    "tar"
    "xz-utils"
)

MISSING_PKGS=()
for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" >/dev/null 2>&1; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}[警告] 发现以下缺失的系统依赖:${NC} ${MISSING_PKGS[*]}"
    echo -e "${CYAN}正在尝试自动安装缺失依赖 (需要 sudo 权限)...${NC}"
    if command -v sudo >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y "${MISSING_PKGS[@]}"
        echo -e "${GREEN}[ OK ] 系统依赖安装完成！${NC}"
    else
        echo -e "${RED}[错误] 未检测到 sudo 命令，请以 root 身份运行：${NC}"
        echo -e "  apt-get update && apt-get install -y ${MISSING_PKGS[*]}"
        exit 1
    fi
else
    echo -e "${GREEN}[ OK ] 系统依赖全部就绪。${NC}"
fi

# 4. 检查 Node.js 环境 (需 >= 20，推荐 22.x)
echo -e "\n${CYAN}--> [3/4] 检查 Node.js 与 npm 环境...${NC}"
NEED_NODE_INSTALL=0
if command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node -v | sed 's/v//' | cut -d. -f1)
    if (( NODE_MAJOR < 20 )); then
        echo -e "${YELLOW}[警告] 当前 Node.js 版本 ($(node -v)) 过低，Mobius 需要 Node.js >= 20 (推荐 22.x)${NC}"
        NEED_NODE_INSTALL=1
    else
        echo -e "${GREEN}[ OK ] Node.js 版本: $(node -v), npm: v$(npm -v)${NC}"
    fi
else
    echo -e "${YELLOW}[提示] 未检测到 Node.js。${NC}"
    NEED_NODE_INSTALL=1
fi

if [ "$NEED_NODE_INSTALL" -eq 1 ]; then
    echo -e "${CYAN}正在从 NodeSource 自动配置并安装 Node.js 22 LTS...${NC}"
    curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
    sudo apt-get install -y nodejs
    echo -e "${GREEN}[ OK ] Node.js 22 安装成功！当前版本: $(node -v)${NC}"
fi

# 5. 执行完整编译与打包
echo -e "\n${CYAN}--> [4/4] 开始一键编译与打包 Mobius...${NC}"
chmod +x "$ROOT/scripts"/*.sh
bash "$ROOT/scripts/package-linux.sh" "$@"

echo -e "\n${GREEN}${BOLD}=====================================================${NC}"
echo -e "${GREEN}${BOLD}       Mobius Ubuntu 打包成功！                       ${NC}"
echo -e "${GREEN}${BOLD}=====================================================${NC}"
echo -e "生成的安装文件保存在: ${CYAN}$ROOT/dist/${NC}"
ls -lh "$ROOT/dist"

echo -e "\n${YELLOW}${BOLD}安装说明：${NC}"
echo -e "在 Ubuntu 终端运行以下命令即可安装并打开 Mobius GUI 桌面版："
echo -e "  ${CYAN}sudo apt install ./dist/mobius_*.deb${NC}"
echo -e "安装后直接在应用列表搜索 ${BOLD}Mobius${NC} 点击图标即可打开！\n"
