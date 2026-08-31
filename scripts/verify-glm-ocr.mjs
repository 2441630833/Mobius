/**
 * Smoke-test GLM-OCR via the production fork path (ONNX, not Ollama).
 * Usage: node scripts/verify-glm-ocr.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { fork } from "node:child_process";

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
const outNm = path.join(root, "continue", "extensions", "vscode", "out", "node_modules");
const coreNm = path.join(root, "continue", "core", "node_modules");
const sharpPlatform = path.join(extNm, "@img", "sharp-win32-x64", "package.json");
if (!fs.existsSync(sharpPlatform)) {
  fail(
    `@img/sharp-win32-x64 missing in Continue extension (run npm run ensure:glm-ocr): ${sharpPlatform}`,
  );
}

const env = {
  ...process.env,
  ELECTRON_RUN_AS_NODE: "1",
  GLM_OCR_LOCAL_MODEL_PATH: modelPath,
  OMP_NUM_THREADS: process.env.OMP_NUM_THREADS ?? "4",
  ORT_INTRA_OP_NUM_THREADS: process.env.ORT_INTRA_OP_NUM_THREADS ?? "4",
  ORT_INTER_OP_NUM_THREADS: process.env.ORT_INTER_OP_NUM_THREADS ?? "1",
  NODE_PATH: [outNm, extNm, coreNm, process.env.NODE_PATH]
    .filter(Boolean)
    .join(path.delimiter),
};

const child = fork(workerPath, [], {
  env,
  stdio: ["ignore", "pipe", "pipe", "ipc"],
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
    child.send({
      id: 1,
      op: "ocr",
      base64: pngBase64,
      mimeType: "image/png",
      prompt: "Text Recognition:",
      maxNewTokens: 32,
    });
  };
  child.on("message", (msg) => {
    if (!msg || typeof msg !== "object") {
      return;
    }
    if (msg.type === "init-error") {
      clearTimeout(timer);
      reject(new Error(msg.error));
      return;
    }
    if (msg.type === "ready") {
      if (msg.device) {
        console.log(`[info] OCR device=${msg.device}`);
      }
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
  child.on("error", (err) => {
    clearTimeout(timer);
    reject(err);
  });
  child.on("exit", (code, signal) => {
    if (code !== 0 && code !== null) {
      clearTimeout(timer);
      reject(new Error(`GLM-OCR process exited code=${code} signal=${signal}`));
    }
  });
  child.stderr?.on("data", (buf) => {
    const line = buf.toString("utf8").trim();
    if (line) {
      console.warn(`[glm-ocr stderr] ${line.slice(0, 400)}`);
    }
  });
  postOcr();
});

child.kill();

if (typeof result !== "string") {
  fail("GLM-OCR returned non-string result");
}

console.log(`[ OK ] GLM-OCR ONNX responded (${result.length} chars): ${JSON.stringify(result.slice(0, 120))}`);
console.log("[ OK ] Built-in GLM-OCR ONNX is running via fork (not Ollama glm-ocr)");
