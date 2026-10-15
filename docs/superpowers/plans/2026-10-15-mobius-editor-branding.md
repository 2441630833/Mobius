# Mobius editor branding and locale audit

## Root cause
The empty-editor CSS referenced generic letterpress SVG assets independent of the Mobius application logo. The English agent-to-editor tooltip already used productService.nameShort, but its unchanged localization key resolved to a Chinese translation containing literal VS Code and no placeholder. Existing translation caches preserved that old text. Other core UI templates and the default keymap label also retained upstream branding.

## Goal
Use the Mobius logo in empty editors in every theme, replace upstream product identity in Mobius UI (including Simplified Chinese), and establish the current UI and agent language defaults.

## Non-goals
Do not rename extension APIs, URLs, protocol identifiers, legal notices, dependencies, or extension-supplied parameter values. Preserve all pre-existing work, including root installer/PPT/OCR files and dirty vendor/hermes/vscode submodules. Do not stage unrelated submodule contents or gitlinks.

## Tasks
1. [x] Audit branding asset synchronization, editor/agent labels, translated strings, and language defaults in E:/MobiusCode/Mobius/scripts and vscode/src.
2. [x] Correct canonical branding assets and product labels, including the Chinese localization delivery path. Add focused regression checks for branding where meaningful.
3. [x] Run script syntax checks, focused regression checks, npm run check, and npm run compile. The build may take more than five minutes; allow it to finish. Review final diff and commit only this task's files (commit submodule changes separately before its intentional root gitlink update if required).

## Acceptance criteria
- Empty-editor watermark shows the Mobius logo in light, dark, and high-contrast themes.
- Agent-to-editor tooltip and related Mobius identity labels do not show VS Code in English or Simplified Chinese.
- Branding refresh/build preserves corrected text and logos.
- UI locale and agent response-language defaults are verified from code/config and explained to the user.
- Checks pass, commits contain only intended work, and remaining changes match the pre-existing deviations.

## Findings
The bundled Chinese pack has 206 upstream-brand templates, including openInVSCodeHover with no product placeholder. NLS formatting now brands templates before argument interpolation, which also fixes existing translation caches and preserves supplied paths/URLs/extension names. The watermark now references the existing workbench logo.png, maintained by sync-brand-assets.ps1, in all themes. product.json default keymap label is Mobius. The UI defaults to zh-cn in src/main.ts and scripts/launch-ide.ps1; Continue agent completion prompts follow the user language (continueChatAgent.ts). No language preference change is required.

## Tools and verification
The session does not expose manage_todo_list or get_errors. Use this numbered checklist as the todo record, real compiler diagnostics/script parsing plus git diff --check as the available verification equivalents. Commit messages: fix: use Mobius editor branding across themes and locales (vscode); fix: synchronize Mobius branding and localized product names (root).
## Workspace deviations
The initially dirty installer/PPT/OCR files were committed by other active sessions during this task. Another session subsequently changed vscode/src/vs/workbench/contrib/terminal/browser/xterm-private.d.ts, browser/xterm/xtermTerminal.ts and test/browser/xterm/xtermTerminal.test.ts; these terminal cursor changes remain excluded from this task. Preserve their commits. Also preserve the newly appeared unrelated docs/superpowers/plans/2026-10-15-agent-terminal-cursor.md. Existing hermes-agent and vendor gitlink differences, and the uninitialized godogen submodule, are outside this task; do not update or stage them.

## Installed application
The running application is C:/Users/mi/AppData/Local/Programs/Mobius/Mobius.exe. scripts/patch-ide-branding.mjs applies the same template formatter and watermark CSS change to both installed entry bundles and updates product resource checksums. It validates every target before writing, preserves .mobius-branding.bak files, and is idempotent. Changes are applied on disk; the user can reload the IDE window to display them. No running session was interrupted.

## Verification results
- npm run typecheck-client: passed (zero errors).
- npm run check: passed.
- Source NLS product-branding unit suite: 4 passing, covering English, cached Chinese, command aliases, placeholder arguments, URLs and identifiers.
- Browser rendering with actual source watermark rules: all four themes passed; screenshot in ignored tmp/mobius-branding-themes.png was visually reviewed.
- Installed patch fixture: passed, including backups and repeated execution.
- Both real installed bundles: all 206 upstream-brand Chinese templates render with Mobius; argument values remain intact. Installed logo equals the canonical logo, resource checksums match, and repeated application reports already current.
- node --check: repair script and both modified installed entry bundles passed.
- npm run compile initially failed because the child Windows PowerShell could not resolve Get-FileHash. Retried the same scripts/compile-vscode.ps1 entrypoint with pwsh -NoProfile; client compilation completed with zero errors. Built-in extension compilation also completed with zero errors; the full entrypoint exited 0.
- Source commit: 8c32468d60e2471e7444a50e2db63627d81bd793 (only the four intended branding files).
