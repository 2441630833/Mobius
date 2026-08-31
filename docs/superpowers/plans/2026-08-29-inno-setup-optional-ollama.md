# Inno Setup must not require staged Ollama

## Root cause

`npm run dev` launches `vscode/scripts/code.bat` from source. It never compiles
the Windows installer, so it never reads `vscode/build/win32/code.iss`.

`npm run package` ends with gulp `vscode-win32-x64-user-setup`, which runs
ISCC.exe on `code.iss`. Line 114 is:

```
Source: "resources\ollama\*"; ...
```

Inno Setup **compile-aborts** if a wildcard matches zero files. After GLM-OCR
ONNX + MiniLM replaced bundled Ollama, `package.ps1` no longer calls
`stage-bundled-ollama.ps1`, so `VSCode-win32-x64\resources\ollama\` is missing
and the setup task fails. `skipifsourcedoesntexist` is unreliable for
directory wildcards at compile time.

## Goal

User-setup packaging succeeds without a staged Ollama tree. If someone *has*
staged `resources/ollama` into the client, still pack it uncompressed.

## Non-goals

- Re-bundling Ollama or GLM via `ollama serve`
- Changing `npm run dev`
- Committing unless the user asks

## Tasks

1. [x] Wrap the Ollama `[Files]` entry in `#ifdef IncludeOllama`.
2. [x] In `gulpfile.vscode.win32.ts`, set `/dIncludeOllama=1` only when
   `VSCode-win32-<arch>/resources/ollama` contains files.
3. [x] Decouple `SKIP_OLLAMA_BUNDLE` from GLM-OCR ensure in `package.ps1`.
4. [x] Re-run gulp `vscode-win32-x64-user-setup` against the existing client tree.

## Acceptance criteria

- [x] ISCC no longer errors `No files found matching "...\resources\ollama\*"`
- [x] gulp `vscode-win32-x64-user-setup` gets past script compile without staged Ollama
  (full LZMA of the client tree continues in the background; that is pack time, not the old abort)
