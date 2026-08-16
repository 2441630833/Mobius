<div align="center">

<img src="static/images/logo.png" alt="Mobius logo" width="140" />

# Mobius

### A self-evolving agentic development environment

**Mobius gets smarter the more you use it.** It observes how you work, distills successful operations into reusable **Skills**, and then automatically matches the most relevant Skill to each task through an intent-recognition based recommendation algorithm — the Agent's capabilities accumulate with use, instead of starting from zero with every conversation.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE.txt)
[![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11%20(x64%20%2F%20ARM64)-blue)]()
[![Node](https://img.shields.io/badge/node-22.18%2B%20%7C%2024.x-brightgreen)]()
[![VS](https://img.shields.io/badge/VS-2022%20(v143)-purple)]()

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## Why Mobius

Most AI IDEs are stateless: every conversation is a brand-new prompt, and when you close the tab, the "Agent" forgets everything.

Mobius is different. It is an **ADE — Agentic Development Environment** — built around one core idea:

> An AI coding partner should accumulate skills, not just consume tokens.

Mobius is built on a [VS Code](https://github.com/microsoft/vscode) fork with the [Continue](https://github.com/continuedev/continue) agent engine built in, and adds three layers on top of it:

| Layer | Purpose |
|---|---|
| 🧠 **Self-summarizing Skills** | Distills successfully completed Agent tasks into reusable, versionable Skills (Markdown playbooks + tool sets). The more tasks you complete, the richer your Skill library becomes. |
| 🎯 **Intent → Skill recommendation** | Hybrid embedding + lexical retrieval that reads the intent of your request and automatically preloads the most relevant Skills into the Agent's context — no need to type `/skill` manually. |
| 🔄 **RSI (coming soon)** | *Recursive Self-Improvement*. Inside a **controlled sandbox** (hidden acceptance test set, independent evaluator, quality gates, human approval), let the Agent propose changes to its own Skills, validate them automatically, and only promote winning candidate versions. See the reference implementation in [`rsi-test/`](rsi-test/README.md). |

The end result: an IDE whose Agent grows more capable the longer you use it — every success you have becomes its instinct.

---

## Feature Highlights

- **Built on the VS Code OSS fork** — full editor experience, extensions, keybindings, themes.
- **Continue built in** — chat, inline editing, `@codebase` repository indexing, autocomplete.
- **Local Ollama built in** — embedding (`nomic-embed-text`) and GLM-OCR image preprocessing run fully offline; chat still uses cloud models.
- **Skill system** — file-based Skills in `.agents/skills/`, hot-reloadable and shareable via git.
- **Intent-driven Skill matching** — hybrid recall (embedding + lexical) scores Skills for every query and preloads the top matches.
- **Pluggable agent harness (roadmap)** — Continue is currently the built-in and only harness; the roadmap extracts a thin harness abstraction so multiple agent engines (such as DeepSeek's agent harness) can coexist as plugins that complement Continue, rather than replacing it.
- **Multi-agent tool superset** — both Continue and GitHub Copilot Chat tools are provided by default (`MOBIUS_SKIP_COPILOT=1` to toggle).
- **Roadmap: RSI loop** — sandboxed self-improvement with training/acceptance data isolation, 5 quality gates, and human approval.

---

## Architecture

```
Mobius/
├── vscode/                # Mobius workbench (VS Code fork, submodule)
├── continue/              # Continue agent engine → linked to vscode/extensions/continue
├── hermes-agent/          # Reference agent loop / skills / memory (read-only submodule)
├── rsi-test/              # RSI (Recursive Self-Improvement) reference loop
├── .agents/skills/        # ← Where Mobius Skills live (auto-discovered)
├── resources/ollama/      # Bundled Ollama runtime (amd64 + arm64) + models
├── scripts/               # Build / launch / packaging automation scripts (PowerShell)
├── config/                # Continue + Mobius configuration templates
└── .env                   # AI provider keys (synced to ~/.continue/config.yaml)
```

See [REBASE.md](REBASE.md) for the rebase workflow against the VS Code / Continue upstreams. `hermes-agent` is a read-only reference submodule from [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent), used to study its agent loop, skills, and memory design.

---

## Quick Start

> 🪟 **Windows-only for now.** Mobius can currently only be built and run on Windows 10/11 (x64 and ARM64). All build scripts are PowerShell, packaging uses Inno Setup, and the bundled Ollama is the Windows build. Linux/macOS support is on the roadmap — the underlying VS Code OSS is already cross-platform; help port the scripts by following the [Contributing](#contributing) section.

```powershell
# 1. Clone (including submodules)
git clone --recurse-submodules https://github.com/<your-org>/mobius.git
cd mobius

# 2. Configure the AI provider
copy .env.example .env
notepad .env   # fill in OPENAI_API_KEY (or any OpenAI-compatible endpoint)

# 3. Verify the toolchain
npm run check

# 4. First build (~20–40 minutes: Continue + Mobius workbench)
npm run install:continue
npm run build:vscode

# 5. Launch
npm start
```

`npm start` launches Mobius with Continue preloaded. Open the Continue sidebar to chat, edit, and index your codebase.

---

## Build Environment Requirements

Mobius compiles native Node modules (sqlite3, `@parcel/watcher`, LanceDB, etc.) and packages an Electron app. `npm run check` validates each item in the toolchain below.

### Required Software

| Component | Version | Notes |
|---|---|---|
| **Windows** | 10 / 11 x64 or ARM64 | **The only currently supported build and run platform.** All build scripts are PowerShell (`.ps1`), packaging uses Inno Setup, and the bundled Ollama runtime only includes Windows builds. The underlying VS Code OSS is cross-platform, but Mobius's build toolchain has not yet been ported to Linux/macOS — community contributions welcome. |
| **Visual Studio 2022** | Any edition (Community / Pro / Enterprise) with **MSVC v143** | Required to compile native C++ modules. Both the regular and **Spectre-mitigated** C++ x64/x86 libraries for v143 must be installed (details below). |
| **"Desktop development with C++" workload** | — | Install via Visual Studio Installer. |
| **Windows 10/11 SDK** | Latest (10.0.22621 or newer) | The Electron download stage needs `signtool`; usually installed with the C++ workload. |
| **Node.js** | **22.18+ LTS** or **24.x** | `vscode/.nvmrc` pins 24.15.0. Use `nvm install 24.15.0 && nvm use 24.15.0`. 22.18+ also works. |
| **Python** | 3.10+ | Used by `node-gyp` to compile native addons; must be on `PATH`. |
| **Git** | 2.40+ | Submodule support required. |
| **Inno Setup 6** | 6.2+ | Only needed when building the Windows installer (`npm run package`). |
| **PowerShell** | 5.1 or 7.x | All build scripts are PowerShell. |

### Visual Studio 2022 — Workloads and Individual Components

In **Visual Studio Installer → Modify**, enable:

**"Workloads" tab**
- ☑ **Desktop development with C++**

**"Individual components" tab** (search by name — install **both** the regular and Spectre-mitigated versions)
- ☑ **MSVC v143 - VS 2022 C++ x64/x86 build tools**
- ☑ **MSVC v143 - VS 2022 C++ x64/x86 Spectre-mitigated build tools** *(required — some native modules link against the Spectre-mitigated CRT)*
- ☑ **MSVC v143 - VS 2022 C++ ARM64 build tools** *(only needed when building `package:arm64`)*
- ☑ **MSVC v143 - VS 2022 C++ ARM64 Spectre-mitigated build tools** *(only needed when building `package:arm64`)*
- ☑ **Windows 11 SDK** (10.0.22621.0 or newer) — usually selected automatically

> ⚠️ Both the regular and Spectre-mitigated v143 x64/x86 components must be selected. Although `Directory.Build.props` disables Spectre mitigation for node-gyp addons, some native dependencies still require the Spectre-mitigated libraries to exist on disk.

> 💡 After installation, run `npm run check` — it validates Node, the C++ toolset, the Windows SDK (`signtool`), and Python, and gives precise fix instructions for each failure.

### Installing via `winget` (optional)

```powershell
# Visual Studio 2022 Community + C++ workload + Spectre libraries
winget install Microsoft.VisualStudio.2022.Community `
  --override "--quiet --wait --add Microsoft.VisualStudio.Workload.NativeDesktop `
  --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
  --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64.Spectre `
  --add Microsoft.VisualStudio.Component.Windows11SDK.22621"

# Node 24 LTS
winget install OpenJS.NodeJS.LTS

# Python 3.12
winget install Python.Python.3.12

# Inno Setup 6 (for packaging the installer)
winget install JRSoftware.InnoSetup
```

### Common Build Issues

| Symptom | Fix |
|---|---|
| `@parcel/watcher` / `node-gyp` reports `MSBxxx` | The C++ toolset is missing. Install the "Desktop development with C++" workload, delete `vscode/node_modules`, and rebuild. |
| `MSB8040: Spectre-mitigated libraries required` | The "MSVC v143 - VS 2022 C++ x64/x86 Spectre-mitigated build tools" individual component is missing. Install it via Visual Studio Installer, then delete `vscode/node_modules` and rebuild. |
| `signtool` not found on first Electron download | Install the Windows 10/11 SDK (via VS Installer, or `winget install Microsoft.WindowsSDK.10.0.22621`). |
| LanceDB `EBUSY` temp-file warnings during `install:continue` | Harmless; Continue's prepackage step leaves locked temp files on Windows. |
| sqlite3 download from `github.com` times out | Re-run `npm run install:continue` — the script automatically switches to a mirror or builds locally. |
| `nvm-windows` doesn't have Node 24.15.0 | Use Node 22.18+ (`nvm install 22.18.0`), or install Node 24 LTS from nodejs.org. |

---

## AI Configuration

There are two ways to connect a model — choose either one:

### Option 1: Add it in Mobius via the Model picker (no file editing)

1. Launch Mobius (`npm start`).
2. Open the Continue sidebar and click the **Model picker** at the top of the chat panel.
3. Select **Add provider** → choose **OpenAI** (or any OpenAI-compatible provider: DeepSeek, SiliconFlow, Ollama, Azure OpenAI, etc.).
4. Fill in Base URL, API Key, and model name, then save.

The configuration is written to `~/.continue/config.yaml` and takes effect immediately, no restart needed.

### Option 2: Configure via `.env` (for team collaboration / version management)

Edit `.env`:

```env
AI_ACTIVE_PROFILE=openai

[openai]
AI_PROVIDER=openai
AI_BASE_URL=https://api.openai.com/v1
AI_API_KEY=sk-...
AI_MODEL=gpt-4o
```

Then sync to Continue:

```powershell
npm run sync:config
```

Any OpenAI-compatible endpoint works (DeepSeek, SiliconFlow, Ollama, Azure OpenAI, etc.). For multiple configurations, add extra `[name]` sections — switch between them at runtime in the model picker.

---

## Bundled Ollama (offline embedding + OCR)

Mobius ships Ollama inside the installer so the following two features work without a separate install:

- **`@codebase` repository embedding**: `nomic-embed-text`
- **Image OCR**: `glm-ocr` — when you attach an image in the Agent, Mobius first runs OCR locally, then injects the `<ocr-extract>` text into the conversation

Chat itself always uses the cloud model configured in `.env`; no chat model runs locally.

```powershell
npm run bundle:ollama    # download amd64 + arm64 runtimes and models
npm run verify:ollama    # validate the bundle before release
```

If GitHub downloads are blocked, point the script at local zip files:

```powershell
$env:OLLAMA_ZIP_PATH_AMD64 = "D:\Downloads\ollama-windows-amd64.zip"
$env:OLLAMA_ZIP_PATH_ARM64 = "D:\Downloads\ollama-windows-arm64.zip"
npm run bundle:ollama
```

---

## Common Commands

### Development

| Command | Purpose |
|---|---|
| `npm start` | Launch Mobius (development mode) |
| `npm run compile` | Fast incremental esbuild transpile of the workbench |
| `npm run install:continue` | Build the Continue extension (Windows-compatible) |
| `npm run build:vscode` | Full build of the Mobius workbench |
| `npm run rebuild` | Rebuild from scratch after deleting `vscode/node_modules` |
| `npm run check` | Validate Node, C++ toolset, SDK, Python, Continue build |
| `npm run sync:config` | Push `.env` to `~/.continue/config.yaml` |
| `npm run web` | Start the `web/` frontend |

### Packaging (Windows installer)

| Command | Output | Use case |
|---|---|---|
| `npm run package` | `vscode/.build/win32-x64/user-setup/MobiusSetup.exe` | Daily incremental release |
| `npm run package:full` | Complete clean release tree + installer | First build or clean release |
| `npm run package:system` | System-level installer (`Program Files`, requires admin) | Enterprise deployment |
| `npm run package:arm64` | ARM64 user installer | Surface / Snapdragon devices |
| `npm run package:setup` | Rebuild only the installer (reuse existing client tree) | Only changed Inno Setup scripts |
| `npm run package:fast` | Skip re-downloading Ollama | Iterating on code without changing models |

### Key Environment Variables

| Variable | Purpose |
|---|---|
| `MOBIUS_SKIP_COPILOT=1` | Don't load Copilot Chat on dev launch (use only Continue's Agent tools) |
| `PACKAGE_FULL=1` | Force a full rebuild of `vscode-*-min` when packaging |
| `SKIP_OLLAMA_BUNDLE=1` | Skip re-downloading Ollama (still validated) |
| `SKIP_VSCODE_BUILD=1` | Skip esbuild and reuse the existing client tree |
| `SKIP_CONTINUE_BUILD=1` | Skip rebuilding the Continue extension |
| `ELECTRON_MIRROR` | Electron download mirror (default `npmmirror.com`) |

---

## Skills and Intent Matching

Skills are folders under `.agents/skills/` (Markdown + scripts). Each Skill declares the scenarios it applies to; Mobius's hybrid retriever (embedding + lexical) scores Skills against the current request and preloads the top few into the Agent's system prompt.

```
.agents/skills/
└── auto/
    └── debug-jenkins-container-deploy/
        ├── SKILL.md
        └── ...
```

- Skills are **plain-text files** — versionable, forkable, and shareable via git.
- After completing a task, the Agent can **write a new Skill** (self-summarization).
- The matching process leaves logs locally, so you can inspect **why** a Skill was selected.

Type `/skills` in the chat box to browse the currently available Skills.

---

## Pluggable Agent Harness (roadmap)

Mobius currently ships with a single built-in agent harness: **Continue**. It is compiled in and not yet replaceable. The roadmap extracts a thin harness abstraction so multiple agent engines can coexist:

```
┌─────────────────────────────────────────────┐
│              Mobius workbench                │
├─────────────────────────────────────────────┤
│   Skill engine · intent matching · tool set │
├─────────────────────────────────────────────┤
│            Harness registry (pluggable)      │
│   ┌──────────────┐   ┌──────────────────┐   │
│   │   Continue   │   │ DeepSeek harness │   │
│   │  (built-in)  │   │    (roadmap)     │   │
│   └──────────────┘   └──────────────────┘   │
└─────────────────────────────────────────────┘
```

- **Continue remains the default** — chat, inline editing, `@codebase`, autocomplete, and all existing Skills continue to work as before.
- **DeepSeek harness will join as a sibling engine** — not a fork replacement, but a peer engine that coexists, letting users switch to a more suitable reasoning style per task (or per model).
- **Skills and tools are shared** — all harnesses read the same `.agents/skills/` library and the same tool superset, so self-summarized Skills keep accumulating regardless of which engine executes.
- **Harness is selected per session** — switch engines via the model picker / command palette; in the future the RSI loop can also evaluate which harness performs better on a given class of task.

This keeps Mobius harness-agnostic at the architecture level, while Continue remains the stable, out-of-the-box default today.

---

## RSI — Recursive Self-Improvement (roadmap)

> ⚠️ Under active development. The reference loop lives in [`rsi-test/`](rsi-test/README.md); production-grade integration with Mobius Skills is on the roadmap.

The RSI loop lets the Agent improve its own Skills **inside a controlled sandbox**:

```
Champion Skill ──▶ Agent (executes the task)
                       │
                       ▼
                 Proposer (analyzes failures, drafts candidate Skill edits)
                       │
                       ▼
                 Evaluator (scores candidates on a hidden acceptance set)
                       │
                       ▼
                 Gate (5 gates: no regression, accuracy not down,
                       no parse errors, net positive gain, no class collapse)
                       │
                       ▼
                 Human approval ──▶ New Champion
```

Three iron rules keep it safe:

1. The Proposer never sees the acceptance (test) data.
2. The Agent cannot modify the Evaluator or the Gate.
3. Only one small step at a time, independently validated, rollbackable at any time.

See [`rsi-test/README.md`](rsi-test/README.md) for the full design and a runnable Next.js visualization.

---

## Contributing

Contributions welcome — especially new Skills, porting the PowerShell build scripts to Linux/macOS (the underlying VS Code OSS already supports them; only `scripts/*.ps1`, the Inno Setup packaging, and the Ollama bundling logic need porting), and work on the RSI safety direction.

1. Fork and clone with `--recurse-submodules`.
2. Run `npm run check` and fix any errors.
3. Create a branch, make changes, and verify with `npm run compile`.
4. Open a PR against `main`.

By submitting a contribution you agree to license it under the MIT License.

---

## Open Source Licenses

- **Mobius** — [MIT](LICENSE.txt)
- **VS Code** (fork base) — MIT
- **Continue** — Apache 2.0
- **Hermes Agent** (reference submodule) — see its repository
- **Ollama** (bundled runtime) — MIT

The bundled Ollama models and third-party extensions follow their respective upstream licenses.
