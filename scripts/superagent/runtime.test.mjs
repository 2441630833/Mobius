import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import http from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { Store } from './core.mjs';
import { Supervisor, defaultConfig, validateConfig } from './runtime.mjs';
import { runAgent, runProcess, safePath, modelFromEnvironment } from './agent.mjs';

const proposal = key => ({ key, title: `Fix ${key}`, task: `Implement ${key}`, ruleId: 'project-quality', evidence: 'README.md describes expected behavior' });
const chatRequest = (action, requestId = action, session = 'chat-a', text = 'Implement the complete feature with tests') => ({ action, requestId, session, text });

test('explicit chat intake runs in observe mode and deduplicates concurrent delivery', async t => {
	const f = await fixture(t, { mode: 'observe' }); let workers = 0;
	const s = f.create(async ({ cwd }) => { workers++; fs.writeFileSync(path.join(cwd, 'feature.txt'), 'feature'); return { state: 'ready', summary: 'Done', evidence: 'checked' }; });
	const [first, duplicate] = await Promise.all([s.chat(chatRequest('submit')), s.chat(chatRequest('submit'))]);
	assert.equal(first.id, duplicate.id); assert.equal(first.handled, true);
	await Promise.all([...s.active.values()].map(a => a.promise));
	assert.equal(workers, 1); assert.equal(s.snapshot().tickets.length, 1);
	assert.equal(s.snapshot().tickets[0].report.state, 'ready');
	assert.equal(s.snapshot().tickets[0].chat.session, 'chat-a');
	assert.equal((await s.chat(chatRequest('status'))).id, first.id);
	assert.equal((await s.chat(chatRequest('status', 'status-b', 'chat-b'))).handled, false);
	assert.equal((await s.chat(chatRequest('submit'))).id, first.id);
});

test('chat submission refuses dirty worktrees, paused policy and missing verification without tickets', async t => {
	const f = await fixture(t, { mode: 'observe', verification: [] }); const s = f.create(async () => { throw new Error('must not execute'); });
	assert.equal((await s.chat(chatRequest('submit'))).handled, false);
	fs.writeFileSync(path.join(f.stateDir, 'config.json'), JSON.stringify({ ...f.config, mode: 'paused' }));
	assert.equal((await s.chat(chatRequest('submit'))).handled, false);
	fs.writeFileSync(path.join(f.stateDir, 'config.json'), JSON.stringify({ ...f.config, verification: [[process.execPath, '-e', 'process.exit(0)']] }));
	fs.writeFileSync(path.join(f.root, 'README.md'), 'Uncommitted user changes');
	assert.match((await s.chat(chatRequest('submit'))).reason, /uncommitted/);
	assert.equal(s.snapshot().tickets.length, 0);
});

test('live followups reach the original worker, task pause/resume/cancel preserve identity', async t => {
	const f = await fixture(t, { mode: 'observe' }); let entered; let read; let seen = [];
	const started = new Promise(resolve => entered = resolve);
	const s = f.create(async ({ signal, takeMessages }) => {
		read = takeMessages; entered();
		await new Promise((resolve, reject) => { if (signal.aborted) { reject(new Error('aborted')); } else { signal.addEventListener('abort', () => reject(new Error('aborted')), { once: true }); } });
	});
	const first = await s.chat(chatRequest('submit')); await started;
	await s.chat(chatRequest('followup', 'extra', 'chat-a', 'Add regression tests too'));
	seen = read(); assert.ok(seen.includes('Add regression tests too')); assert.deepEqual(read(), []);
	const paused = await s.chat(chatRequest('pause')); assert.equal(paused.stage, 'paused'); assert.equal(s.active.size, 0);
	await s.chat(chatRequest('followup', 'paused-extra', 'chat-a', 'Preserve compatibility')); assert.equal(s.active.size, 0);
	const resumed = await s.chat(chatRequest('resume')); assert.equal(resumed.id, first.id);
	assert.equal(s.active.size, 1);
	await s.chat(chatRequest('cancel')); assert.equal(s.active.size, 0);
	assert.equal(s.store.tickets.get(first.id).ended.outcome, 'stopped');
	assert.equal(s.snapshot().tickets.length, 1);
	assert.equal((await s.chat(chatRequest('pause', 'other', 'chat-b'))).id, undefined);
});

