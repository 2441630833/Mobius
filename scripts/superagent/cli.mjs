#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import http from 'node:http';
import { randomUUID } from 'node:crypto';
import { setTimeout as delay } from 'node:timers/promises';
import { Supervisor, defaultConfig, validateConfig } from './runtime.mjs';
import { modelFromEnvironment, runProcess } from './agent.mjs';

const [action = 'status', ...args] = process.argv.slice(2);
const requestedRoot = args.includes('--repo') ? args[args.indexOf('--repo') + 1] : process.cwd();
const git = async argv => { const r = await runProcess('git', argv, requestedRoot); if (r.code) { throw new Error(r.text); } return r.text.trim(); };
const root = await git(['rev-parse', '--show-toplevel']);
const common = await git(['rev-parse', '--path-format=absolute', '--git-common-dir']);
const stateDir = path.join(common, 'mobius-superagent');
const configPath = path.join(stateDir, 'config.json');
const lockPath = path.join(stateDir, 'lock');
const ownerPath = path.join(lockPath, 'owner.json');
const snapshotPath = path.join(stateDir, 'status.json');
const writeJson = (file, value) => { const temp = `${file}.${process.pid}.tmp`; fs.writeFileSync(temp, JSON.stringify(value, null, 2), { mode: 0o600 }); fs.renameSync(temp, file); };
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8'));
const alive = pid => { try { process.kill(pid, 0); return true; } catch (e) { return e.code === 'EPERM'; } };
function owner() { try { const value = readJson(ownerPath); return alive(value.pid) ? value : undefined; } catch { return undefined; } }
function init() {
	fs.mkdirSync(stateDir, { recursive: true });
	if (!fs.existsSync(configPath)) {
		const config = structuredClone(defaultConfig);
		try {
			const pkg = readJson(path.join(root, 'package.json'));
			const script = ['test', 'check', 'compile'].find(key => pkg.scripts?.[key]);
			// npm's JS entry works without cmd.exe shell quoting on Windows.
			const npm = process.env.npm_execpath || [path.join(path.dirname(process.execPath), 'node_modules/npm/bin/npm-cli.js'), path.join(path.dirname(process.execPath), '../lib/node_modules/npm/bin/npm-cli.js')].find(p => fs.existsSync(p));
			if (script && npm) { config.verification = [[process.execPath, npm, 'run', script]]; }
		} catch { /* Project can supply its own verification command. */ }
		writeJson(configPath, config);
	}
}

