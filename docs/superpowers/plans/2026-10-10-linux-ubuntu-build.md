# Ubuntu / Linux Build & Packaging System for Mobius

## Root cause / Background

Mobius currently only has PowerShell-based build and packaging automation designed for Windows (`scripts/build-vscode.ps1`, `scripts/package.ps1`). The underlying VS Code OSS and Continue extensions are cross-platform, but there were no automated scripts, Docker recipes, or CI workflows to compile and package Mobius for Linux / Ubuntu (`.deb` and portable `.tar.gz`).

## Goal

Provide a complete, production-grade Linux Ubuntu build and packaging solution for Mobius:
1. Native Linux shell scripts:
   - `scripts/check-prerequisites-linux.sh`: Validates Node 22+, Python 3, C++ toolchain, and Ubuntu development headers (`libsecret-1-dev`, `libx11-dev`, `libxkbfile-dev`, `libkrb5-dev`, `fakeroot`, `dpkg-deb`).
   - `scripts/build-linux.sh`: One-click compilation of Continue and Mobius workbench on Ubuntu.
   - `scripts/package-linux.sh`: Packages Mobius into an Ubuntu/Debian `.deb` installer and portable `.tar.gz`, complete with desktop shortcuts, app icons, and MIME associations.
2. Containerized build solution:
   - `Dockerfile.ubuntu`: Standalone reproducible Ubuntu build container that builds `.deb` and `.tar.gz` without polluting the host system.
   - `scripts/docker-build-linux.ps1` & `scripts/docker-build-linux.sh`: One-command Docker build triggers for Windows and Linux hosts.
3. Continuous Integration:
   - `.github/workflows/build-ubuntu.yml`: GitHub Actions workflow building and publishing Ubuntu `.deb` and `.tar.gz` artifacts.
4. Workspace integration:
   - Added `package.json` scripts (`build:linux`, `package:linux`, `docker:build:linux`).
   - Documentation in `README.zh-CN.md` and `README.md`.

## Non-goals

- Altering Windows Inno Setup packaging scripts.
- Modifying VS Code workbench runtime core code.

## Tasks

1. [x] Create `scripts/check-prerequisites-linux.sh` and `scripts/build-linux.sh`.
2. [x] Create `scripts/package-linux.sh` supporting both `.deb` and `.tar.gz` output with proper metadata.
3. [x] Create `Dockerfile.ubuntu`, `scripts/docker-build-linux.ps1`, and `scripts/docker-build-linux.sh`.
4. [x] Create `.github/workflows/build-ubuntu.yml` for automated GitHub Actions builds.
5. [x] Update `package.json` to expose `build:linux`, `package:linux`, and `docker:build:linux`.
6. [x] Update `README.zh-CN.md` and `README.md` with Ubuntu build and installation guide.
7. [x] Verify script syntax and lint, stage and commit all changes cleanly.

## Acceptance criteria

- `scripts/build-linux.sh` and `scripts/package-linux.sh` can be executed on Ubuntu 20.04/22.04/24.04.
- `package-linux.sh` produces `dist/mobius_<version>_<arch>.deb` and `dist/Mobius-linux-<arch>.tar.gz`.
- Docker build (`Dockerfile.ubuntu`) compiles the entire stack in an isolated Ubuntu container.
- GitHub Actions workflow `.github/workflows/build-ubuntu.yml` is valid and ready to run.
- `package.json` scripts and documentation are in place.
