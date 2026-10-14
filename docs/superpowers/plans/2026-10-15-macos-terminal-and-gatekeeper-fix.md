# Plan: Polish macOS Terminal Aesthetic and Fix Gatekeeper Modal

## Root cause
1. Browser aggressive HTTP caching caused the previously deployed `styles.css` and `main.js` to be served from stale local cache, resulting in unstyled browser default links and non-functional modal triggers.
2. The terminal layout lacked authentic macOS Terminal styling (traffic lights, window title `mobius — -zsh — 80×24`, shell prompt `mobius@macbook ~ %`, blinking cursor, terminal status bar).
3. The Gatekeeper guide modal relied solely on standard `<dialog>` without fallback classes and was not guaranteed to open if scripts were cached or blocked.

## Goal
- Build an authentic macOS Terminal window component:
  - Top bar with red/yellow/green traffic lights, centered title (`mobius — -zsh — 80×24`), and OS switcher tabs.
  - Realistic macOS terminal body with `Last login` header, colored prompt (`mobius@macbook ~ % ` / `PS C:\Users\Mobius> `), terminal command, blinking cursor, and instant copy button.
  - Sub-terminal status row with sync-update note and macOS unblock guide trigger.
- Polish the 3 Desktop Download buttons into luminous, glassmorphic pill buttons with crisp SVG icons and tags.
- Bulletproof the Gatekeeper unblock modal with dual trigger handlers (DOM and inline fallback), high z-index (99999), backdrop blur, and guaranteed open/close logic.
- Implement cache-busting version query strings (`?v=20261015-3`) on all asset links and embed critical styles to guarantee instant rendering even on stale caches.
- Synchronize across `index.html`, `styles.css`, `main.js`, `web/`, `docs/`, and `gh-pages` branch.

## Tasks
1. [x] Rebuild `index.html` with:
   - macOS Terminal structure (traffic lights, title, tabs, realistic prompt, cursor, copy button)
   - Luminous desktop download pills (Windows, macOS, Linux)
   - Gatekeeper guide dialog with verified modal attributes and inline fallback
   - Cache-busting query strings on `styles.css` and `main.js`
2. [x] Overhaul `styles.css` with:
   - macOS Terminal styling (SF Mono/Menlo, realistic titlebar, traffic lights, dark glass blur, cursor animation)
   - High-contrast, premium download pill styling
   - Gatekeeper dialog backdrop blur, high z-index (99999), and guaranteed visibility
3. [x] Update `main.js` with:
   - Robust OS tab switcher (macOS, Windows, Linux) updating prompts (`%` vs `PS >`) and commands
   - Zero-fail copy handler with visual "已复制" feedback
   - Dual-mode modal open/close (showModal + class fallback)
   - Dynamic GitHub Release URL updater
4. [x] Synchronize to `web/` and `docs/`, commit to `main`, and push to `origin/main` and `origin/gh-pages`
5. [x] Verify live site on `mobiusai.si` and confirm terminal styling and modal functionality

## Acceptance criteria
1. One-click install command is styled inside a realistic macOS Terminal window with traffic lights, title bar, and blinking cursor.
2. Clicking "macOS 提示“无法打开”？3 秒放行指南" reliably opens the Gatekeeper guide modal.
3. Desktop download buttons render as styled glassmorphic pills with icons.
4. Live site verified with 200 status and updated markup.
