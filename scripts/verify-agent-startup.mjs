// Exercise the packaged Electron app, using isolated profiles and its local
// debugging endpoint. A wrong renderer must fail packaging before publication.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { mkdtemp, mkdir, rm } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const executable = process.argv[2];
const sourceRoot = process.argv[3];
assert.ok(executable, 'Usage: node scripts/verify-agent-startup.mjs <executable> [source root]');
const scratch = await mkdtemp(path.join(tmpdir(), 'mobius-agent-startup-'));
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));

async function workbenchReady(url) {
	const socket = new WebSocket(url);
	try {
		await once(socket, 'open', { signal: AbortSignal.timeout(3000) });
		const response = once(socket, 'message', { signal: AbortSignal.timeout(3000) });
		socket.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: {
			expression: 'document.readyState === "complete" && !!document.querySelector(".monaco-workbench")',
			returnByValue: true
		} }));
		const [event] = await response;
		return JSON.parse(event.data).result?.result?.value === true;
	} finally {
		socket.close();
	}
}

async function launch(label, userData, args, renderer) {
	const server = createServer();
	server.listen(0, '127.0.0.1');
	await once(server, 'listening');
	const port = server.address().port;
	await new Promise(resolve => server.close(resolve));
	const env = { ...process.env };
	delete env.ELECTRON_RUN_AS_NODE;
	if (sourceRoot) { env.VSCODE_DEV = '1'; } else { delete env.VSCODE_DEV; }
	const child = spawn(executable, [
		...(sourceRoot ? [path.resolve(sourceRoot)] : []),
		`--user-data-dir=${userData}`, `--extensions-dir=${path.join(scratch, 'extensions')}`,
		`--remote-debugging-port=${port}`, '--remote-debugging-address=127.0.0.1',
		'--skip-welcome', '--skip-release-notes', '--disable-updates',
		'--disable-workspace-trust', '--log=trace', ...args
	], { env, stdio: ['ignore', 'pipe', 'pipe'] });
	let output = '';
	let failure;
	child.on('error', error => { failure = error; });
	for (const stream of [child.stdout, child.stderr]) {
		stream.on('data', chunk => { output = (output + chunk).slice(-12000); });
	}
	const exited = once(child, 'close').catch(() => {});
	try {
		const deadline = Date.now() + 90000;
		while (Date.now() < deadline) {
			if (failure) { throw failure; }
			assert.equal(child.exitCode, null, `${label}: app exited early\n${output}`);
			try {
				const response = await fetch(`http://127.0.0.1:${port}/json/list`, { signal: AbortSignal.timeout(3000) });
				const pages = (await response.json()).filter(target => target.type === 'page');
				if (renderer === 'sessions') {
					const editor = pages.find(target => target.url.includes('/vs/code/electron-browser/workbench/'));
					if (editor && await workbenchReady(editor.webSocketDebuggerUrl)) {
						assert.fail(`${label}: opened Editor instead of Agent view (${editor.url})`);
					}
				}
				const page = pages.find(target => target.url.includes(`/vs/${renderer}/electron-browser/`));
				if (page && await workbenchReady(page.webSocketDebuggerUrl)) {
					if (renderer === 'sessions') {
						assert.ok(!pages.some(target => target.url.includes('/vs/code/electron-browser/workbench/')), 'Unexpected Editor window');
					}
					console.log(`[OK] ${label}: ${page.url}`);
					return;
				}
			} catch (error) {
				if (error.code === 'ERR_ASSERTION') { throw error; }
			}
			await delay(500);
		}
		throw new Error(`${label}: ${renderer} workbench did not become ready\n${output}`);
	} finally {
		child.kill('SIGTERM');
		const killTimer = setTimeout(() => child.kill('SIGKILL'), 5000);
		await exited;
		clearTimeout(killTimer);
	}
}

try {
	await launch('Fresh default launch', path.join(scratch, 'fresh'), [], 'sessions');
	await launch('New window launch', path.join(scratch, 'new'), ['--new-window'], 'sessions');
	const project = path.join(scratch, 'project');
	await mkdir(project);
	const existing = path.join(scratch, 'existing');
	await launch('Existing Editor profile setup', existing, ['--folder-uri', pathToFileURL(project).href], 'code');
	await launch('Relaunch after Editor', existing, [], 'sessions');
} finally {
	await rm(scratch, { recursive: true, force: true, maxRetries: 3 });
}