async function daemon() {
	init();
	try { fs.mkdirSync(lockPath); }
	catch (error) {
		if (error.code !== 'EEXIST') { throw error; }
		if (owner()) { throw new Error('Background service is already running'); }
		// A newly created lock may not yet have written its owner. Never steal that lock.
		if (Date.now() - fs.statSync(lockPath).mtimeMs < 10000) { throw new Error('Another process is acquiring the service lock'); }
		fs.rmSync(lockPath, { recursive: true }); fs.mkdirSync(lockPath);
	}
	const nonce = randomUUID(); writeJson(ownerPath, { pid: process.pid, nonce });
	let supervisor, server, timer, stopping = false, tick;
	try {
		modelFromEnvironment();
		supervisor = new Supervisor({ root, stateDir, discoveryEnabled: !args.includes('--chat-only') });
		server = http.createServer(async (req, res) => {
			if (req.headers.host !== `127.0.0.1:${server.address().port}`) { res.writeHead(403).end(); return; }
			if (req.method === 'POST' && req.url === '/chat') {
				req.setEncoding('utf8');
				const origin = `http://127.0.0.1:${server.address().port}`;
				if (req.headers.origin !== origin || req.headers['x-mobius-control'] !== nonce) { res.writeHead(403).end(); return; }
				res.setHeader('Content-Type', 'application/json');
				try {
					let body = ''; for await (const chunk of req) { body += chunk; if (body.length > 300000) { throw new Error('Request too large'); } }
					const { model, ...request } = JSON.parse(body);
					const selectedModel = model ? modelFromEnvironment({ AI_MODEL: model.model, AI_API_KEY: model.apiKey, AI_BASE_URL: model.base }) : undefined;
					res.end(JSON.stringify(await supervisor.chat(request, selectedModel)));
				} catch (error) { res.writeHead(400).end(JSON.stringify({ error: error.message })); }
				return;
			}
			if (req.method === 'POST' && req.url === '/control') {
				const origin = `http://127.0.0.1:${server.address().port}`;
				if (req.headers.origin !== origin || req.headers['x-mobius-control'] !== nonce) { res.writeHead(403).end(); return; }
				res.setHeader('Content-Type', 'application/json');
				try {
					let body = ''; for await (const chunk of req) { body += chunk; if (body.length > 4096) { throw new Error('Request too large'); } }
					const { action, id } = JSON.parse(body);
					if (['pause', 'auto', 'observe'].includes(action)) {
						const c = readJson(configPath); c.mode = action === 'pause' ? 'paused' : action; supervisor.config = validateConfig(c); writeJson(configPath, c);
						if (action === 'auto') { supervisor.discoveryEnabled = true; }
					} else if (action === 'stop') { stopping = true; void supervisor.stop(); }
					else if (action === 'acknowledge' && typeof id === 'string') { supervisor.store.delete('attention', id); }
					else if (action === 'retry' && typeof id === 'string' && !supervisor.active.has(id)) { supervisor.engine.retryTicket(id); supervisor.store.delete('attention', id); }
					else { throw new Error('Unknown action or task is still running'); }
					res.end(JSON.stringify({ ok: true }));
				} catch (error) { res.writeHead(400).end(JSON.stringify({ error: error.message })); }
				return;
			}
			if (req.method !== 'GET' || !['/', '/status'].includes(req.url)) { res.writeHead(404).end(); return; }
			res.setHeader('Cache-Control', 'no-store'); res.setHeader('X-Content-Type-Options', 'nosniff');
			res.setHeader('Content-Security-Policy', "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'");
			res.setHeader('Content-Type', req.url === '/' ? 'text/html; charset=utf-8' : 'application/json');
			res.end(req.url === '/' ? fs.readFileSync(new URL('./panel.html', import.meta.url), 'utf8').replace('__CONTROL_TOKEN__', nonce) : JSON.stringify(supervisor.snapshot()));
		});
		await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
		const url = `http://127.0.0.1:${server.address().port}`;
		writeJson(ownerPath, { pid: process.pid, nonce, url });
		const stop = () => { stopping = true; void supervisor.stop(); };
		process.once('SIGINT', stop); process.once('SIGTERM', stop);
		timer = setInterval(() => {
			try {
				if (fs.existsSync(path.join(stateDir, 'stop.json')) && readJson(path.join(stateDir, 'stop.json')).nonce === nonce) { stop(); }
				const requests = path.join(stateDir, 'requests');
				if (fs.existsSync(requests)) {
					for (const name of fs.readdirSync(requests).filter(name => name.endsWith('.json'))) {
						const file = path.join(requests, name); const request = readJson(file);
						fs.unlinkSync(file);
						if (request.nonce !== nonce || stopping) { continue; }
						try {
							if (request.action === 'acknowledge') { supervisor.store.delete('attention', request.id); }
							else if (request.action === 'retry') {
								if (supervisor.active.has(request.id)) { throw new Error('Task is still running'); }
								supervisor.engine.retryTicket(request.id); supervisor.store.delete('attention', request.id);
							}
						} catch (error) { supervisor.notify('control', 'failed', error.message); }
					}
				}
				writeJson(snapshotPath, { ...supervisor.snapshot(), url, pid: process.pid, updatedAt: Date.now() });
			} catch (error) { supervisor.notify('host', 'failed', error.message); stop(); }
		}, 1000);
		while (!stopping) {
			try { tick = supervisor.tick(); await tick; } catch (error) { supervisor.notify('policy', 'failed', error.message); }
			if (!stopping) { await delay(1000); }
		}
	} finally {
		clearInterval(timer);
		await supervisor?.stop(); await tick;
		if (supervisor) { writeJson(snapshotPath, { ...supervisor.snapshot(), stopped: true }); supervisor.store.close(); }
		server?.close();
		try { if (readJson(ownerPath).nonce === nonce) { fs.rmSync(lockPath, { recursive: true }); } } catch { /* Already gone. */ }
	}
}

