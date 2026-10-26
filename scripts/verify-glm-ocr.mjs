/** Production OCR smoke: optional extension directory and Node/Electron executable. */
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(import.meta.url);
const { verify } = require(path.join(root, 'continue/extensions/vscode/scripts/verify-glm-ocr-runtime.cjs'));
try {
  await verify(path.resolve(process.argv[2] || path.join(root, 'continue/extensions/vscode')), process.argv[3]);
} catch (error) {
  console.error(error);
  process.exitCode = 1;
}
