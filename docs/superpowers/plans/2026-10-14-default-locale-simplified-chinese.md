# Mobius Default Locale to Simplified Chinese (zh-cn)

## Root Cause
1. In `vscode/src/main.ts`, `getUserDefinedLocale(argvConfig)` returns `undefined` when not specified, which causes Electron command line switch `--lang` to be forced to `'en'`, and `resolveNLSConfiguration` / `resolveNlsConfiguration` to resolve to English (`'en'`).
2. `createDefaultArgvConfigSync` in `vscode/src/main.ts` generates initial `argv.json` without `"locale": "zh-cn"`.
3. In `vscode/src/vs/base/node/nls.ts`, `resolveNLSConfiguration` aborts early to English if `process.env['VSCODE_DEV']` is set or if `commit` is undefined. Furthermore, `getLanguagePackConfigurations` only reads `userDataPath/languagepacks.json` which is initially empty on clean installations and never automatically populated for built-in extensions.
4. No Chinese language pack is bundled by default in `vscode/extensions/` or `VSCode-win32-x64/resources/app/extensions/`.
5. Helper launch and patch scripts (`scripts/launch-ide.ps1`, `scripts/patch-ide-native-modules.ps1`, etc.) do not set or ensure `"locale": "zh-cn"`.

## Goal
Make Simplified Chinese (`zh-cn`) the default locale for Mobius across both development mode and packaged installations, with complete UI translation available out-of-the-box without requiring manual extension installation or language switching.

## Non-goals
- Overriding explicit user locale preferences if the user intentionally sets `"locale": "en"` in `argv.json` or passes `--locale=en`.
- Committing unrelated submodule pointer deviations (`hermes-agent`, `vendor/*`).

## Tasks
1. [x] Bundle `vscode-language-pack-zh-hans` into `vscode/extensions/vscode-language-pack-zh-hans` and `VSCode-win32-x64/resources/app/extensions/vscode-language-pack-zh-hans`, and register in `vscode/product.json`.
2. [x] Update `vscode/src/vs/base/node/nls.ts` to allow dev mode NLS resolution, support commit fallback, auto-discover the bundled language pack if `languagepacks.json` is unpopulated, and resolve metadata files.
3. [x] Update `vscode/src/main.ts` so `getUserDefinedLocale` defaults to `'zh-cn'`, `createDefaultArgvConfigSync` writes `"locale": "zh-cn"`, and Electron lang switch defaults to `'zh-cn'`.
4. [x] Update `scripts/patch-ide-native-modules.ps1` and launch scripts (`launch-ide.ps1`, `launch-ide-mac.sh`, `launch-ide-linux.sh`) to default to `--locale=zh-cn`, and update current user `argv.json`.
5. [x] Compile `vscode` and verify NLS resolution and translations.
6. [x] Git commit encoding-safe and clean tree check.

## Acceptance Criteria
- Fresh or unconfigured Mobius installations default to Simplified Chinese (`zh-cn`).
- NLS resolution correctly translates workbench core UI to Simplified Chinese.
- Explicit `--locale` and `argv.json` overrides continue to be respected.
- Workspace builds cleanly and git status is clean.
