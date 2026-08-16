---
name: sync-visual-studio-toolchain-docs
description: "Use when updating repository prerequisites or build configuration to reflect a changed Visual Studio/MSVC toolset version or required native components such as Spectre-mitigated libraries."
auto-generated: true
generated-at: 2026-08-16T11:08:54.479Z
source-task: "- ☑ **MSVC v145 - VS 2026 C++ x64/x86 生成工具**（若用 VS 2022 则选 v143）\r\n- ☑ **MSVC v145 - VS 2026 C++ ARM64 生成工具** *（仅在构建 `package:arm64` 时需要）*\r\n\r\n这还不准确。我们用的就是143，不是145，帮我更新 readme。而且我们需要安装**Spectre**. ima…"
---
## When to use
- Documentation lists the wrong Visual Studio release or MSVC toolset (for example, v143 vs v145).
- The required native component set changes, such as adding or removing Spectre-mitigated libraries.
- Installation instructions must stay consistent across English and localized documentation.
- A search reveals old product names, toolset versions, winget package IDs, or troubleshooting notes spread across several files.

## Steps
1. Search the entire repository for all relevant identifiers: Visual Studio release name, `v1xx` toolset number, winget package IDs, component IDs, and related error codes.
2. Verify the actual toolchain from authoritative build files: MSBuild props/targets, node-gyp configuration, CI scripts, and packaging scripts.
3. Treat the Visual Studio release and MSVC platform toolset as separate concepts. A newer Visual Studio shell may target an older toolset, so not every release-year reference is wrong.
4. Update user-facing documentation consistently:
   - header badge or summary,
   - required-software table,
   - individual-component checklist,
   - installer/winget commands,
   - troubleshooting or FAQ entries for native build errors.
5. Mirror the same changes in all localized documentation.
6. For Spectre libraries, list both the regular and Spectre-mitigated MSVC components when native dependencies require them. Mark architecture-specific components, such as ARM64, as required only for the corresponding package target.
7. Leave functional build settings unchanged if they are intentionally different from the documented toolset, for example a script that launches a newer VS/MSBuild shell while targeting an older platform toolset.
8. Re-run the search after editing and confirm every remaining old identifier is intentional, such as a technical comment or a functional override.

## Pitfalls
- Do not blindly replace every Visual Studio year; some scripts may intentionally use a newer installer or shell with an older toolset.
- Do not tell users to disable or skip Spectre libraries if any native dependency still produces errors such as `MSB8040` without them.
- A project may disable Spectre in its own MSBuild settings while still requiring Spectre libraries on disk for third-party native modules.
- Remember ARM64 tools are usually only needed when building ARM64 packages.
- winget and Visual Studio Installer component IDs are exact strings; verify the normal and Spectre variants separately.

## Example
- Bad documented requirement: `Visual Studio 2026 with MSVC v145` and `Spectre libraries: do NOT install`.
- Correct after checking the build:
  - `Visual Studio 2022 with MSVC v143`
  - install both `MSVC v143 - VS 2022 C++ x64/x86 build tools` and the matching `Spectre-mitigated build tools`
  - install the ARM64 variants only for ARM64 packaging
  - add the corresponding Spectre component ID to the winget/Visual Studio Installer command
  - update `MSB8040` troubleshooting from "reinstall dependencies" to "install the missing Spectre-mitigated component".