test('chat host autostarts without discovery and authenticated transport returns the same task', async t => {
	const f = await fixture(t, { mode: 'observe' }); let calls = 0;
	const server = http.createServer(async (req, res) => {
		let body = ''; for await (const chunk of req) { body += chunk; }
		const request = JSON.parse(body); calls++; assert.match(request.messages[0].content, /background worker/);
		res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ choices: [{ message: { role: 'assistant', content: JSON.stringify({ state: 'blocked', summary: 'Test blocker' }) } }] }));
	});
	await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
	const cli = fileURLToPath(new URL('./cli.mjs', import.meta.url));
	const env = { ...process.env, AI_MODEL: 'selected-model', AI_API_KEY: 'test-chat-secret', AI_BASE_URL: `http://127.0.0.1:${server.address().port}/v1` };
	const run = async (...args) => (await promisify(execFile)(process.execPath, [cli, ...args, '--repo', f.root], { env, timeout: 20000, windowsHide: true })).stdout;
	const input = path.join(f.stateDir, 'input.json'); const output = path.join(f.stateDir, 'output.json');
	try {
		fs.writeFileSync(input, JSON.stringify(chatRequest('submit')));
		await run('chat', '--request', input, '--response', output);
		const first = JSON.parse(fs.readFileSync(output)); assert.equal(first.handled, true, JSON.stringify(first));
		await run('chat', '--request', input, '--response', output);
		assert.equal(JSON.parse(fs.readFileSync(output)).id, first.id);
		const status = JSON.parse(await run('status'));
		assert.equal((await fetch(`${status.url}/chat`, { method: 'POST', body: '{}' })).status, 403);
		for (let i = 0; i < 100 && calls === 0; i++) { await new Promise(resolve => setTimeout(resolve, 50)); }
		assert.equal(calls, 1); assert.equal(JSON.parse(fs.readFileSync(path.join(f.stateDir, 'config.json'))).mode, 'observe');
		assert.ok(!fs.readFileSync(output, 'utf8').includes('test-chat-secret'));
	} finally { await run('stop'); await new Promise(resolve => server.close(resolve)); }
});

test('followups during verification rerun the same worktree without losing requirements', async t => {
	const f = await fixture(t, { mode: 'observe' }); let runs = 0; let supplemented = false;
	const s = f.create(async ({ cwd, prompt }) => {
		runs++; if (runs === 2) { assert.match(prompt, /Keep compatibility/); }
		fs.writeFileSync(path.join(cwd, 'feature.txt'), `run ${runs}`);
		return { state: 'ready', summary: 'Done', evidence: 'checked' };
	});
	s.command = async (program, args, cwd, options) => {
		if (program === process.execPath && !supplemented) { supplemented = true; await s.chat(chatRequest('followup', 'late', 'chat-a', 'Keep compatibility')); }
		return runProcess(program, args, cwd, options);
	};
	const first = await s.chat(chatRequest('submit'));
	await Promise.all([...s.active.values()].map(a => a.promise));
	assert.equal(s.pending.has(first.id), true); s.dispatch();
	await Promise.all([...s.active.values()].map(a => a.promise));
	assert.equal(runs, 2); assert.equal(s.snapshot().tickets.length, 1);
	assert.equal(s.snapshot().tickets[0].report.state, 'ready');
	assert.equal(fs.readFileSync(path.join(s.snapshot().tickets[0].execution.worktree, 'feature.txt'), 'utf8'), 'run 2');
});

test('chat ownership and request deduplication survive reopening SQLite', async t => {
	const f = await fixture(t, { mode: 'observe' });
	const firstHost = f.create(async () => ({ state: 'blocked', summary: 'Needs input' }));
	const first = await firstHost.chat(chatRequest('submit'));
	await Promise.all([...firstHost.active.values()].map(a => a.promise));
	await firstHost.stop(); firstHost.store.close();
	const secondHost = f.create(async () => { throw new Error('Must not replay submission'); });
	assert.equal((await secondHost.chat(chatRequest('submit'))).id, first.id);
	assert.equal((await secondHost.chat(chatRequest('status'))).id, first.id);
	assert.equal(secondHost.active.size, 0); assert.equal(secondHost.snapshot().tickets.length, 1);
});

