# Plan: Linux ARM64 Auto-Adaptation & GitHub Actions Multi-Arch Packaging

**Date:** 2026-10-19  
**Status:** Completed  

## 1. Root Cause Analysis

1. **GitHub Actions Workflows**:
   - `.github/workflows/build-ubuntu.yml`: Configured with `runs-on: ubuntu-22.04` (x64) and defaulted to `ARCH="x64"` on tag pushes (`push: tags: - 'v*'`). ARM64 builds were never triggered or published on releases.
   - `.github/workflows/build-all-platforms.yml`: The `build-linux` job ran strictly on `ubuntu-22.04` with `--arch x64`, ignoring ARM64 entirely.
   - As a result, GitHub releases (e.g. `v1.0.6`) only contained `mobius_1.126.0_amd64.deb` and `mobius-1.126.0-linux-x64.tar.gz`.

2. **One-Line Installer (`scripts/install-linux.sh`)**:
   - On an ARM64 system (e.g. `AArch64` / `arm64`), `LINUX_ARCH` was identified as `arm64`.
   - When searching release assets, no `arm64.deb` was found.
   - The script contained a dangerous fallback:
     ```bash
     if [ -z "$DOWNLOAD_URL" ]; then
         DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v1.0.4/mobius_1.126.0_amd64.deb"
     fi
     ```
   - This caused ARM64 systems to download an x86 `amd64.deb`, failing at install time with:
     `dpkg: error processing archive ... package architecture (amd64) does not match system (arm64)`.
   - Release queries queried `/releases` (listing up to 30 releases), risking picking an older release's asset if the latest was incomplete.

3. **Packaging Scripts**:
   - `scripts/build-linux.sh`: Did not parse `--arch` argument from CLI.
   - `scripts/package-linux.sh`: Did not pass `--arch "$ARCH"` when invoking `build-linux.sh`.

## 2. Goal

- Provide full native ARM64 support in GitHub Actions for Linux builds using GitHub's native `ubuntu-24.04-arm` hosted runners.
- Make `.github/workflows/build-all-platforms.yml` and `.github/workflows/build-ubuntu.yml` build and publish both `x64` (`amd64`) and `arm64` Linux binaries (`.deb` and `.tar.gz`).
- Make `scripts/install-linux.sh` automatically detect machine architecture (`dpkg --print-architecture` and `uname -m`), fetch the exact matching release asset for that architecture, and prevent architecture mismatch fallbacks.
- Ensure build scripts (`build-linux.sh`, `package-linux.sh`, `package-ubuntu.sh`) correctly support `--arch arm64`.

## 3. Non-Goals

- Modifying macOS or Windows workflows (which already support their respective architectures).
- Altering VS Code OSS upstream packaging internals (`vscode-linux-arm64-min` is already defined in the build system).

## 4. Implementation Tasks

1. [x] Plan documented.
2. [x] Update `scripts/build-linux.sh` to accept `--arch` and target the requested architecture.
3. [x] Update `scripts/package-linux.sh` to forward `--arch "$ARCH"` to `build-linux.sh`.
4. [x] Update `scripts/install-linux.sh` to:
   - Detect architecture accurately using `dpkg --print-architecture` and `uname -m`.
   - Accurately match `.deb` (`_${LINUX_ARCH}.deb`) or `.tar.gz` (`linux-${TAR_ARCH}.tar.gz`) for the host architecture.
   - Eliminate hardcoded AMD64 fallback; fail gracefully with clear diagnostic messages if an ARM64 asset is not yet available.
5. [x] Update `.github/workflows/build-ubuntu.yml`:
   - Matrix build across `x64` (`ubuntu-22.04`) and `arm64` (`ubuntu-24.04-arm`).
   - Build both architectures on tag push (`v*`) and support `all`, `x64`, `arm64` in `workflow_dispatch`.
   - Publish both `.deb` and `.tar.gz` packages to GitHub Releases.
6. [x] Update `.github/workflows/build-all-platforms.yml`:
   - Matrix build `x64` and `arm64` in `build-linux` job.
   - Consolidate and publish both Linux architecture assets to the unified release.
7. [x] Update `package-ubuntu.sh` install hint for multi-architecture.
8. [x] Verify scripts syntax and behavior, verify git status, commit with UTF-8 clean commit message.

## 5. Acceptance Criteria

- `scripts/install-linux.sh` detects `arm64` / `aarch64` and requests `arm64` package, never falling back to `amd64`.
- `.github/workflows/build-ubuntu.yml` and `.github/workflows/build-all-platforms.yml` contain `arm64` runner and packaging steps.
- Shell scripts pass syntax validation (`bash -n`).
- Working tree clean and committed.
