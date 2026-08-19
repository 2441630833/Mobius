# Bundled Ollama (Mobius)

This directory holds the **bundled Ollama runtime** and the local OCR model:

- `glm-ocr` — Agents image OCR preprocess

There is **no local embedding or chat model**. `@codebase` uses the built-in MiniLM ONNX (`transformers.js` / `all-MiniLM-L6-v2`). Agents chat uses a cloud provider from Settings / `.env`.

## Layout (after `npm run bundle:ollama`)

```
resources/ollama/
  bin-amd64/     # x64 Windows (~1.4 GB)
  bin-arm64/     # ARM64 Windows (~15 MB)
  models/        # shared model blobs (OCR only)
  home/          # Ollama config/cache (OLLAMA_HOME)
  .bundled-version
```

`npm start` detects the machine CPU (`amd64` or `arm64`) and starts the matching `bin-*` runtime. Models are shared across architectures.

These paths are **gitignored** — run `npm run bundle:ollama` once before release or first local use.

## Commands

| Command | Purpose |
|---------|---------|
| `npm run bundle:ollama` | Download **both** amd64 + arm64 Ollama + pull `glm-ocr` |
| `npm run verify:ollama` | Verify both architectures and the OCR model (release check) |
| `npm run setup:ollama` | Re-pull / verify OCR; retire leftover nomic-embed-text |
| `npm run ensure:minilm` | Download MiniLM ONNX if missing |
| `npm run verify:minilm` | Smoke-test MiniLM ONNX via worker_threads |
| `npm start` | Auto-starts bundled `ollama serve` for this machine's arch |

## Manual zip fallback

```powershell
$env:OLLAMA_ZIP_PATH_AMD64 = "D:\Downloads\ollama-windows-amd64.zip"
$env:OLLAMA_ZIP_PATH_ARM64 = "D:\Downloads\ollama-windows-arm64.zip"
npm run bundle:ollama
```

Ollama is [MIT licensed](https://github.com/ollama/ollama/blob/main/LICENSE).
