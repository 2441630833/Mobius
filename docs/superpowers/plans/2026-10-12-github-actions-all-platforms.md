# GitHub Actions Multi-Platform CI/CD System (iOS/macOS, Windows, Linux)

## Root cause / Background

The user asked: "能用GitHub Actions 帮我自动编译吗？ ios, windows, linux 系统？"
While `build-ubuntu.yml` (Linux) and `build-macos.yml` (iOS / Apple macOS desktop) have been configured, there is currently no `build-windows.yml` workflow for Windows, and no unified all-in-one matrix workflow (`build-all-platforms.yml`) that can build all three platforms (macOS/iOS, Windows, Linux) in parallel from a single trigger or Git tag push.

## Goal

1. Provide `.github/workflows/build-windows.yml`:
   - Runs on `windows-2022`.
   - Sets up Node.js 22.x, Python 3.11, and Inno Setup 6.
   - Compiles Continue extension, builds VS Code OSS workbench (`win32-x64`), and packages Inno Setup installer (`MobiusSetup.exe`) and portable zip archive (`Mobius-<version>-win32-x64.zip`).
   - Copies artifacts to `dist/` and uploads to GitHub Artifacts / Releases.
2. Provide `.github/workflows/build-all-platforms.yml`:
   - Unified multi-platform CI/CD workflow building:
     - **iOS / macOS (Darwin)**: `macos-14` (Apple Silicon arm64) & `macos-13` (Intel x64), outputting `.dmg` and `.zip`.
     - **Linux**: `ubuntu-22.04`, outputting `.deb` and `.tar.gz`.
     - **Windows**: `windows-2022`, outputting `.exe` installer and `.zip`.
   - Supports `workflow_dispatch` with platform selection (all / macos / windows / linux).
   - Automatically publishes unified multi-platform assets to GitHub Releases upon tag pushes (`v*`).
3. Update `README.md` and `README.zh-CN.md`:
   - Document how to trigger GitHub Actions automated compilation for all 3 systems (iOS/macOS, Windows, Linux).
   - Explain how to download compiled installers directly from GitHub Actions Artifacts or GitHub Releases without any local build environment.

## Non-goals

- Altering local developer scripts or build scripts.
- Modifying VS Code runtime code.
- Committing unrelated submodule deviations.

## Tasks

1. [x] Create plan document `docs/superpowers/plans/2026-10-12-github-actions-all-platforms.md`.
2. [x] Create `.github/workflows/build-windows.yml` for Windows desktop packaging.
3. [x] Create `.github/workflows/build-all-platforms.yml` for unified concurrent multi-platform CI/CD.
4. [x] Update `README.md` and `README.zh-CN.md` with multi-platform GitHub Actions compilation guide.
5. [x] Verify YAML validity and clean git state.

## Acceptance criteria

- `.github/workflows/build-windows.yml` and `.github/workflows/build-all-platforms.yml` are created and syntactically valid.
- Workflows support both manual triggering (`workflow_dispatch`) and automatic release tagging (`v*`).
- Documentation clearly guides users on running GitHub Actions to get prebuilt installers for macOS/iOS, Windows, and Linux.
- Git repository is cleanly staged and committed.
