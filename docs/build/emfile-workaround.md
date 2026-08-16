# EMFILE workaround for `vscode-win32-x64-min`

## Symptom

`npm run gulp vscode-win32-x64-min` aborts with:

```
'vscode-win32-x64-min' errored after ~2 min
Error: EMFILE: too many open files, open
  'D:\AI\physical-ai-ide\continue\core\node_modules\openai\src\_vendor\zod-to-json-schema\parsers\undefined.ts'
```

esbuild / gulp scans the `continue/core/node_modules/openai/...` tree (>10k files)
and Windows refuses new file handles.

## Fixes layered (this repo)

The fix is **defence in depth** — any one of the three layers below is enough to
prevent the EMFILE crash; together they make the build resilient to large
dependency trees.

### Layer 1 — `compile:safe` npm script (main repo)

Added a `compile:safe` script that wraps gulp with the Node-side headroom needed
when scanning large `node_modules` trees:

```jsonc
// package.json
"compile:safe": "powershell -ExecutionPolicy Bypass -File scripts/raise-ulimit.ps1 vscode-win32-x64-min"
```

The wrapper (`scripts/raise-ulimit.ps1`) sets:

- `NODE_OPTIONS=--max-old-space-size=8192 --experimental-strip-types`
- `UV_THREADPOOL_SIZE=8`
- `VSCODE_SKIP_NODE_VERSION_CHECK=1`

…and invokes `node vscode/node_modules/gulp/bin/gulp.js vscode-win32-x64-min`.

Use it with:

```powershell
npm run compile:safe
```

### Layer 2 — `isContinue` guard in `vscode/build/lib/extensions.ts` (vscode submodule)

`packageNonNativeLocalExtensionsStream` is the gulp step that compiles all
non-native extensions (including `extensions/continue/`). The continue extension
ships pre-packaged (`out/extension.js` + `out/node_modules`), so the gulp code
short-circuits the npm dep-discovery step for it:

```ts
// vscode/build/lib/extensions.ts
const isContinue = extensionName === 'continue';
const listCwd = isContinue ? fs.realpathSync(extensionPath) : extensionPath;
const packageManager = isContinue ? vsce.PackageManager.None : vsce.PackageManager.Npm;
```

This means the build **does not** recurse into `continue/core/node_modules/...`
when collecting files. If you are on a vscode submodule commit **before** this
guard was added, you will hit EMFILE. Update the submodule:

```powershell
git submodule update --remote vscode
```

### Layer 3 — OS-level handle quota (optional)

If EMFILE still occurs after layers 1 and 2, raise the per-process handle quota
and reboot once (Administrator PowerShell):

```powershell
fsutil behavior set memoryusage 1
```

## Verifying the fix

```powershell
# 1. Source rg.exe is in the build output
& d:\AI\physical-ai-ide\VSCode-win32-x64\resources\app\node_modules\@vscode\ripgrep-universal\bin\win32-x64\rg.exe --version
# should print: ripgrep 15.0.0

# 2. Install rg.exe into the shipped IDE
Get-Process | Where-Object { $_.ProcessName -match "^(Mobius|Code)$" } | Stop-Process -Force -ErrorAction SilentlyContinue
powershell -ExecutionPolicy Bypass -File d:\AI\physical-ai-ide\scripts\patch-ide-ripgrep.ps1
# should print: [ OK ] Verified installed ripgrep responds to --version

# 3. Build the IDE with the safe wrapper (no EMFILE)
npm run compile:safe
```

After step 2 + a restart of Mobius, the agent's `grep_search` tool will load
its `rg.exe` from the installed location and stop returning
`Config not loaded`.

## Where the EMFILE root cause actually lives

| Layer | File | Why it's the bottleneck |
|---|---|---|
| Source of file enumeration | `vscode/build/lib/extensions.ts::doPackageLocalExtensionsStream` | Calls `glob.sync('extensions/*/package.json')` and then walks each extension. Pre-`isContinue` guard, this walk also pulled in continue's huge `node_modules`. |
| gulp.src of the work | `vscode/build/lib/compilation.ts::compileTask` | `gulp.src(\`${src}/**\`, { base: \`${src}\` })` only scans `src/`, not the workspace root, so the main client compile is **not** a hot spot. |
| Subprocess spawn | `vscode/build/lib/scan.ts` (vscode-symbols task) | Walks production dependencies, not active for `vscode-win32-x64-min`. |

If you ever see EMFILE again, the **first** thing to check is whether the
`isContinue` guard at `extensions.ts:176` is still in the submodule you are
building from.

## Related

- `docs/superpowers/plans/2026-07-31-fix-grep-search-config-not-loaded.md` —
  the original plan this doc implements.
- `scripts/patch-ide-ripgrep.ps1` — copies `rg.exe` into the installed IDE so
  `grep_search` works after the next Mobius restart.
- `scripts/raise-ulimit.ps1` — the `compile:safe` wrapper itself.
