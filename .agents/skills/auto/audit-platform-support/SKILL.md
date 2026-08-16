---
name: audit-platform-support
description: "Use when verifying which operating systems or platforms a project actually supports versus what its documentation claims, and correcting the docs accordingly."
auto-generated: true
generated-at: 2026-08-16T10:48:49.277Z
source-task: "我们目前是不是只支持windows的platform?我们的项目，你检查下，我看readme 里面还写了macOS 和 Linux ，我们这个项目支持吗现在，我们用Visial Studio 编译的，目前是不是只支持windows 平台？"
---
## When to use

- A user questions whether a project truly supports a platform mentioned in its README or docs.
- You need to audit actual platform support before making claims about cross-platform compatibility.
- Documentation lists platforms (Windows/macOS/Linux) but the build or release toolchain may not be ported.

## Steps

1. **Inspect package manager scripts** (`package.json`, `Makefile`, `Cargo.toml`, etc.). Count how many scripts invoke platform-specific shells (PowerShell `.ps1`, batch `.cmd`, bash `.sh`). Zero presence of a shell family is a strong negative signal.

2. **List the scripts/tools directory**. Classify files by extension (`.ps1` vs `.sh`). A directory containing only one family indicates that platform is the sole target.

3. **Read native build configuration**. Files like `*.gyp`, `binding.gyp`, `node-gyp-*.js`, `CMakeLists.txt` often contain `process.platform` switches or hardcoded toolchain paths (MSBuild, MSVC, Windows SDK). Note which branches actually exist.

4. **Check packaging and release targets**. Look for platform-specific package commands (`package:win32`, `package:linux`, `package:mac`), installer tools (Inno Setup = Windows, pkgbuild = macOS, AppImage/deb = Linux), and which binary bundles are downloaded.

5. **Check CI configuration** (`.github/workflows/`, `.gitlab-ci.yml`, `azure-pipelines.yml`). The platform matrix in CI reveals what is actually tested. Absence of a CI directory means no automated cross-platform verification.

6. **Grep for platform identifiers** in source and config: `darwin`, `linux`, `win32`, `macOS`, `cross-platform`, OS names. Distinguish project code from `node_modules`.

7. **Distinguish transitive dependencies from real support**. npm packages like `@biomejs/cli-darwin-*` or `@esbuild/linux-*` install via `optionalDependencies` on every platform but are only invoked at runtime on their target OS. Their presence in `node_modules` does **not** mean the project supports that platform.

8. **Build an evidence table** listing each check and result. This makes the conclusion defensible.

9. **Update documentation to match reality**:
   - Replace misleading platform badges with accurate labels (including architecture if relevant, e.g., x64/ARM64).
   - Add a prominent callout near the top of the Quick Start stating actual support and roadmap intent.
   - Correct build-requirement tables; remove phrases like "standard cross-platform flow" if no such flow is scripted.
   - Make contributing guidance concrete: name the exact files and systems that need porting (e.g., `scripts/*.ps1`, installer configs, bundled binary logic).

10. **Do not modify source code** in this task unless explicitly asked. The goal is accurate documentation based on evidence.

## Pitfalls

- **Do not infer support from a framework's cross-platform nature.** A VS Code OSS fork, Electron app, or Node.js project is theoretically cross-platform, but the project's own build scripts may not be.
- **Do not treat optionalDependencies as proof of support.** Package managers install platform-specific binaries for all platforms; only runtime conditionals and actual build scripts prove support.
- **Do not claim a platform is unsupported based on a single missing file.** Gather multiple independent signals (scripts, CI, packaging, native modules, bundled binaries) before concluding.
- **Avoid vague wording** like "partially supported" or "should work." State exactly what is scripted, tested, and released, and what is not.
- **Keep both localized READMEs in sync** if the project maintains multiple language versions.

## Example

A project's README badges list Windows, Linux, and macOS. Investigation reveals: all 30+ npm scripts call PowerShell, the `scripts/` directory contains only `.ps1` files, `node-gyp-win.js` hardcodes MSBuild, packaging targets only `win32`/`arm64`, the Inno Setup installer is Windows-only, bundled Ollama downloads only Windows zips, and no CI workflows exist. Conclusion: Windows 10/11 (x64 and ARM64) is the only supported platform. The README badges, quick-start callout, build requirements table, and contributing section are updated to reflect this, while noting that the underlying framework is cross-platform and community ports are welcome.
