# Fix Windows CI Build and Rebuild Windows Installer for Release

> Date: 2026-10-15  
> Target: Fix Windows GitHub Actions build failures, ensure CI runner installs VS Code dependencies, skips heavy unbundled models, outputs MobiusSetup.exe, and trigger Windows build for release v1.0.4.

---

## 1. Root Cause Analysis

1. **`gulp.js MODULE_NOT_FOUND` on CI Runner**:
   - `scripts/package.ps1` called `Invoke-VsCodeGulp` without first verifying or installing `vscode/node_modules`.
   - On fresh GitHub Actions runners, `vscode` is a clean submodule clone without dependencies, so `node ./node_modules/gulp/bin/gulp.js` crashed immediately.
2. **`ensure-glm-ocr-onnx.ps1` Strict Exit**:
   - In `scripts/package.ps1`, `verify-glm-ocr-onnx.ps1` was executed unconditionally outside the `SKIP_GLM_OCR_BUNDLE` check.
   - In `scripts/install-continue.ps1`, `ensure-glm-ocr-onnx.ps1 -Strict` was also executed unconditionally.
   - On GitHub Actions runners, downloading ~3-4 GB of GLM-OCR model weights from HuggingFace failed, causing the entire packaging to abort.
3. **Artifact Naming in CI**:
   - Workflows only copied to `dist/Mobius-Setup-${version}-win32-x64.exe`, but static download links and scripts look for `MobiusSetup.exe` as well.
4. **Missing `workflow_dispatch` Release Tag Support**:
   - `build-windows.yml` only published releases on tag push `refs/tags/v*`, preventing manual re-runs from publishing to an existing tag like `v1.0.4`.

## 2. Goal

1. Fix `scripts/package.ps1` to auto-install VS Code dependencies if `gulp.js` is missing, and respect `SKIP_GLM_OCR_BUNDLE=1`.
2. Fix `scripts/install-continue.ps1` to respect `SKIP_GLM_OCR_BUNDLE=1`.
3. Fix `scripts/init-electron-env.ps1` to use official GitHub mirror in CI.
4. Update `.github/workflows/build-windows.yml` and `.github/workflows/build-all-platforms.yml`:
   - Set `SKIP_GLM_OCR_BUNDLE=1`, `ELECTRON_MIRROR=official`.
   - Pre-install dependencies.
   - Copy both `MobiusSetup.exe` and `Mobius-Setup-*-win32-x64.exe`.
   - Allow `release_tag` input in `workflow_dispatch` to attach to `v1.0.4`.
5. Trigger Windows build on GitHub Actions targeting `v1.0.4`.

## 3. Tasks

1. [x] Fix `scripts/package.ps1`, `scripts/install-continue.ps1`, and `scripts/init-electron-env.ps1`.
2. [x] Update `.github/workflows/build-windows.yml` and `.github/workflows/build-all-platforms.yml`.
3. [x] Commit changes cleanly using UTF-8 Python helper.
4. [x] Push commits to `origin/main`.
5. [x] Trigger the `Build Windows Desktop (.exe & zip)` GitHub Actions workflow with `release_tag: v1.0.4`.
6. [x] Verify workflow execution status.

## 4. Acceptance Criteria

- Windows CI workflow passes on GitHub Actions without `MODULE_NOT_FOUND` or model download failures.
- Windows installer artifacts (`MobiusSetup.exe` and `.zip`) are uploaded to GitHub Release `v1.0.4`.
- `install-win.ps1` and GitHub Pages can successfully pull `v1.0.4` for Windows.