test('real model adapter consumes a followup arriving with its final response', async t => {
	let consumed = false; let calls = 0;
	const server = http.createServer(async (req, res) => {
		let body = ''; for await (const chunk of req) { body += chunk; }
		calls++; const request = JSON.parse(body);
		if (calls === 2) { assert.ok(request.messages.some(m => m.role === 'user' && m.content === 'Additional requirement')); }
		res.end(JSON.stringify({ choices: [{ message: { role: 'assistant', content: JSON.stringify({ state: 'blocked', summary: 'Need input' }) } }] }));
	});
	await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
	try {
		await runAgent({ role: 'worker', cwd: os.tmpdir(), prompt: 'Test request', model: { model: 'test', apiKey: 'test', base: `http://127.0.0.1:${server.address().port}` }, takeMessages: () => { if (calls === 1 && !consumed) { consumed = true; return ['Additional requirement']; } return []; } });
		assert.equal(calls, 2);
	} finally { await new Promise(resolve => server.close(resolve)); }
});

test('ECC recommendations and observed background selections remain distinct', async t => {
	const f = await fixture(t, { mode: 'observe' }); let calls = 0;
	const server = http.createServer(async (req, res) => {
		let body = ''; for await (const chunk of req) { body += chunk; }
		const request = JSON.parse(body); calls++;
		let message;
		if (calls === 1) {
			assert.ok(request.tools.some(tool => tool.function.name === 'load_capability'));
			assert.ok(!JSON.stringify(request.messages).includes('Read exact regression instructions'));
			message = { role: 'assistant', content: null, tool_calls: [{ id: 'load-1', type: 'function', function: { name: 'load_capability', arguments: JSON.stringify({ kind: 'skill', name: 'regression', reason: 'Cover the reported bug' }) } }] };
		} else {
			assert.ok(JSON.stringify(request.messages).includes('Read exact regression instructions'));
			message = { role: 'assistant', content: JSON.stringify({ state: 'blocked', summary: 'Need a reproduction' }) };
		}
		res.end(JSON.stringify({ choices: [{ message }] }));
	});
	await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
	try {
		const model = { model: 'test', apiKey: 'test', base: `http://127.0.0.1:${server.address().port}` };
		const s = f.create(options => runAgent({ ...options, model }));
		const submitted = await s.chat({ ...chatRequest('submit'), advisory: 'Suggested skills regression, unused', capabilities: [{ kind: 'skill', name: 'regression', content: 'Read exact regression instructions' }, { kind: 'agent-profile', name: 'reviewer', content: 'Review carefully' }] });
		assert.deepEqual(submitted.selections, []);
		await Promise.all([...s.active.values()].map(a => a.promise));
		const selected = s.snapshot().tickets[0].selections;
		assert.deepEqual(selected, [{ kind: 'skill', name: 'regression', reason: 'Cover the reported bug' }]);
		assert.deepEqual((await s.chat(chatRequest('status'))).selections, selected);
	} finally { await new Promise(resolve => server.close(resolve)); }
});
async function fixture(t, overrides = {}) {
	const root = fs.mkdtempSync(path.join(os.tmpdir(), 'mobius-superagent-'));
	const git = async args => { const r = await runProcess('git', args, root); assert.equal(r.code, 0, r.text); return r.text.trim(); };
	await git(['init']); fs.writeFileSync(path.join(root, 'README.md'), 'Example project'); await git(['add', '.']);
	await git(['-c', 'user.name=Test', '-c', 'user.email=test@localhost', 'commit', '-m', 'initial']);
	const stateDir = path.join(root, '.git', 'mobius-superagent'); fs.mkdirSync(stateDir);
	const config = { ...structuredClone(defaultConfig), mode: 'auto', verification: [[process.execPath, '-e', 'process.exit(0)']], ...overrides };
	fs.writeFileSync(path.join(stateDir, 'config.json'), JSON.stringify(config));
	let supervisor;
	t.after(async () => { if (supervisor) { await supervisor.stop(); supervisor.store.close(); } fs.rmSync(root, { recursive: true, force: true }); });
	return { root, stateDir, config, git, create: agent => supervisor = new Supervisor({ root, stateDir, agent }) };
}

