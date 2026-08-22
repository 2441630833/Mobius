/**
 * Smoke-test the production GLM-OCR worker_threads path (ONNX, not Ollama).
 * Usage: node scripts/verify-glm-ocr.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { Worker } from "node:worker_threads";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const workerPath = path.join(
  root,
  "continue",
  "extensions",
  "vscode",
  "out",
  "transformersJsGlmOcrWorker.js",
);
const modelPath = path.join(
  root,
  "continue",
  "extensions",
  "vscode",
  "models",
);
const decoderData = path.join(
  modelPath,
  "onnx-community",
  "GLM-OCR-ONNX",
  "onnx",
  "decoder_model_merged_q4f16.onnx_data",
);

function fail(msg) {
  console.error(`[FAIL] ${msg}`);
  process.exit(1);
}

if (!fs.existsSync(decoderData) || fs.statSync(decoderData).size < 100 * 1024 * 1024) {
  fail(`GLM-OCR ONNX missing or too small: ${decoderData} (run npm run ensure:glm-ocr)`);
}
if (!fs.existsSync(workerPath)) {
  fail(`GLM-OCR worker missing (run npm run install:continue): ${workerPath}`);
}

const pngBase64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";

const extNm = path.join(root, "continue", "extensions", "vscode", "node_modules");
const coreNm = path.join(root, "continue", "core", "node_modules");
const sharpPlatform = path.join(extNm, "@img", "sharp-win32-x64", "package.json");
if (!fs.existsSync(sharpPlatform)) {
  fail(
    `@img/sharp-win32-x64 missing in Continue extension (run npm run ensure:glm-ocr): ${sharpPlatform}`,
  );
}
process.env.NODE_PATH = [extNm, coreNm, process.env.NODE_PATH]
  .filter(Boolean)
  .join(path.delimiter);

const worker = new Worker(workerPath, {
  workerData: { localModelPath: modelPath },
  env: process.env,
});

const result = await new Promise((resolve, reject) => {
  const timer = setTimeout(
    () => reject(new Error("GLM-OCR worker timed out after 240s")),
    240_000,
  );
  let posted = false;
  const postOcr = () => {
    if (posted) {
      return;
    }
    posted = true;
    worker.postMessage({
      id: 1,
      op: "ocr",
      base64: pngBase64,
      mimeType: "image/png",
      prompt: "Text Recognition:",
      maxNewTokens: 32,
    });
  };
  worker.on("message", (msg) => {
    if (!msg || typeof msg !== "object") {
      return;
    }
    if (msg.type === "init-error") {
      clearTimeout(timer);
      reject(new Error(msg.error));
      return;
    }
    if (msg.type === "ready") {
      postOcr();
      return;
    }
    if ("id" in msg) {
      clearTimeout(timer);
      if (msg.ok) {
        resolve(msg.text);
      } else {
        reject(new Error(msg.error));
      }
    }
  });
  worker.on("error", (err) => {
    clearTimeout(timer);
    reject(err);
  });
  worker.on("exit", (code) => {
    if (code !== 0) {
      clearTimeout(timer);
      reject(new Error(`GLM-OCR worker exited with code ${code}`));
    }
  });
  postOcr();
});

await worker.terminate();

if (typeof result !== "string") {
  fail("GLM-OCR returned non-string result");
}

console.log(`[ OK ] GLM-OCR ONNX responded (${result.length} chars): ${JSON.stringify(result.slice(0, 120))}`);
console.log("[ OK ] Built-in GLM-OCR ONNX is running (not Ollama glm-ocr)");
