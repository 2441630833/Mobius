// Cross-platform packaging: keep the runtime and the pinned upstream core together.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const destination = process.argv[2];
if (!destination) { throw new Error('Usage: node scripts/stage-superagent.mjs <client-root>'); }
const target = path.resolve(destination);
if (target === root) { throw new Error('Staging destination must differ from the source repository'); }
const upstream = path.join(root, 'dsh-superagent-prototype');
if (!fs.existsSync(path.join(upstream, 'src/core/engine.ts'))) { throw new Error('Initialize dsh-superagent-prototype before packaging'); }
fs.mkdirSync(path.join(target, 'scripts/superagent'), { recursive: true });
for (const file of ['cli.mjs', 'agent.mjs', 'runtime.mjs', 'core.mjs']) {
	fs.copyFileSync(path.join(root, 'scripts/superagent', file), path.join(target, 'scripts/superagent', file));
}
fs.mkdirSync(path.join(target, 'dsh-superagent-prototype/src'), { recursive: true });
fs.cpSync(path.join(upstream, 'src/core'), path.join(target, 'dsh-superagent-prototype/src/core'), { recursive: true });
fs.copyFileSync(path.join(upstream, 'LICENSE'), path.join(target, 'dsh-superagent-prototype/LICENSE'));
console.log(`Super Agent runtime staged in ${target}`);
