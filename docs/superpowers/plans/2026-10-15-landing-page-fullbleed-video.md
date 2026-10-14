# Plan: Rebuild Single-Viewport Full-Bleed Video Landing Page

## Root cause
The previous GitHub Pages site (`index.html`, `web/index.html`, `docs/index.html`) used a multi-component card/terminal layout with paper/ink styling. The user requested rebuilding it as an exact, high-impact single-viewport full-bleed video-background landing page with static HTML + CSS + vanilla JS matching a strict design specification.

## Goal
Implement a single-viewport landing page with:
- Full-bleed video background (`.bg-video` inside `.bg`) using the exact CloudFront video URL
- Inter (Google Fonts 400/500/600), BubbledotICG-FinePos (OnlineWebFonts retro dot-matrix), local Geist Pixel Circle fallback (`fonts/GeistPixel-Circle.woff2`), and Font Awesome 6.5.2
- Exact CSS variables, `.page` 3-region vertical flex layout (Header, Hero, Stats footer)
- Desktop header: circular logo button with `assets/logo.webp`, white nav pill with 3-dot active indicator under Home, dark sign-in pill, slideDown entrance animation
- Hero: "Trusted by 2000+ Enterprises" row with 3 padded dark/white avatar rings (Microsoft, Amazon, Google) and overlapping trust pill; 2-line solid white dot-matrix headline with per-line fade; subhead with exact copy, opacity 0.8, base+2pt sizing; "Get Started" CTA with soft white glow and `revealPulse` entrance
- Stats footer: 4 counting metrics (`< 120 ms Inference Time`, `% 99.99 % Platform Uptime`, `* 24 /7 Autonomous Runtime`, `# 2.4 M Context Windows`) with easeOutCubic count-up via IntersectionObserver
- Mobile (<=720px): circular burger button (white open state with black X), backdrop-blurred overlay, white modal sheet menu, staggered links, 2-column stats grid, tight height adaptations
- Synchronized across root, `web/`, and `docs/`, with GitHub Actions workflow updated for deployment

## Non-goals
- No JavaScript frameworks (React, Vue, etc.) or bundlers
- No multi-card hero or gradient headline animations
- No local Bubbledot files (OnlineWebFonts CDN used for BubbledotICG-FinePos)

## Tasks
1. [x] Download and verify local assets:
   - Save `fonts/GeistPixel-Circle.woff2` from official CDN package
   - Generate `assets/logo.webp` from high-resolution master brand logo
2. [x] Create `styles.css` implementing all exact CSS variables, resets, layout, typography, animations, responsive breakpoints (<=720px, <=420px, <=700px height), and reduced motion
3. [x] Create `index.html` with semantic HTML5 structure, exact fonts/meta/links, background video, desktop header, mobile menu & overlay, hero section, CTA, and stats footer
4. [x] Create `main.js` with easeOutCubic animated counters, IntersectionObserver, and mobile menu interaction (aria attributes, keyboard Esc, outside click, resize)
5. [x] Synchronize landing page files to `web/` and `docs/` and update `.github/workflows/deploy-pages.yml`
6. [x] Verify implementation across desktop, mobile viewport dimensions, and verify zero errors

## Acceptance criteria
1. Document title is `Intelligence Designed To Evolve`.
2. Exact background video tag with CloudFront URL covers full viewport behind UI (`z-index: 0`).
3. Exact CSS variables and fonts (Inter, BubbledotICG-FinePos, Geist Pixel Circle, Font Awesome 6.5.2) loaded and applied.
4. Header features circular logo, white nav pill with 3-dot active indicator, dark sign-in pill.
5. Trust row has 3 padded ring brand avatars (Microsoft, Amazon, Google) with hover lifts and overlapping trust pill.
6. Headline displays "Intelligence" and "Designed To Evolve" in solid white retro dot-matrix with per-line reveal.
7. Subhead has exact copy and +2pt font sizing; CTA has glowing pulse entrance.
8. 4 stats animate from 0 to targets (120ms, 99.99%, 24/7, 2.4M) with correct decimals and suffixes.
9. Mobile menu works seamlessly with animated burger, blur overlay, and white card sheet.
10. `git status` clean and verified.
