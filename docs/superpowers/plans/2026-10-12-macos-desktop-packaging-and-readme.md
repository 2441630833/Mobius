# macOS (Apple Desktop) Build & Packaging System and Multi-Platform Deployment Documentation

## Root cause / Background

The user requested: "增加 ios 编译打包destop, 以及readme 更新支持的系统及部署方式".
In colloquial developer usage, "ios desktop / 苹果系统桌面" refers to the Apple desktop operating system (macOS / Darwin, supporting Apple Silicon M-series arm64 and Intel x64). Mobius already has comprehensive packaging automation for Windows (PowerShell + Inno Setup) and Linux Ubuntu (Bash + dpkg/fakeroot + Docker). However:
1. There were no dedicated build, packaging, prerequisite-checking, or launcher scripts for macOS desktop (`.dmg` disk image and `.zip` bundle).
2. `package.json` lacked npm shortcut commands for macOS builds and packaging.
3. There was no GitHub Actions CI workflow to build and release macOS binaries automatically.
4. The documentation (`README.md` and `README.zh-CN.md`) was partially outdated (still stating in the prerequisites table that Windows was the only supported build platform, and not documenting macOS desktop build steps or Web/iOS mobile deployment modes).

## Goal

1. Provide complete native macOS / Darwin desktop build and packaging automation:
   - `scripts/check-prerequisites-mac.sh`: Checks macOS environment, Xcode CLI tools, Node 20/22+, Python 3, and disk packaging tools (`hdiutil`, `ditto`).
   - `scripts/build-mac.sh`: Syncs brand assets, compiles Continue extension for `darwin-arm64`/`darwin-x64`, and compiles the VS Code OSS workbench.
   - `scripts/package-mac.sh`: Runs gulp `vscode-darwin-$ARCH-min`, packages `Mobius.app` into `.dmg` (with `/Applications` symlink) and `.zip` archive, and computes SHA256 checksums.
   - `package-mac.sh` (and `package-ios.sh` alias wrapper): One-click root packaging entrypoint for macOS users (analogous to `package-ubuntu.sh`).
   - `scripts/launch-ide-mac.sh`: Developer launcher script for macOS.
2. Continuous Integration:
   - `.github/workflows/build-macos.yml`: Automated GitHub Actions workflow compiling macOS binaries on both Apple Silicon (arm64) and Intel (x64) runners, producing `.dmg` and `.zip` releases.
3. Workspace npm scripts:
   - Add `build:mac`, `package:mac`, `package:mac:arm64`, `package:mac:x64`, `package:ios`, and `start:mac` to `package.json`.
4. Documentation update:
   - Update `README.md` and `README.zh-CN.md` with:
     - All supported platforms (Windows 10/11, Linux Ubuntu/Debian, macOS / Apple Desktop).
     - Multi-platform packaging and deployment methods (Native local, Docker container, CI/CD, and Web/Server deployment for browser & iOS/iPadOS mobile devices).
     - Updated build environment prerequisites matrix.

## Non-goals

- Modifying Windows Inno Setup or Linux dpkg scripts.
- Modifying VS Code OSS core workbench TypeScript source.
- Committing unrelated submodule pointer modifications.

## Tasks

1. [x] Create plan document `docs/superpowers/plans/2026-10-12-macos-desktop-packaging-and-readme.md`.
2. [x] Create `scripts/check-prerequisites-mac.sh` and `scripts/build-mac.sh`.
3. [x] Create `scripts/package-mac.sh` and `scripts/launch-ide-mac.sh`.
4. [x] Create root `package-mac.sh` and `package-ios.sh` wrapper.
5. [x] Create `.github/workflows/build-macos.yml` for automated macOS CI builds.
6. [x] Update `package.json` to expose macOS build and packaging commands.
7. [x] Update `README.md` and `README.zh-CN.md` with complete platform support matrix and deployment guides.
8. [x] Verify scripts and syntax, stage and commit all changes cleanly.

## Acceptance criteria

- `scripts/check-prerequisites-mac.sh`, `scripts/build-mac.sh`, `scripts/package-mac.sh`, `scripts/launch-ide-mac.sh`, `package-mac.sh`, `package-ios.sh` are created and have executable permissions.
- Packaging script generates standard macOS `.dmg` and `.zip` artifacts under `dist/` with valid SHA256 checksums.
- `.github/workflows/build-macos.yml` is syntactically valid and covers both arm64 and x64 architectures.
- `package.json` contains npm scripts for `build:mac`, `package:mac`, `package:ios`, etc.
- `README.md` and `README.zh-CN.md` thoroughly describe supported systems, build commands, packaging outputs, and deployment scenarios (including Web access on iOS devices).
- Git repository state is cleanly committed without any unintended submodule pointer changes.