test('SQLite repositories persist and roll back atomically', t => {
	const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'mobius-store-')); const file = path.join(dir, 'store.sqlite');
	t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
	let store = new Store(file); store.set('test', 'a', { value: 1 });
	assert.throws(() => store.atomic(() => { store.set('test', 'a', { value: 2 }); throw new Error('rollback'); }));
	store.close(); store = new Store(file); assert.deepEqual(store.get('test', 'a'), { value: 1 }); store.close();
});

test('observe discovers once without creating assignments or changing the repository', async t => {
	const f = await fixture(t, { mode: 'observe' }); let calls = 0;
	const s = f.create(async () => { calls++; return { tasks: [proposal('bug')] }; });
	await s.tick(); await s.tick();
	assert.deepEqual([calls, s.snapshot().proposals.length, s.snapshot().tickets.length, await f.git(['status', '--porcelain'])], [1, 1, 0, '']);
});

test('upstream Engine launches parallel isolated workers and retains verified commits for review', async t => {
	const f = await fixture(t); let active = 0, peak = 0;
	const s = f.create(async ({ role, cwd, prompt }) => {
		if (role === 'planner') { return { tasks: [proposal('one'), proposal('two'), proposal('three')] }; }
		assert.ok(prompt.includes('Implement ')); active++; peak = Math.max(active, peak);
		await new Promise(resolve => setTimeout(resolve, 40)); fs.writeFileSync(path.join(cwd, 'fix.txt'), 'verified fix'); active--;
		return { state: 'ready', summary: 'Fixed issue', evidence: 'fixture verification passed' };
	});
	await s.tick(); assert.equal(s.active.size, 2);
	await Promise.all([...s.active.values()].map(a => a.promise)); s.dispatch(); await Promise.all([...s.active.values()].map(a => a.promise));
	const results = s.snapshot();
	assert.equal(peak, 2); assert.equal(results.tickets.length, 3);
	assert.ok(results.tickets.every(ticket => ticket.report.state === 'ready' && ticket.execution.commit));
	assert.equal(results.attention.length, 3); assert.equal(await f.git(['status', '--porcelain']), '');
	assert.equal(fs.existsSync(path.join(f.root, 'fix.txt')), false);
	assert.equal(new Set(results.tickets.map(ticket => ticket.execution.worktree)).size, 3);
});

test('failed independent verification never yields a ready report or review commit', async t => {
	const f = await fixture(t, { verification: [[process.execPath, '-e', 'process.exit(3)']] });
	const s = f.create(async ({ role, cwd }) => {
		if (role === 'planner') { return { tasks: [proposal('broken')] }; }
		fs.writeFileSync(path.join(cwd, 'broken.txt'), 'not tested'); return { state: 'ready', summary: 'Looks fine', evidence: 'claimed success' };
	});
	await s.tick(); await Promise.all([...s.active.values()].map(a => a.promise));
	assert.equal(s.snapshot().tickets[0].report.state, 'failed'); assert.equal(s.snapshot().tickets[0].execution.commit, undefined);
});

test('paused policy makes no model calls', async t => {
	const f = await fixture(t, { mode: 'paused' }); const s = f.create(async () => { assert.fail('must not call model'); }); await s.tick();
	assert.equal(s.snapshot().tickets.length, 0);
});

test('daily task budget and deduplication survive repeated discovery', async t => {
	const f = await fixture(t, { maxTasksPerDay: 1 });
	const s = f.create(async ({ role }) => role === 'planner' ? { tasks: [proposal('one'), proposal('two')] } : { state: 'blocked', summary: 'Need fixture data' });
	await s.tick(); await Promise.all([...s.active.values()].map(a => a.promise)); s.store.set('clock', 'discovery', 0); await s.tick();
	assert.equal(s.snapshot().tickets.length, 1);
});

test('unknown rules fail closed before a ticket is created', async t => {
	const f = await fixture(t); const s = f.create(async () => ({ tasks: [{ ...proposal('bad'), ruleId: 'invented-rule' }] }));
	await s.tick(); assert.equal(s.snapshot().tickets.length, 0); assert.equal(s.snapshot().attention[0].kind, 'failed');
});

