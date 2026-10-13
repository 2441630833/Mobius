# GitHub Pages Clean Terminal Card & Browser-Language i18n

> Date: 2026-10-13  
> Target: Clean up the GitHub Pages terminal quick-install card header by removing clutter texts, and implement full internationalization (i18n) based on the browser's default language with English and Chinese locales.

---

## 1. Root Cause & Requirements

1. **Terminal Card Cleanliness**:
   - The user requested to remove "一键安装/同步更新" and "全新 同步更新" from the quick-install terminal card header to keep the card sleek, minimalistic, and distraction-free (traffic-light dots on the left, OS tabs on the right).
2. **Internationalization (i18n)**:
   - The GitHub Pages site was primarily in Chinese or mixed.
   - The user requested full i18n with English locale as default/international option, dynamically displaying content based on `navigator.language` (Chinese if starting with `zh`, English otherwise).
   - Add a subtle manual language switch toggle so visitors can switch between English and Chinese at will, while respecting browser language on initial load.

## 2. Goal

- Clean up `.quick-install__topbar` by removing `.quick-install__meta` so the topbar cleanly houses window control dots and OS tabs.
- Build lightweight, zero-dependency client-side i18n dictionary (English `en` and Chinese `zh`).
- Auto-detect user browser language via `navigator.language || navigator.userLanguage`.
- Update all UI text nodes and element attributes (`data-i18n`, `data-i18n-title`, `data-i18n-aria`) dynamically.
- Provide a subtle language toggle (`EN | 中`) in the footer navigation.
- Synchronize across `index.html`, `web/index.html`, and `docs/index.html`.

## 3. Tasks

1. [x] Remove `.quick-install__meta` and badge from `.quick-install__topbar` in `index.html`.
2. [x] Define i18n translation dictionary for all texts (tagline, downloads, terminal, note, gatekeeper modal, nav, copy buttons).
3. [x] Add `data-i18n` attributes to markup elements.
4. [x] Implement language detection and dynamic text switching in JavaScript.
5. [x] Add a discreet language switcher toggle in the footer.
6. [x] Synchronize `index.html` to `web/index.html` and `docs/index.html`.
7. [x] Verify markup, console errors, and functionality.
8. [x] Git commit using clean UTF-8.

## 4. Acceptance Criteria

- Terminal card header contains only window dots on the left and OS tabs on the right (no "一键安装/同步更新" or "全新 · 同步更新" clutter).
- On English browser locale, page automatically renders in English.
- On Chinese browser locale (`zh*`), page automatically renders in Chinese.
- Users can toggle between EN and 中文 with instant update.
- Files `index.html`, `web/index.html`, and `docs/index.html` remain in sync.
