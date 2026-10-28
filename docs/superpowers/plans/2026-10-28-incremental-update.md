# Incremental Update (增量更新) Implementation for Mobius

## Root cause
The Windows one-click install/update command (`install-win.ps1`) always downloaded the full installer `MobiusSetup.exe` (~1 GB compressed, expanding to ~12 GB on disk) even when only a few files (e.g. JS/CSS workbench code, Continue extension fixes, or configuration) changed between releases. The build and release pipelines on GitHub Actions did not generate file manifests or differential patch packages, giving the client updater no option other than downloading the entire installer.

## Goal
Implement a robust, end-to-end incremental update system for Mobius on Windows:
1. Provide `scripts/generate-delta.ps1` to produce file manifests with SHA-256 hashes and build lightweight differential patch archives (`Mobius-Patch-*.zip`) by comparing new build trees against previous release manifests.
2. Provide `scripts/apply-delta.ps1` (and embed the core patch application engine into `scripts/install-win.ps1`) featuring pre-validation, SHA-256 hash checks, automatic pre-update backup, atomic replacement, removed file deletion, and automatic rollback on any failure.
3. Update `scripts/install-win.ps1` to automatically detect and prioritize incremental updates when updating an existing installation, downloading only ~10-30 MB instead of ~1 GB, with 100% reliable fallback to full `MobiusSetup.exe` if no valid patch is available or if patching encounters any issue.
4. Integrate manifest and delta generation into CI workflows (`.github/workflows/build-windows.yml` and `.github/workflows/build-all-platforms.yml`) and local package tooling (`scripts/package.ps1`).
5. Provide comprehensive automated behavioral tests verifying normal patch application, hash failure rollback, fallback behavior, and forced reinstallation.

## Non-goals
- Modifying Inno Setup installer compilation internals (`code.iss`) or binary patching of the setup executable itself (block-level bsdiff on compressed Inno Setup archives is brittle and requires preserving multi-gigabyte installer files on client disks).
- Changing macOS or Linux release packaging in this iteration (this task focuses on Windows one-click update requested by the user, while keeping design easily extensible).
- Disrupting clean uninstall: Inno Setup uninstall paths are maintained, and all patch-added files are recorded for clean maintenance.

## Tasks
1. [x] Implement `scripts/generate-delta.ps1`:
   - Compute SHA-256 file manifest (`manifest.json`) for any target directory (ignoring temp/cache/uninstaller files).
   - Compare current manifest against a previous manifest or directory to identify added, modified, and deleted files.
   - Bundle only added/modified files and `patch-manifest.json` into a compressed delta zip.
   - Support retrieving the previous release manifest automatically via GitHub API or local path.
2. [x] Implement `scripts/apply-delta.ps1`:
   - Standalone script with transactional application: staging extraction, checksum verification, backup creation, atomic file copy, deleted file removal, critical file verification, and automatic rollback.
3. [x] Upgrade `scripts/install-win.ps1`:
   - Inlined delta patch discovery and application logic with zero external dependencies.
   - Check release assets for matching patch archive (e.g. `Mobius-Patch-$installedTag-to-$latestTag-win32-$arch.zip` or `Mobius-Patch-win32-$arch.zip`).
   - If found, attempt incremental update; on any issue, cleanly fall back to full `MobiusSetup.exe`.
   - Update version tag, display size savings and elapsed time, and preserve notification/auto-close behavior.
4. [x] Update GitHub Actions workflows and package scripts:
   - Update `.github/workflows/build-windows.yml` and `.github/workflows/build-all-platforms.yml` to generate manifests and delta packages in `dist/`.
   - Update `scripts/package.ps1` to support `-CreateDelta` and `-PreviousManifest` options.
5. [x] Add automated test suites:
   - Create `scripts/test-delta-update.ps1` testing manifest generation, delta creation, full application, and rollback.
   - Extend `scripts/test-install-win.ps1` with incremental update scenarios (delta success, delta mismatch fallback, delta corruption rollback, force override).
6. [x] Run all verification tests and ensure clean status before completing.

## Acceptance criteria
1. [x] `scripts/generate-delta.ps1` correctly computes manifests, detects file differences, and packages delta archives.
2. [x] `scripts/apply-delta.ps1` and `scripts/install-win.ps1` successfully apply delta patches, verify checksums, and update `.mobius-installed-tag`.
3. [x] In case of patch corruption or missing files, `install-win.ps1` rolls back cleanly and falls back to full `MobiusSetup.exe`.
4. [x] All existing and new tests in `test-install-win.ps1` (17 scenarios) and `test-delta-update.ps1` (3 integration scenarios) pass on Windows PowerShell 5.1.
5. [x] `git status --short` is clean and committed without touching pre-existing unrelated submodules.

## Verification results
- `scripts/test-delta-update.ps1`:
  - Test 1: Delta generation, manifest hashing, filtering unchanged large weights (~100% precision).
  - Test 2: Delta application with adds, edits, deletes, and uninstaller data retention.
  - Test 3: Tampered payload checksum detection, pre-flight abort, and safe state rollback.
- `scripts/test-install-win.ps1`:
  - All 17 scenarios passed, including `DeltaSuccess` (download count = 1, install count = 0, patched file verified) and `DeltaCorrupt` (download count = 2, install count = 1 fallback to Inno Setup).
