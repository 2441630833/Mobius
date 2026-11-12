# Plan: Client-Side Chained Incremental Updates

## Root Cause
In GitHub Releases, CI produces differential patches between adjacent releases:
- Release `v1.0.22` contains `Mobius-Patch-v1.0.21-to-v1.0.22-win32-x64.zip` (~33 MB)
- Release `v1.0.23` contains `Mobius-Patch-v1.0.22-to-v1.0.23-win32-x64.zip` (~32 MB)

However, client update scripts (`scripts/install-win.ps1` and `scripts/update-mobius-local.ps1`) previously only performed a direct 1-hop search for `Mobius-Patch-$installedTag-to-$latestTag-win32-$arch.zip`. When a user skipped any version (such as updating from `v1.0.21` directly to `v1.0.23`), no single 1-hop patch asset existed. Consequently, the client abandoned incremental patching and downloaded the full ~927 MB installer.

## Goal
Implement client-side chained incremental patch resolution:
1. Parse all available releases from the GitHub Releases API to extract all available transition edges matching `Mobius-Patch-<fromTag>-to-<toTag>-win32-<arch>.zip`.
2. Construct a directed graph and perform Breadth-First Search (BFS) to find the shortest transition path from `$installedTag` to `$latestTag` (e.g. `v1.0.21 -> v1.0.22 -> v1.0.23`).
3. Support jumping across arbitrarily many versions as long as a continuous chain of valid patch assets exists (no arbitrary hop count threshold).
4. Sequentially download and apply each patch in the chain with robust backup and rollback:
   - Create a master backup of modified files prior to applying the first patch.
   - If any patch in the chain fails (network error, manifest failure, checksum mismatch, or extraction issue), safely roll back the installation directory to its pre-update state and fall back to the full installer.
   - If all patches in the chain succeed, update the `.mobius-installed-tag` to the final target tag and clean up backup files.
5. Provide the same chained patching capability to both `scripts/install-win.ps1` and `scripts/update-mobius-local.ps1`.
6. Add unit test coverage in `scripts/test-install-win.ps1` for multi-hop chained patching.

## Non-goals
- Server/CI changes: CI does not need to precompute $O(N^2)$ cross-version permutations.
- Changing delta zip format or binary patch engine.

## Tasks
1. [x] Create plan document in `docs/superpowers/plans/2026-11-12-chained-incremental-update.md`.
2. [x] Implement `Find-MobiusPatchChain` in `scripts/install-win.ps1` and update patch application logic to handle chains with safety rollback.
3. [x] Update `scripts/update-mobius-local.ps1` with chained patch resolution and sequential application.
4. [x] Add `DeltaChainSuccess` test case to `scripts/test-install-win.ps1`.
5. [x] Run full test suite to verify 0 regressions and multi-hop patch functionality.
6. [x] Git commit and push cleanly to `origin/main`.

## Acceptance Criteria
- When jumping across versions where adjacent patches exist (e.g. `v1.0.0 -> v1.0.1 -> v9.8.7`), the installer downloads only the chained patches and successfully updates files without downloading the full installer.
- When no chain exists or a gap exists between versions, the installer cleanly falls back to downloading the full setup executable.
- When a patch in a multi-hop chain is corrupted, the rollback mechanism restores the original pre-update state, and the installer falls back to the full installer.
- All existing scenarios in `scripts/test-install-win.ps1` continue to pass.
