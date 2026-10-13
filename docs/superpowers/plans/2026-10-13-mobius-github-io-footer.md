# Plan: Mobius GitHub Pages (github.io) Single-File Index Landing Page

## Root Cause / Context
The repository `2441630833/Mobius` needs a GitHub Pages (`github.io`) landing page matching the requested calm, vintage engraved-illustration full-viewport footer design for "meridian" / Mobius, featuring:
1. Seamless pen-and-ink engraved stone viaduct background video with `mix-blend-mode: multiply` against pale sage paper background (`#ebeee7`).
2. Exact typography (Fraunces serif + Inter sans from Google Fonts).
3. 8-point compass rose SVG with split-engraved cardinal points.
4. Lowercase wordmark "mobius", poetic tagline, 8-item nav with progressive dot separators, left-to-right animated hover underlines, and dynamic copyright year.
5. Direct download links to 3 desktop versions of Mobius (Windows .exe, macOS .dmg, Linux .deb) hosted on GitHub Releases, plus release links.
6. Full viewport (100vh / 100svh) with zero vertical/horizontal scroll across all standard screen sizes (1280x720, 1920x1080, 2560x1080, 768x1024, 390x844, 375x812, 360x640).

## Goal
- Build a single, self-contained `index.html` at the repo root (and copy to `docs/index.html` and `web/index.html` so whichever GitHub Pages publishing source is chosen, it serves seamlessly).
- Ensure all HTML, CSS, and JS are inline (no external assets except Google Fonts and the specified video URL).
- Allow users to click and download Windows, macOS, and Linux desktop versions directly from GitHub Releases (`v1.0.2` and `v1.0.3`).
- Strictly adhere to all visual and interaction specifications, including responsive breakpoints (900px tablet, 600px mobile), prefers-reduced-motion, and IntersectionObserver autoplay pause/play.

## Non-goals
- Do not add complex multi-page routing or heavy client bundles.
- Do not modify core VS Code / Continue engine files in other folders.

## Tasks
- [x] 1. Write the complete, self-contained `index.html` with:
   - Inline CSS design tokens (`--paper`, `--ink`, `--ink-soft`, `--muted`, `--serif`, `--sans`).
   - SVG compass mark (64x64, exact path definitions).
   - Wordmark ("mobius") in Fraunces 600, opsz 72.
   - Tagline.
   - Download section for Windows, macOS, Linux with exact GitHub Release links and icons.
   - Nav with 8 exact items, dot separators, hover animated underline.
   - Copyright line with `#year`.
   - Reverse DOM / CSS order for `<video>` and `<div class="footer__content">`.
   - Responsive breakpoints (900px, 600px) and reduced-motion support.
   - Inline script for year updating and IntersectionObserver video management.
- [x] 2. Ensure copies are placed in `index.html`, `docs/index.html`, and `web/index.html` for GitHub Pages hosting compatibility.
- [x] 3. Validate layout and zero-scroll across all target screen sizes using automated script / browser testing.
- [x] 4. Verify git status and commit cleanly.

## Acceptance Criteria
- Full viewport footer page with zero scrollbars at 1280x720, 1920x1080, 2560x1080, 768x1024, 390x844, 375x812, 360x640.
- All 3 desktop download links point to valid GitHub release assets.
- Video plays seamlessly and blends into `#ebeee7` paper.
- Responsive nav transforms to 4x2 on tablet and 2x4 on mobile.
- `TASK_COMPLETE` emitted when verified.