test('stop cancels workers and preserves incomplete work as blocked', async t => {
	const f = await fixture(t); let started;
	const ready = new Promise(resolve => started = resolve);
	const s = f.create(async ({ role, signal }) => {
		if (role === 'planner') { return { tasks: [proposal('cancel')] }; }
		started(); return new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(new Error('cancelled')), { once: true }));
	});
	await s.tick(); await ready; await s.stop(); assert.equal(s.snapshot().tickets[0].report.state, 'blocked');
});

test('policy rejects unbounded concurrency and automatic execution without verification', () => {
	assert.throws(() => validateConfig({ ...defaultConfig, maxParallel: 99 }));
	assert.throws(() => validateConfig({ ...defaultConfig, mode: 'auto' }));
});

test('file tools reject traversal and secret environment files', async () => {
	await assert.rejects(safePath(os.tmpdir(), '../secret')); await assert.rejects(safePath(os.tmpdir(), '.env'));
	assert.throws(() => modelFromEnvironment({ AI_MODEL: 'test', AI_API_KEY: 'secret', AI_BASE_URL: 'http://remote.example' }));
});

test('observed proposals are reassessed before execution when auto mode is enabled', async t => {
	const f = await fixture(t, { mode: 'observe' });
	const s = f.create(async ({ role }) => role === 'planner' ? { tasks: [proposal('observed')] } : { state: 'blocked', summary: 'fixture blocker' });
	await s.tick(); assert.equal(s.snapshot().tickets.length, 0);
	fs.writeFileSync(path.join(f.stateDir, 'config.json'), JSON.stringify({ ...f.config, mode: 'auto' })); s.store.set('clock', 'discovery', 0);
	await s.tick(); await Promise.all([...s.active.values()].map(a => a.promise)); assert.equal(s.snapshot().tickets.length, 1);
});

test('crash recovery blocks uncertain execution and retains its worktree metadata', async t => {
	const f = await fixture(t); let s = f.create(async () => ({ tasks: [proposal('recover')] }));
	await s.discover(); const ticket = s.store.tickets.list()[0]; s.engine.assignmentStarted(ticket.id, ticket.assignments[0].id);
	s.store.set('execution', ticket.id, { worktree: 'retained', branch: 'retained' }); s.store.close();
	s = f.create(async () => { assert.fail('must not replay uncertain work'); });
	assert.equal(s.snapshot().tickets[0].report.state, 'blocked'); assert.equal(s.snapshot().tickets[0].execution.worktree, 'retained');
	assert.equal(s.snapshot().attention[0].kind, 'blocked'); assert.equal(s.pending.size, 0);
});

test('changed written rules block previously admitted pending work', async t => {
	const f = await fixture(t); const s = f.create(async () => ({ tasks: [proposal('policy')] })); await s.discover();
	fs.writeFileSync(path.join(f.stateDir, 'config.json'), JSON.stringify({ ...f.config, rules: [{ id: 'project-quality', instruction: 'Documentation only' }] }));
	s.dispatch(); assert.equal(s.active.size, 0); assert.equal(s.snapshot().tickets[0].report.state, 'blocked');
});

test('packaged payload loads the real upstream Engine without the source checkout', async t => {
	const destination = fs.mkdtempSync(path.join(os.tmpdir(), 'mobius-payload-')); t.after(() => fs.rmSync(destination, { recursive: true, force: true }));
	const stage = fileURLToPath(new URL('../stage-superagent.mjs', import.meta.url));
	const result = await runProcess(process.execPath, [stage, destination], os.tmpdir()); assert.equal(result.code, 0, result.text);
	const entry = path.join(destination, 'scripts/superagent/core.mjs');
	const { pathToFileURL } = await import('node:url');
	const probe = await runProcess(process.execPath, ['--input-type=module', '-e', `const m = await import(${JSON.stringify(pathToFileURL(entry).href)}); if (typeof m.Engine !== 'function') process.exit(1);`], destination);
	assert.equal(probe.code, 0, probe.text); assert.ok(fs.readFileSync(path.join(destination, 'dsh-superagent-prototype/LICENSE'), 'utf8').includes('DeepSeek Harness Team'));
});

