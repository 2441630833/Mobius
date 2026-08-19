/**
 * Smoke-test the production MiniLM worker_threads path (ONNX, not Ollama).
 * Usage: node scripts/verify-minilm.mjs
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
  "transformersJsEmbedWorker.js",
);
const modelPath = path.join(
  root,
  "continue",
  "extensions",
  "vscode",
  "models",
);
const onnxPath = path.join(
  modelPath,
  "all-MiniLM-L6-v2",
  "onnx",
  "model_quantized.onnx",
);

function fail(msg) {
  console.error(`[FAIL] ${msg}`);
  process.exit(1);
}

function cosine(a, b) {
  let dot = 0;
  let na = 0;
  let nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

if (!fs.existsSync(onnxPath) || fs.statSync(onnxPath).size < 10 * 1024 * 1024) {
  fail(`MiniLM ONNX missing or too small: ${onnxPath}`);
}
if (!fs.existsSync(workerPath)) {
  fail(`MiniLM worker missing (run npm run install:continue): ${workerPath}`);
}

const chunks = [
  "The cat sits on the mat",
  "A feline rests on a rug",
  "Quantum chromodynamics and lattice gauge theory",
];

const extNm = path.join(root, "continue", "extensions", "vscode", "node_modules");
const coreNm = path.join(root, "continue", "core", "node_modules");
process.env.NODE_PATH = [extNm, coreNm, process.env.NODE_PATH]
  .filter(Boolean)
  .join(path.delimiter);

const worker = new Worker(workerPath, {
  workerData: { localModelPath: modelPath },
  env: process.env,
});

const result = await new Promise((resolve, reject) => {
  const timer = setTimeout(
    () => reject(new Error("MiniLM worker timed out after 90s")),
    90_000,
  );
  let posted = false;
  const postEmbed = () => {
    if (posted) {
      return;
    }
    posted = true;
    worker.postMessage({ id: 1, op: "embed", chunks });
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
      postEmbed();
      return;
    }
    if ("id" in msg) {
      clearTimeout(timer);
      if (msg.ok) {
        resolve(msg.vectors);
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
      reject(new Error(`MiniLM worker exited with code ${code}`));
    }
  });
  postEmbed();
});

await worker.terminate();

if (!Array.isArray(result) || result.length !== chunks.length) {
  fail(`expected ${chunks.length} vectors, got ${result?.length}`);
}
for (const vec of result) {
  if (!Array.isArray(vec) || vec.length !== 384) {
    fail(`expected 384-d vector, got ${vec?.length}`);
  }
  const allTwos = vec.every((v) => v === 2);
  if (allTwos) {
    fail("got mock test vectors (all 2s) — ONNX did not run");
  }
}

const simClose = cosine(result[0], result[1]);
const simFar = cosine(result[0], result[2]);
console.log(
  `[ OK ] MiniLM ONNX embed dims=384 close=${simClose.toFixed(3)} far=${simFar.toFixed(3)}`,
);
if (!(simClose > simFar)) {
  fail(`semantic check failed: close (${simClose}) should beat far (${simFar})`);
}
console.log("[ OK ] Built-in MiniLM ONNX is running (not Ollama nomic-embed-text)");
