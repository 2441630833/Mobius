# Fix macOS Icon: Transparent Background & Remove Black Squircle Tile

> Date: 2026-10-13  
> Target: Fix macOS Mobius icon by removing the opaque black/dark squircle tile background and restoring a clean transparent background with the Mobius infinity ribbon logo.

---

## 1. Root Cause Analysis

In commit `30c9e8c0`, `scripts/generate-mac-icns.py` was introduced to produce the macOS `code.icns` icon. In that script, lines 33-74 generated an artificial 824x824 squircle tile with a solid dark slate gradient (`#242630` -> `#14151b`) and an inner border outline, and pasted the Mobius logo on top:
```python
arr = np.zeros((tile_h, tile_w, 4), dtype=np.uint8)
top_color = np.array([36, 38, 48], dtype=np.float32)
bot_color = np.array([20, 21, 27], dtype=np.float32)
...
arr[y, :, 3] = 255
```
Because of this:
1. The icon background was 100% opaque dark charcoal/black instead of transparent.
2. In the macOS Dock, user sees a prominent "黑色的底部方框" (black background square box) behind the logo.
3. On modern macOS (Big Sur / Monterey / Ventura / Sonoma / Sequoia), macOS Dock/Launchpad renders this opaque square inside the system container tile, creating an awkward double-box appearance.
4. Other platforms (Windows `code.ico`, Linux `code.png`, and Web `logo.png`) have transparent backgrounds without any dark box.

---

## 2. Goals & Non-goals

### Goals
- Completely remove the solid dark slate background squircle and inner border from `scripts/generate-mac-icns.py`.
- Render the Mobius infinity ribbon on a 100% transparent canvas (RGBA `(0, 0, 0, 0)`).
- Add a subtle, high-quality silhouette drop shadow following Apple HIG for free-form icons, providing depth and edge contrast against both light and dark backgrounds while maintaining transparency.
- Provide crisp multi-resolution mipmaps (16x16 through 1024x1024) using high-quality Lanczos resampling.
- Re-generate `vscode/resources/darwin/code.icns` with the new transparent asset.
- Update `scripts/sync-brand-assets.ps1` to ensure macOS ICNS is synced properly.
- Verify binary ICNS format, chunks (`ic07`, `ic08`, `ic09`, `ic10`, etc.), and alpha transparency.

### Non-goals
- Modifying Windows `.ico` or Linux `.png` assets (already transparent).
- Modifying product IDs or unrelated application metadata.

---

## 3. Implementation Tasks

- [x] Task 1: Update `scripts/generate-mac-icns.py` to generate transparent-background icon with silhouette shadow and multi-resolution mipmaps.
- [x] Task 2: Update `scripts/sync-brand-assets.ps1` to support generating/updating macOS `code.icns` when brand assets are synced.
- [x] Task 3: Execute `scripts/generate-mac-icns.py` to generate the new `vscode/resources/darwin/code.icns`.
- [x] Task 4: Verify generated ICNS file format, resolution chunks, and transparent alpha channel.
- [x] Task 5: Commit changes in `vscode` submodule and root repository using encoding-safe commit.

---

## 4. Acceptance Criteria

1. `vscode/resources/darwin/code.icns` contains the Mobius infinity ribbon on a transparent background.
2. The corners and non-logo areas have alpha = 0 (completely transparent, no dark square box).
3. The ICNS file parses successfully with valid chunk structure (`TOC`, `ic07`, `ic08`, `ic09`, `ic10`, `ic11`, `ic12`, `ic13`, `ic14`).
4. `scripts/generate-mac-icns.py` runs cleanly without error.
5. `git status --short` is clean after commits.