test('background CLI starts detached, refuses duplicate launch, serves panel and stops', async t => {
	const f = await fixture(t, { mode: 'observe' }); let requests = 0;
	const server = http.createServer((req, res) => {
		requests++; req.resume(); res.setHeader('Content-Type', 'application/json');
		res.end(JSON.stringify({ choices: [{ message: { role: 'assistant', content: '{"tasks":[]}' } }] }));
	});
	await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
	const cli = fileURLToPath(new URL('./cli.mjs', import.meta.url));
	const env = { ...process.env, AI_MODEL: 'test-model', AI_API_KEY: 'test-secret-not-persisted', AI_BASE_URL: `http://127.0.0.1:${server.address().port}/v1` };
	const run = async (action, ...extra) => (await promisify(execFile)(process.execPath, [cli, action, ...extra, '--repo', f.root], { env, timeout: 20000, windowsHide: true })).stdout;
	try {
		assert.match(await run('start'), /Mobius background coding:/);
		assert.match(await run('start'), /Already running:/);
		const status = JSON.parse(await run('status')); assert.equal(status.running, true);
		const panel = await fetch(status.url); const html = await panel.text(); assert.match(html, /Needs Your Attention/);
		const controlToken = /const token='([^']+)'/.exec(html)?.[1]; assert.ok(controlToken);
		assert.equal((await fetch(`${status.url}/control`, { method: 'POST', body: '{}' })).status, 403);
		const pause = await fetch(`${status.url}/control`, { method: 'POST', headers: { Origin: status.url, 'X-Mobius-Control': controlToken }, body: JSON.stringify({ action: 'pause' }) });
		assert.equal(pause.status, 200);
		assert.equal((await (await fetch(`${status.url}/status`)).json()).mode, 'paused');
		assert.equal((await fetch(`${status.url}/status`, { method: 'POST' })).status, 404);
		await run('pause'); assert.equal(JSON.parse(fs.readFileSync(path.join(f.stateDir, 'config.json'))).mode, 'paused');
		await run('start', '--auto'); assert.equal(JSON.parse(fs.readFileSync(path.join(f.stateDir, 'config.json'))).mode, 'auto');
		await run('stop'); assert.equal(JSON.parse(await run('status')).running, false);
		assert.ok(requests >= 1);
		assert.ok(!fs.readFileSync(path.join(f.stateDir, 'config.json'), 'utf8').includes('test-secret'));
	} finally { await run('stop'); await new Promise(resolve => server.close(resolve)); }
});

test('OpenAI-compatible adapter drives discovery, actual file tool execution and verified review', async t => {
	const f = await fixture(t);
	const server = http.createServer(async (req, res) => {
		let data = ''; for await (const chunk of req) { data += chunk; }
		const request = JSON.parse(data); const planner = request.messages[0].content.includes('background planner');
		let message;
		if (planner) {
			assert.ok(request.tools.every(tool => ['list', 'read'].includes(tool.function.name)));
			message = { role: 'assistant', content: JSON.stringify({ tasks: [proposal('api-flow')] }) };
		} else if (!request.messages.some(message => message.role === 'tool')) {
			message = { role: 'assistant', content: null, tool_calls: [{ id: 'write-1', type: 'function', function: { name: 'write', arguments: JSON.stringify({ path: 'result.txt', content: 'Written through the actual worker adapter' }) } }] };
		} else {
			message = { role: 'assistant', content: JSON.stringify({ state: 'ready', summary: 'Implemented API task', evidence: 'Supervisor runs configured validation' }) };
		}
		res.setHeader('Content-Type', 'application/json'); res.end(JSON.stringify({ choices: [{ message }] }));
	});
	await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
	try {
		const model = { base: `http://127.0.0.1:${server.address().port}/v1`, model: 'fixture-model', apiKey: 'fixture-key' };
		const s = f.create(options => runAgent({ ...options, model }));
		await s.tick(); await Promise.all([...s.active.values()].map(a => a.promise));
		const ticket = s.snapshot().tickets[0]; assert.equal(ticket.report.state, 'ready');
		assert.equal(fs.readFileSync(path.join(ticket.execution.worktree, 'result.txt'), 'utf8'), 'Written through the actual worker adapter');
		assert.match(ticket.execution.commit, /^[a-f0-9]{40}$/);
	} finally { await new Promise(resolve => server.close(resolve)); }
});
