# Plan: Dynamic Auto-Update for GitHub Releases Download Links

## Root Cause / Context
Currently, the download URLs for Windows, macOS, and Linux desktop installers are static HTML links. When a new release or GitHub Action build runs, new releases (e.g. `v1.0.4`, `v1.1.0`) will not be automatically reflected without code edits.

## Goal
Enable client-side auto-discovery of the newest GitHub Release assets using GitHub REST API in inline JS:
- Fetch `https://api.github.com/repos/2441630833/Mobius/releases` on page load.
- Find the newest matching `.exe`, `.dmg`, and `.deb` (or `.tar.gz`) assets across releases.
- Update the download button `href` and title attributes dynamically.
- Keep resilient static fallback URLs so the buttons always work even if the GitHub API is offline or rate-limited.
- Display the latest version tag (e.g., `v1.0.3`) as a subtle engraved badge or status if desired.

## Tasks
- [x] 1. Implement `updateLatestReleaseLinks()` in inline script in `index.html`.
- [x] 2. Synchronize `index.html` to `docs/index.html` and `web/index.html`.
- [x] 3. Verify in browser test script with zero errors and zero scrollbars.
- [x] 4. Commit changes cleanly.

## Acceptance Criteria
- Page dynamically updates download links to the absolute latest GitHub release assets on load.
- Page works offline or on rate-limit with fallback links.
- No console errors or layout shifts.
