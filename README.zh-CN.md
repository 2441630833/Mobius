<div align="center">

<img src="static/images/logo.png" alt="Mobius logo" width="140" />

# Mobius

### 会自我进化的智能体开发环境

**Mobius 越用越聪明。** 它会观察你的工作方式，把成功的操作沉淀成可复用的 **Skill（技能）**，再通过基于意图识别的推荐算法，自动为每个任务匹配最合适的 Skill——Agent 的能力会随着使用不断累积，而不是每次对话都从零开始。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.txt)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20%7C%20Linux%20%7C%20macOS%20%7C%20Web-blue)]()
[![Node](https://img.shields.io/badge/node-22.18%2B%20%7C%2024.x-brightgreen)]()
[![VS](https://img.shields.io/badge/VS-2022%20(v143)-purple)]()

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## 为什么是 Mobius

绝大多数 AI IDE 是无状态的：每次对话都是一个全新的 prompt，关掉标签页，"Agent"就把一切都忘了。

Mobius 不一样。它是一个 **ADE — Agentic Development Environment（智能体开发环境）**，围绕一个核心理念构建：

> AI 编程伙伴应当积累技能，而不只是消耗 token。

Mobius 在 [VS Code](https://github.com/microsoft/vscode) 分支的基础上，内置了 [Continue](https://github.com/continuedev/continue) 智能体引擎，并在其上增加了三层能力：

| 层级 | 作用 |
|---|---|
| 🧠 **自我总结 Skill** | 把 Agent 成功完成的任务，蒸馏成可复用、可版本化的 Skill（Markdown 操作手册 + 工具集）。完成的任务越多，Skill 库越丰富。 |
| 🎯 **意图 → Skill 推荐** | 混合 embedding + 词法检索，读懂用户请求的意图，自动把最相关的 Skill 预加载到 Agent 上下文中——无需手动输入 `/skill`。 |
| 🔄 **RSI** | *Recursive Self-Improvement，递归自我改进*。在**受控沙箱**内（隐藏的验收测试集、独立评估器、质量门禁、人工审批），让 Agent 提出对自身 Skill 的修改建议，自动验证，只有胜出的候选版本才会晋升。可运行的参考闭环见 [`rsi-test/`](rsi-test/README.md)。 |

最终效果：一个使用越久、Agent 能力越强的 IDE——你的每一次成功，都会变成它的本能。

---

## 特性一览

- **基于 VS Code OSS 分支**——完整的编辑器体验、扩展、快捷键、主题。
- **内置 Continue**——对话、内联编辑、`@codebase` 代码库索引、自动补全。
- **本地 embedding + OCR**——`@codebase` 使用进程内 `transformers.js`（`all-MiniLM-L6-v2`）；GLM-OCR 仍走内置 Ollama。对话走云端模型。
- **Skill 系统**——基于文件的 Skill，位于 `.agents/skills/`，支持热加载、通过 git 分享。
- **意图驱动的 Skill 匹配**——混合召回（embedding + 词法）针对每次提问给 Skill 打分并预加载 Top 匹配。
- **可插拔 agent harness（路线图）**——目前 Continue 是内置且唯一的 harness；路线图上会抽出一层 harness 抽象，让多个 agent 引擎（如 DeepSeek 的 agent harness）可以插拔共存、与 Continue 相辅相成，而不是替换。
- **多 Agent 工具超集**——默认同时提供 Continue 与 GitHub Copilot Chat 工具（`MOBIUS_SKIP_COPILOT=1` 可切换）。
- **路线图：RSI 闭环**——沙箱化自我改进，训练/验收数据隔离、5 项质量门禁、人工审批。

---

## 架构

```
Mobius/
├── vscode/                # Mobius 工作台（VS Code 分支，子模块）
├── continue/              # Continue 智能体引擎 → 链接到 vscode/extensions/continue
├── hermes-agent/          # 参考用的 agent loop / skills / memory（只读子模块）
├── rsi-test/              # RSI（递归自我改进）参考闭环
├── .agents/skills/        # ← Mobius Skill 存放位置（自动发现）
├── resources/ollama/      # 内置 Ollama 运行时（amd64 + arm64）—— 仅 OCR 模型（不含 embedding/对话）
├── scripts/               # 构建、启动、打包自动化脚本（PowerShell 与 Bash）
├── config/                # Continue + Mobius 配置模板
└── .env                   # AI 提供商密钥（同步到 ~/.continue/config.yaml）
```

与 VS Code / Continue 上游的 rebase 流程见 [REBASE.md](REBASE.md)。`hermes-agent` 是来自 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) 的只读参考子模块，用于对照其 agent loop、skills、memory 设计。

---

### 快速开始

#### Windows

```powershell
# 1. 克隆（含子模块）
git clone --recurse-submodules https://github.com/<your-org>/mobius.git
cd mobius

# 2. 配置 AI 提供商
copy .env.example .env
notepad .env   # 填入 OPENAI_API_KEY（或任意 OpenAI 兼容端点）

# 3. 检查工具链
npm run check

# 4. 首次构建（约 20–40 分钟：Continue + Mobius 工作台）
npm run install:continue
npm run build:vscode

# 5. 启动
npm start
```

#### Linux (Ubuntu / Debian)

Mobius 提供原生 Shell 自动化脚本与 Docker 容器化打包方案，可输出标准 Ubuntu `.deb` 安装包与便携 `.tar.gz` 归档。

##### 方式 1：Ubuntu 本机极简一键打包（全自动检测依赖与子模块）

拉完代码后，直接运行项目根目录下的打包脚本：

```bash
# 极简一键打包（自动检测并安装系统依赖、初始化子模块、编译打包全部搞定）
bash package-ubuntu.sh

# 或者使用 npm 脚本：
npm run package:ubuntu
# 或标准打包命令：
npm run package:linux
```

打包完成后，生成文件位于 `./dist/`：
- `dist/mobius_<version>_amd64.deb` （Ubuntu GUI 桌面版安装包）
- `dist/mobius-<version>-linux-x64.tar.gz` （便携绿色版）

直接在 Ubuntu 上安装运行：
```bash
sudo apt install ./dist/mobius_*_amd64.deb
```

##### 方式 2：Docker 容器一键打包（无需配置物理 Linux 环境）

无论在 Windows、macOS 还是 Linux 宿主机上，只要装有 Docker，即可一键生成 Ubuntu 安装包：

```bash
# Windows (PowerShell)
npm run docker:build:linux

# Linux / macOS (Bash)
npm run docker:build:linux:sh
# 或直接使用 Docker BuildKit:
DOCKER_BUILDKIT=1 docker build -f Dockerfile.ubuntu --target export -o dist .
```

##### 方式 3：GitHub Actions 自动构建

项目内置 `.github/workflows/build-ubuntu.yml`，在 GitHub 仓库中触发该工作流或推送 Release Tag，GitHub Actions 将自动在 Ubuntu 环境完成编译并上传 `.deb` 与 `.tar.gz` 安装包。

#### macOS / 苹果桌面系统 (Apple Silicon arm64 / Intel x64)

Mobius 完整支持 macOS 桌面端（Desktop IDE）的原生编译与打包，支持最新的 Apple Silicon (M1/M2/M3/M4 arm64) 以及 Intel (x64) 芯片架构，生成标准 `.dmg` 拖拽安装镜像与便携 `.zip` 压缩包。

##### 方式 1：macOS 本机极简一键打包

在 macOS 终端中，克隆代码后直接运行根目录打包脚本：

```bash
# 极简一键打包（自动检测 Xcode CLT、子模块、Node 环境并完成打包）：
bash package-mac.sh

# 亦可通过 npm 脚本调用：
npm run package:mac

# 指定架构打包（例如指定 Apple Silicon arm64 或 Intel x64）：
npm run package:mac:arm64
npm run package:mac:x64

# （兼容快捷别名，用户常说的 iOS 桌面 / 苹果系统打包）：
bash package-ios.sh
npm run package:ios
```

打包完成后，生成文件位于 `./dist/`：
- `dist/Mobius-<version>-macOS-<arch>.dmg`（标准 macOS 磁盘镜像安装包，含拖拽至 Applications 快捷方式）
- `dist/Mobius-<version>-darwin-<arch>.zip`（便携免安装绿色归档，完美保留 Mach-O 权限与软链接）
- `dist/SHA256SUMS.txt`（安全哈希校验和）

安装与运行方式：
```bash
# 双击打开 .dmg 镜像，直接将 Mobius.app 拖拽至 Applications 即可！
# 或在终端直接挂载：
hdiutil attach dist/Mobius-*-macOS-*.dmg
cp -R /Volumes/Mobius/Mobius.app /Applications/
hdiutil detach /Volumes/Mobius
```

##### 方式 2：macOS 源码构建与调试

```bash
# 仅编译工作台与扩展：
npm run build:mac

# 启动开发调试客户端：
npm run start:mac

# 或直接运行打包好的 Release 应用：
npm run start:mac -- --release
```

##### 方式 3：GitHub Actions 自动构建 macOS 安装包

项目内置 `.github/workflows/build-macos.yml`，配置了 Apple Silicon (`macos-14`) 与 Intel (`macos-13`) 双矩阵构建。当推送 Release Tag (`v*`) 或手动触发时，GitHub Actions 会自动编译并打包发布 macOS `.dmg` 与 `.zip` 安装包。

---

#### Web 部署与移动端支持 (iOS / iPadOS / Android / 浏览器远程访问)

> **关于 iOS / 移动端运行的说明**：由于 Apple iOS / iPadOS 系统的沙箱机制与限制，移动设备无法直接运行原生的 Electron 桌面应用。为此，Mobius 提供了**开箱即用的 Web 服务端部署模式**。任何 iPhone、iPad、Android 平板或远程轻薄本，均可通过浏览器无缝使用 Mobius 的全套智能体开发与编辑功能！

##### 启动 Web 终端服务端

在任意安装有 Node.js 或 Python 的机器（或云服务器）上运行：

```bash
# 启动 Mobius Web 服务端（默认端口 5173）：
npm run web

# 或指定自定义端口（Linux / macOS）：
WEB_PORT=8080 npm run web

# Windows PowerShell 指定端口：
$env:WEB_PORT='8080'; npm run web
```

启动后终端将输出访问链接：
```
Mobius web UI: http://localhost:5173/web/
```

##### 在 iOS / iPadOS (iPhone / iPad) 上获得原生 App 体验

1. 打开 iPad 或 iPhone 上的 **Safari 浏览器**，访问 `http://<服务器IP>:5173/web/`；
2. 点击 Safari 底部（或顶部工具栏）的 **"分享" (Share) 按钮**；
3. 选择 **"添加到主屏幕" (Add to Home Screen)** 并确认；
4. 桌面将生成精美的 Mobius 应用图标，点击后以**无边框全屏 PWA 原生应用模式**启动，支持触摸手势、移动端虚拟键盘与全功能 AI 对话！

---

### ☁️ GitHub Actions 云端全自动编译（无需本地配置，全平台覆盖）

如果你本地没有特定操作系统的开发环境（例如在 Windows 机器上想打包 macOS/iOS 桌面版，或在 Mac 上想打包 Windows 安装包），可以直接使用项目内置的 GitHub Actions 云端流水线全自动编译：

| 工作流文件 | 编译目标系统 | 输出安装包格式 | 云端 Runner |
|---|---|---|---|
| **`.github/workflows/build-all-platforms.yml`** | **macOS + Windows + Linux 三端并行** | `.dmg`, `.exe`, `.deb`, `.zip`, `.tar.gz` | `macos-14`, `macos-13`, `windows-2022`, `ubuntu-22.04` |
| **`.github/workflows/build-macos.yml`** | **macOS / 苹果桌面端** (Apple Silicon arm64 / Intel x64) | `Mobius-*-macOS-*.dmg`, `Mobius-*-darwin-*.zip` | `macos-14` (M系列), `macos-13` (Intel) |
| **`.github/workflows/build-windows.yml`** | **Windows 桌面端** (x64 / arm64) | `Mobius-Setup-*.exe`, `Mobius-*-win32-*.zip` | `windows-2022` |
| **`.github/workflows/build-ubuntu.yml`** | **Linux / Ubuntu 桌面端** (x64 / arm64) | `mobius_*_amd64.deb`, `mobius-*-linux-*.tar.gz` | `ubuntu-22.04` |

#### 如何一键触发云端打包与下载：

1. **手动一键触发编译 (Manual Trigger)**：
   - 打开 GitHub 项目仓库页面，点击顶部导航栏的 **"Actions"** 选项卡；
   - 在左侧工作流列表中选择 **"Build All Platforms (macOS, Windows, Linux)"**；
   - 点击右侧的 **"Run workflow"** 下拉框，选择分支并指定编译平台（可选择 `all` 编译全部平台，或单选 `macos` / `windows` / `linux`）；
   - 点击绿色 **"Run workflow"** 按钮启动云端编译。
2. **下载构建产物 (Artifacts)**：
   - 编译完成后，点击进入该次运行的详情页面；
   - 滚动到底部的 **Artifacts (构建产物)** 区域，即可直接下载对应系统的安装包（如 `mobius-macos-arm64`、`mobius-windows-x64`、`mobius-linux-x64`）。
3. **推送 Release Tag 全自动发布**：
   - 本地给仓库打版本标签并推送至 GitHub：
     ```bash
     git tag v1.0.0
     git push origin v1.0.0
     ```
   - GitHub Actions 将自动触发全平台并行编译，编译完成后自动汇总并将所有三端安装包发布到 GitHub Releases 页面，供团队或用户直接下载！

---

## 编译环境要求

Mobius 会编译原生 Node 模块（sqlite3、`@parcel/watcher`、LanceDB 等），并打包跨平台桌面应用。`npm run check`（Linux/macOS 下为 `scripts/check-prerequisites-*.sh`）会逐项校验工具链。

### 各平台支持矩阵与环境依赖

| 平台 / 系统 | 支持状态 | 编译工具链与必需组件 | 打包输出格式 |
|---|---|---|---|
| **Windows 10 / 11** (x64 / ARM64) | 官方支持（桌面端） | Visual Studio 2022 (MSVC v143 含 Spectre 缓解库)、Windows 10/11 SDK (`signtool`)、Inno Setup 6、PowerShell 5.1/7+ | 单文件安装器 (`.exe`)、免安装绿色版 |
| **Linux (Ubuntu / Debian)** (x64 / arm64) | 官方支持（桌面端 / Docker） | GCC / G++ (>= 11)、`pkg-config`、`libsecret-1-dev`、`libx11-dev`、`libxkbfile-dev`、`libkrb5-dev`、`fakeroot`、`dpkg-dev` | Debian 安装包 (`.deb`)、便携归档 (`.tar.gz`) |
| **macOS (苹果桌面系统)** (Apple Silicon arm64 / Intel x64) | 官方支持（桌面端） | Xcode Command Line Tools (`clang` / `make`)、`hdiutil`（系统自带）、`ditto`（系统自带） | 苹果磁盘镜像 (`.dmg`)、免安装归档 (`.zip`) |
| **iOS / iPadOS / 移动端** (Safari / PWA) | 官方支持（Web 服务端访问） | 服务端只需 Node.js 20+ 或 Python 3，客户端任意现代移动浏览器（Safari / Chrome） | PWA 全屏应用、Web IDE |
| **Node.js (通用)** | 所有平台必需 | **22.18+ LTS** 或 **24.x**（`vscode/.nvmrc` 锁定 24.15.0） | — |
| **Python 3 (通用)** | 所有平台必需 | 3.10+（`node-gyp` 编译原生插件使用，必须在 `PATH` 中） | — |
| **Git (通用)** | 所有平台必需 | 2.40+（需完整支持子模块递归克隆） | — |

### Visual Studio 2022 — 工作负载与单个组件

在 **Visual Studio Installer → 修改** 中启用：

**"工作负载"标签页**
- ☑ **使用 C++ 的桌面开发**

**"单个组件"标签页**（按名称搜索——普通版与 Spectre 缓解版**都要装**）
- ☑ **MSVC v143 - VS 2022 C++ x64/x86 生成工具**
- ☑ **MSVC v143 - VS 2022 C++ x64/x86 Spectre 缓解生成工具** *（必需——部分原生模块链接 Spectre 缓解版 CRT）*
- ☑ **MSVC v143 - VS 2022 C++ ARM64 生成工具** *（仅在构建 `package:arm64` 时需要）*
- ☑ **MSVC v143 - VS 2022 C++ ARM64 Spectre 缓解生成工具** *（仅在构建 `package:arm64` 时需要）*
- ☑ **Windows 11 SDK**（10.0.22621.0 或更高）——一般会自动勾选

> ⚠️ v143 x64/x86 的普通版与 Spectre 缓解版两个组件都必须勾选。虽然 `Directory.Build.props` 为 node-gyp 插件禁用了 Spectre 缓解，但部分原生依赖仍要求磁盘上存在 Spectre 缓解库。

> 💡 装完后运行 `npm run check`，它会校验 Node、C++ 工具集、Windows SDK（`signtool`）、Python，并对每个失败项给出精确修复指令。

### 通过 `winget` 安装（可选）

```powershell
# Visual Studio 2022 Community + C++ 工作负载 + Spectre 库
winget install Microsoft.VisualStudio.2022.Community `
  --override "--quiet --wait --add Microsoft.VisualStudio.Workload.NativeDesktop `
  --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64.Spectre `
  --add Microsoft.VisualStudio.Component.Windows11SDK.22621"

# Node 24 LTS
winget install OpenJS.NodeJS.LTS

# Python 3.12
winget install Python.Python.3.12

# Inno Setup 6（打包安装器用）
winget install JRSoftware.InnoSetup
```

### 常见构建问题

| 症状 | 解决方法 |
|---|---|
| `@parcel/watcher` / `node-gyp` 报 `MSBxxx` | C++ 工具集缺失。安装"使用 C++ 的桌面开发"工作负载，删除 `vscode/node_modules` 后重新构建。 |
| `MSB8040：需要 Spectre 缓解库` | 缺少"MSVC v143 - VS 2022 C++ x64/x86 Spectre 缓解生成工具"单个组件。通过 Visual Studio Installer 安装，然后删除 `vscode/node_modules` 重新构建。 |
| 首次下载 Electron 时找不到 `signtool` | 安装 Windows 10/11 SDK（通过 VS Installer，或 `winget install Microsoft.WindowsSDK.10.0.22621`）。 |
| `install:continue` 中出现 LanceDB `EBUSY` 临时文件警告 | 无害；Continue 的 prepackage 步骤在 Windows 上会遗留被锁定的临时文件。 |
| 从 `github.com` 下载 sqlite3 超时 | 重新运行 `npm run install:continue` —— 脚本会自动切换到镜像或本地编译。 |
| `nvm-windows` 没有 Node 24.15.0 | 使用 Node 22.18+（`nvm install 22.18.0`），或从 nodejs.org 安装 Node 24 LTS。 |

---

## AI 配置

有两种方式接入模型，任选其一：

### 方式一：在 Mobius 内通过 Model picker 添加（无需编辑文件）

1. 启动 Mobius（`npm start`）。
2. 打开 Continue 侧边栏，点击聊天面板顶部的 **Model picker（模型选择器）**。
3. 选择 **Add provider（添加提供商）** → 选择 **OpenAI**（或任意 OpenAI 兼容提供商：DeepSeek、硅基流动、Ollama、Azure OpenAI 等）。
4. 填入 Base URL、API Key、模型名称，保存即可。

配置会写入 `~/.continue/config.yaml`，立即生效，无需重启。

### 方式二：通过 `.env` 配置（适合团队协作 / 需要版本管理）

编辑 `.env`：

```env
AI_ACTIVE_PROFILE=openai

[openai]
AI_PROVIDER=openai
AI_BASE_URL=https://api.openai.com/v1
AI_API_KEY=sk-...
AI_MODEL=gpt-4o
```

然后同步到 Continue：

```powershell
npm run sync:config
```

任何 OpenAI 兼容端点都可以（DeepSeek、硅基流动、Ollama、Azure OpenAI 等）。如需多套配置，添加额外的 `[name]` 段即可——运行时在模型选择器里切换。

---

## 本地 embedding + 内置 Ollama OCR

- **`@codebase` 代码库 embedding**：进程内 `transformers.js`（`all-MiniLM-L6-v2`），与 Cursor 同类做法——不再走 Ollama，多 Agent 并发时不会抢占同一个 llama.cpp。
- **图像 OCR**：内置 Ollama `glm-ocr`——当你在 Agent 中附加图片时，Mobius 先在本地跑 OCR，再把 `<ocr-extract>` 文本注入对话

对话本身始终使用 `.env` 中配置的云端模型；本地不跑对话模型。

```powershell
npm run bundle:ollama    # 下载 amd64 + arm64 运行时与 glm-ocr
npm run verify:ollama    # 发布前校验 Ollama OCR bundle
npm run verify:minilm    # 冒烟测试内置 MiniLM ONNX embedding
```

若 GitHub 下载被墙，可把本地 zip 路径指给脚本：

```powershell
$env:OLLAMA_ZIP_PATH_AMD64 = "D:\Downloads\ollama-windows-amd64.zip"
$env:OLLAMA_ZIP_PATH_ARM64 = "D:\Downloads\ollama-windows-arm64.zip"
npm run bundle:ollama
```

---

## 常用命令

### 开发

| 命令 | 用途 |
|---|---|
| `npm start` | 启动 Mobius（开发模式） |
| `npm run compile` | 工作台快速增量 esbuild 转译 |
| `npm run install:continue` | 构建 Continue 扩展（Windows 兼容） |
| `npm run build:vscode` | 完整构建 Mobius 工作台 |
| `npm run rebuild` | 删除 `vscode/node_modules` 后从零重建 |
| `npm run check` | 校验 Node、C++ 工具集、SDK、Python、Continue 构建 |
| `npm run sync:config` | 把 `.env` 推送到 `~/.continue/config.yaml` |
| `npm run web` | 启动 `web/` 前端 |

### 打包（Windows 安装器）

| 命令 | 产物 | 适用场景 |
|---|---|---|
| `npm run package` | `vscode/.build/win32-x64/user-setup/MobiusSetup.exe` | 日常增量发布 |
| `npm run package:full` | 完整干净的发布树 + 安装器 | 首次构建或干净发布 |
| `npm run package:system` | 系统级安装器（`Program Files`，需管理员） | 企业部署 |
| `npm run package:arm64` | ARM64 用户安装器 | Surface / 骁龙设备 |
| `npm run package:setup` | 仅重建安装器（复用现有客户端树） | 只改了 Inno Setup 脚本 |
| `npm run package:fast` | 跳过 Ollama 重新下载 | 改代码、不改模型时迭代 |

### 关键环境变量

| 变量 | 作用 |
|---|---|
| `MOBIUS_SKIP_COPILOT=1` | 开发启动时不加载 Copilot Chat（只用 Continue 的 Agent 工具） |
| `PACKAGE_FULL=1` | 打包时强制完整重建 `vscode-*-min` |
| `SKIP_OLLAMA_BUNDLE=1` | 跳过 Ollama 重新下载（仍会校验） |
| `SKIP_VSCODE_BUILD=1` | 跳过 esbuild，复用现有客户端树 |
| `SKIP_CONTINUE_BUILD=1` | 跳过 Continue 扩展重建 |
| `ELECTRON_MIRROR` | Electron 下载镜像（默认 `npmmirror.com`） |

---

## Skill 与意图匹配

Skill 是 `.agents/skills/` 下的文件夹（Markdown + 脚本）。每个 Skill 声明自己的适用场景；Mobius 的混合检索器（embedding + 词法）针对当前请求给 Skill 打分，并把得分最高的几个预加载进 Agent 的系统提示词。

```
.agents/skills/
└── auto/
    └── debug-jenkins-container-deploy/
        ├── SKILL.md
        └── ...
```

- Skill 是**纯文本文件**——可版本化、可 fork、可通过 git 分享。
- Agent 在完成任务后可以**写出新的 Skill**（自我总结）。
- 匹配过程在本地留有日志，可查看某个 Skill **为什么**被选中。

在对话框输入 `/skills` 可浏览当前可用的 Skill。

---

## 可插拔 Agent Harness（路线图）

目前 Mobius 内置的 agent harness 只有 **Continue 一个**——它是编译进去的，暂时不可替换。路线图上会抽出一层薄薄的 harness 抽象，让多个 agent 引擎共存：

```
┌─────────────────────────────────────────────┐
│              Mobius workbench                │
├─────────────────────────────────────────────┤
│   Skill 引擎 · 意图匹配 · 工具集            │
├─────────────────────────────────────────────┤
│            Harness 注册表（可插拔）          │
│   ┌──────────────┐   ┌──────────────────┐   │
│   │   Continue   │   │ DeepSeek harness │   │
│   │  （内置）    │   │   （路线图）     │   │
│   └──────────────┘   └──────────────────┘   │
└─────────────────────────────────────────────┘
```

- **Continue 仍是默认**——对话、内联编辑、`@codebase`、自动补全，以及已有的全部 Skill 照常工作。
- **DeepSeek harness 将作为同级引擎加入**——不是 fork 替换，而是作为对等的引擎并存，用户可以按任务（或按模型）切换到更合适的推理风格。
- **Skill 与工具共享**——所有 harness 读取同一份 `.agents/skills/` 库与同一套工具超集，因此无论哪个引擎执行，自我总结的 Skill 都会持续累积。
- **Harness 按会话选择**——通过模型选择器 / 命令面板切换引擎；未来 RSI 闭环还可以评估在某类任务上哪个 harness 表现更好。

这样 Mobius 在架构层面保持 harness 无关，而 Continue 在今天仍是稳定、开箱即用的默认选项。

---

## RSI — 递归自我改进

> 可运行的参考闭环位于 [`rsi-test/`](rsi-test/README.md)。与实时 Mobius Skill 引擎（混合召回路由、`ILanguageModelsService` 提议器、`.agents/skills` 冠军存储）的生产级集成已列入路线图。

RSI 闭环让 Agent **在受控沙箱内**改进自己的 Skill：

```
Champion Skill ──▶ Agent（执行任务）
                       │
                       ▼
                 Proposer（分析失败，起草候选 Skill 修改）
                       │
                       ▼
                 Evaluator（在隐藏的验收集上给候选打分）
                       │
                       ▼
                 Gate（5 项门禁：无回归、准确率不下降、
                       无解析错误、净增益为正、无分类坍塌）
                       │
                       ▼
                 人工审批 ──▶ 新 Champion
```

三条铁律保证安全：

1. Proposer 永远看不到验收（测试）数据。
2. Agent 不能修改 Evaluator 或 Gate。
3. 每次只改一小步，必须独立验证，可随时回滚。

完整设计见 [`rsi-test/README.md`](rsi-test/README.md)。试运行：

```powershell
npm run rsi:test        # 7/7 —— 证明闭环是安全的
npm run rsi:approve     # 提议 + 门禁 + 审批（离线脚本提议器）
npm run rsi:rollback    # 回滚上一次晋升
```

---

## 参与贡献

欢迎贡献——尤其是新的 Skill、把 PowerShell 构建脚本移植到 Linux/macOS（底层 VS Code OSS 已支持，只需移植 `scripts/*.ps1`、Inno Setup 打包与 Ollama 捆绑逻辑），以及 RSI 安全方向的工作。

1. Fork 并使用 `--recurse-submodules` 克隆。
2. 运行 `npm run check`，修复任何报错。
3. 创建分支、修改代码、运行 `npm run compile` 验证。
4. 向 `main` 发起 PR。

提交贡献即表示你同意以 MIT 许可证授权你的贡献。

---

## 开源协议

- **Mobius** — [MIT](LICENSE.txt)
- **VS Code**（fork 基座）— MIT
- **Continue** — Apache 2.0
- **Hermes Agent**（参考子模块）— 见其仓库
- **Ollama**（内置运行时）— MIT

内置的 Ollama 模型与第三方扩展遵循其各自上游许可证。

---

Mobius 支持四种交互模式：**Agent**（通用软件开发）、**Game**（Godot 游戏开发）、**Chip**（FPGA 采样器设计）与 **PPT**（AI 演示文稿与幻灯片生成）。