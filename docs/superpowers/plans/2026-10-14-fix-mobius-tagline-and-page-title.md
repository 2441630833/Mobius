# Fix Mobius Tagline, Browser Tab Title, and Meta Descriptions

> Date: 2026-10-14  
> Target: Replace template/placeholder tagline ("The scenic route to shipped work. Plan, track, and deliver from town to town.") and browser tab titles/meta tags with Mobius's actual core identity: "A self-evolving agentic development environment / 会自我进化的智能体开发环境".

---

## 1. Root Cause

- The GitHub Pages template originally inherited placeholder copy from a Campsite design template ("The scenic route to shipped work. Plan, track, and deliver from town to town." and "Mobius Works Ltd.").
- This copy is completely unrelated to Mobius, which is an ADE (Agentic Development Environment) whose core value proposition is:
  - English: "A self-evolving agentic development environment. The AI coding partner that gets smarter the more you use it."
  - Chinese: "会自我进化的智能体开发环境。越用越聪明的 AI 编程伙伴。"

## 2. Goal

1. Update `<title>`, `<meta name="description">`, and `.footer__tagline` in HTML markup.
2. Update `docTitle`, `docDescription`, and `tagline` in both `en` and `zh` dictionaries of the `I18N` engine in `<script>`.
3. Update footer copyright from `Mobius Works Ltd.` to `Mobius`.
4. Mirror changes across `index.html`, `web/index.html`, and `docs/index.html`.
5. Verify syntax and identical SHA256 hashes.
6. Commit via clean UTF-8 Python helper.

## 3. Tasks

1. [x] Update `<title>`, `<meta name="description">`, `.footer__tagline`, and footer brand in `index.html`.
2. [x] Update `I18N.en` and `I18N.zh` dictionaries in `index.html`.
3. [x] Synchronize `index.html` to `web/index.html` and `docs/index.html`.
4. [x] Verify JavaScript syntax and verify matching file hashes.
5. [x] Commit cleanly with Git using UTF-8.

## 4. Acceptance Criteria

- Browser tab title displays "Mobius — A Self-Evolving Agentic Development Environment" in English and "Mobius — 会自我进化的智能体开发环境" in Chinese.
- Footer tagline displays "A self-evolving agentic development environment. The AI coding partner that gets smarter the more you use it." in English and "会自我进化的智能体开发环境。越用越聪明的 AI 编程伙伴。" in Chinese.
- All references to "town to town", "scenic route", and "Works Ltd." are eliminated.
- `index.html`, `web/index.html`, and `docs/index.html` remain synchronized.
