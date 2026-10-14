# Plan: Adapt One-Click & Desktop Downloads and Remove Irrelevant Content

## Root cause
The previous UI rebuild implemented the visual template layout strictly, but contained placeholder template data (e.g. fake "Trusted by 2000+ Enterprises" Microsoft/Amazon/Google avatars, fake SaaS API metrics like "Inference Time 120ms / 2.4M Context Windows", and dead "Get Started / Sign in / Case Studies" links). The user requested keeping the new video-background UI while adapting the essential Mobius functionality: one-click terminal install/update, the 3 desktop downloads (Windows, macOS, Linux), dynamic GitHub releases fetching, macOS gatekeeper guide, and removing all unrelated placeholder information.

## Goal
Adapt the single-viewport full-bleed video landing page for Mobius:
- Maintain full-bleed looping video background, Bubbledot dot-matrix font, and dark glassmorphic styling.
- Remove all unrelated filler: fake enterprise trust avatars (Microsoft/Amazon/Google), fake cloud SaaS metrics (Inference Time, Context Windows, Uptime), and placeholder links (Case Studies, Sign in).
- Integrate **Three Desktop Downloads**: Windows (.exe), macOS (.dmg), Linux (.deb) with vector icons, tags, hover glows, and dynamic GitHub Releases asset fetching.
- Integrate **One-Line Fast Installer & Updater**: Terminal widget with macOS, Windows, Linux tabs, command display, instant copy with feedback, sync-update note, and macOS Gatekeeper unblock guide modal.
- Provide Mobius branding, tagline, and optional i18n (Chinese/English switcher).
- Keep within the single-viewport design on desktop with responsive mobile adaptivity.
- Synchronize across repo root, `web/`, `docs/`, and `gh-pages` branch.

## Non-goals
- Re-introducing multi-page marketing clutter or legacy paper/ink styles.
- Leaving any uncommitted changes or broken deployment pipelines.

## Tasks
1. [x] Design & structure download actions and terminal widget in `index.html`:
   - Replace trust row and fake stats with desktop downloads and terminal widget
   - Add macOS Gatekeeper modal dialog
   - Refactor header links to relevant Mobius anchors / GitHub repo
2. [x] Style the download buttons, terminal card, tabs, copy button, and modal in `styles.css` matching the modern dark glassmorphic video-background aesthetic
3. [x] Implement JavaScript in `main.js`:
   - Fast installer tab switcher (macOS, Windows, Linux) with matching prompts
   - Clipboard copy with visual feedback
   - Dynamic GitHub Releases auto-fetch for latest download URLs
   - macOS Gatekeeper modal open/close
   - i18n support for EN / ZH
4. [x] Synchronize updated files to `web/`, `docs/`, and push to `main` and `gh-pages`
5. [x] Verify live deployment on `mobiusai.si` and ensure zero errors

## Acceptance criteria
1. No fake enterprise trust row, no fake SaaS metrics.
2. 3 desktop download buttons (Windows .exe, macOS .dmg, Linux .deb) are prominently displayed and functional.
3. Terminal one-line fast installer allows switching between macOS, Windows, and Linux, and copying the command.
4. macOS Gatekeeper unblock guide opens when triggered and displays `sudo xattr -cr /Applications/Mobius.app` command with copy button.
5. GitHub API dynamically updates download links to latest release assets.
6. Single-viewport video background layout remains clean and fully responsive.
7. Both `main` and `gh-pages` branches are up-to-date and live site verified.