try {
	if (action === 'run') { await daemon(); }
	else if (action === 'chat') {
		const input = args[args.indexOf('--request') + 1];
		const output = args[args.indexOf('--response') + 1];
		if (!args.includes('--request') || !args.includes('--response')) { throw new Error('Supply request and response paths'); }
		try {
			const request = readJson(input);
			init();
			if (!owner()?.url) {
				modelFromEnvironment();
				const log = fs.openSync(path.join(stateDir, 'host.log'), 'a', 0o600);
				const child = spawn(process.execPath, [fileURLToPath(import.meta.url), 'run', '--chat-only', '--repo', root], { detached: true, windowsHide: true, stdio: ['ignore', log, log], env: process.env });
				child.on('error', () => {}); child.unref(); fs.closeSync(log);
				for (let i = 0; i < 100 && !owner()?.url; i++) { await delay(100); }
			}
			const current = owner();
			if (!current?.url || !/^http:\/\/127\.0\.0\.1:\d+$/.test(current.url)) { throw new Error('Background host failed to start; inspect host.log'); }
			const response = await fetch(`${current.url}/chat`, { method: 'POST', signal: AbortSignal.timeout(45000), headers: { Origin: current.url, 'X-Mobius-Control': current.nonce, 'Content-Type': 'application/json' }, body: JSON.stringify({ ...request, model: modelFromEnvironment() }) });
			writeJson(output, await response.json());
		} catch (error) { writeJson(output, { error: error.message }); }
	}
	else if (action === 'init') { init(); console.log(configPath); }
	else if (action === 'start') {
		init();
		if (args.includes('--auto')) { const c = readJson(configPath); c.mode = 'auto'; writeJson(configPath, validateConfig(c)); }
		if (owner()) {
			if (args.includes('--auto')) {
				const current = owner();
				const response = await fetch(`${current.url}/control`, { method: 'POST', headers: { Origin: current.url, 'X-Mobius-Control': current.nonce }, body: JSON.stringify({ action: 'auto' }), signal: AbortSignal.timeout(5000) });
				if (!response.ok) { throw new Error('Could not enable autonomous discovery'); }
			}
			console.log(`Already running: ${owner().url}`);
		}
		else {
			modelFromEnvironment();
			const log = fs.openSync(path.join(stateDir, 'host.log'), 'a', 0o600);
			const child = spawn(process.execPath, [fileURLToPath(import.meta.url), 'run', '--repo', root], { detached: true, windowsHide: true, stdio: ['ignore', log, log], env: process.env });
			child.on('error', error => console.error(error.message)); child.unref(); fs.closeSync(log);
			for (let i = 0; i < 50 && !owner()?.url; i++) { await delay(100); }
			if (!owner()?.url) { throw new Error(`Startup failed; inspect ${path.join(stateDir, 'host.log')}`); }
			console.log(`Mobius background coding: ${owner().url}\nPolicy: ${configPath}`);
		}
	} else if (action === 'stop') {
		const current = owner();
		if (current) {
			writeJson(path.join(stateDir, 'stop.json'), { nonce: current.nonce });
			for (let i = 0; i < 100 && owner(); i++) { await delay(100); }
			if (owner()) { throw new Error('Stop requested; still draining active processes. Check status.'); }
		}
		console.log('Background service stopped. Worktrees retained.');
	} else if (['retry', 'acknowledge'].includes(action)) {
		const current = owner();
		if (!current) { throw new Error('Start the background service before changing tasks'); }
		const id = args[0]; if (!id || id.startsWith('--')) { throw new Error('Supply a ticket/attention id from status'); }
		const requests = path.join(stateDir, 'requests'); fs.mkdirSync(requests, { recursive: true });
		writeJson(path.join(requests, `${randomUUID()}.json`), { nonce: current.nonce, action, id }); console.log('Request queued.');
	} else if (['pause', 'auto', 'observe'].includes(action)) {
		init(); const c = readJson(configPath); c.mode = action === 'pause' ? 'paused' : action; writeJson(configPath, validateConfig(c)); console.log(`Mode: ${c.mode}`);
	} else if (action === 'status') {
		console.log(JSON.stringify({ running: !!owner(), config: configPath, ...(fs.existsSync(snapshotPath) ? readJson(snapshotPath) : {}), ...(owner() ?? {}) }, null, 2));
	} else { throw new Error('Commands: init, start [--auto], run, status, pause, observe, auto, stop, retry ID, acknowledge ID [--repo PATH]'); }
} catch (error) { console.error(error.message); process.exitCode = 1; }
