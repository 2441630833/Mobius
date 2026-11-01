import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { Engine, Store, ticketStage } from './core.mjs';
import { runAgent, runProcess } from './agent.mjs';

export const defaultConfig = {
	version: 1, mode: 'observe', intervalSeconds: 900, maxParallel: 2,
	maxTasksPerDay: 6, maxDiscoveriesPerDay: 24, taskTimeoutSeconds: 1800,
	rules: [{ id: 'project-quality', instruction: 'Find and fix concrete bugs, missing regression coverage, or incomplete work supported by README, docs, tests and source. Keep changes small and aligned with existing architecture. No speculative features, dependency upgrades, publishing or deployment.' }],
	verification: [],
};
export function validateConfig(c) {
	if (c?.version !== 1 || !['observe', 'auto', 'paused'].includes(c.mode)) { throw new Error('Invalid policy version or mode'); }
	for (const [key, min, max] of [['intervalSeconds', 60, 86400], ['maxParallel', 1, 8], ['maxTasksPerDay', 1, 100], ['maxDiscoveriesPerDay', 1, 96], ['taskTimeoutSeconds', 60, 14400]]) {
		if (!Number.isInteger(c[key]) || c[key] < min || c[key] > max) { throw new Error(`Invalid ${key}: expected ${min}..${max}`); }
	}
	if (!Array.isArray(c.rules) || !c.rules.length || c.rules.some(r => !/^[a-z0-9-]{1,64}$/.test(r.id) || typeof r.instruction !== 'string' || !r.instruction.trim()) || new Set(c.rules.map(r => r.id)).size !== c.rules.length) { throw new Error('Supply unique written rules'); }
	if (!Array.isArray(c.verification) || c.verification.some(cmd => !Array.isArray(cmd) || !cmd.length || cmd.some(v => typeof v !== 'string'))) { throw new Error('Verification must contain program/argument arrays'); }
	if (c.mode === 'auto' && !c.verification.length) { throw new Error('Auto mode requires at least one project verification command'); }
	return c;
}
export function taskKey(task) { return createHash('sha256').update(`${task.ruleId}:${task.key.trim().toLowerCase()}`).digest('hex').slice(0, 24); }
export function validateTask(task, config) {
	if (!task || !['key', 'title', 'task', 'ruleId', 'evidence'].every(k => typeof task[k] === 'string' && task[k].trim() && task[k].length <= 12000) || !config.rules.some(r => r.id === task.ruleId)) { throw new Error('Planner returned an invalid task or unauthorized rule'); }
	return task;
}

export class Supervisor {
	constructor({ root, stateDir, agent = runAgent, command = runProcess }) {
		this.root = root; this.stateDir = stateDir; this.agent = agent; this.command = command;
		fs.mkdirSync(stateDir, { recursive: true });
		this.store = new Store(path.join(stateDir, 'state.sqlite'));
		this.active = new Map(); this.pending = new Set(); this.stopping = false;
		this.config = validateConfig(JSON.parse(fs.readFileSync(path.join(stateDir, 'config.json'), 'utf8')));
		this.engine = new Engine({
			repo: this.store,
			policy: () => ({ version: createHash('sha256').update(JSON.stringify(this.config.rules)).digest('hex'), paused: this.config.mode !== 'auto' || this.stopping,
				gate: trigger => ({ admissible: true, strength: 'inferred', basis: { via: 'bot', observation: { mode: this.config.mode } } }),
				revalidate: mandate => this.config.mode === 'auto' && this.config.rules.some(r => mandate.basis.rules?.includes(r.id)),
				admitsInferred: rules => this.config.mode === 'auto' && rules.length > 0 && rules.every(id => this.config.rules.some(r => r.id === id)), evalTimeoutMs: 60000 }),
			scope: { scope: () => ({ listened: true, observed: false }) },
			assessor: { request: () => {} },
			executor: { start: ticket => this.pending.add(ticket.id), deliver: () => {}, stop: () => {} },
			outbox: { send: () => { throw new Error('External messaging is disabled'); }, status: () => undefined, withdraw: () => {} },
		});
		// Never replay a possibly completed side effect after a process crash.
		for (const ticket of this.store.tickets.open()) {
			const assignment = ticket.assignments.at(-1);
			if (assignment?.state === 'running' && !assignment.report) {
				this.engine.report(ticket.id, { state: 'blocked', summary: 'Background host interrupted. Inspect the retained worktree before retrying.' });
				this.notify(ticket.id, 'blocked', 'Background host interrupted. Inspect the retained worktree before retrying.');
			} else if (assignment?.state === 'pending') { this.pending.add(ticket.id); }
		}
	}
	async git(args, cwd = this.root, signal) {
		const result = await this.command('git', args, cwd, { signal });
		if (result.code !== 0) { throw new Error(`git ${args[0]} failed: ${result.text.slice(-2000)}`); }
		return result.text.trim();
	}
	notify(id, kind, summary) {
		const previous = this.store.get('attention', id);
		if (previous?.kind === kind && previous?.summary === summary) { return; }
		this.store.set('attention', id, { id, kind, summary, at: new Date().toISOString() });
	}
	async discover(signal) {
		const today = new Date().toISOString().slice(0, 10);
		const usage = this.store.get('usage', today) ?? { scans: 0, tasks: 0 };
		if (usage.scans >= this.config.maxDiscoveriesPerDay || usage.tasks >= this.config.maxTasksPerDay) { return; }
		const now = Date.now();
		if (now - (this.store.get('clock', 'discovery') ?? 0) < this.config.intervalSeconds * 1000) { return; }
		this.store.set('clock', 'discovery', now);
		usage.scans++; this.store.set('usage', today, usage);
		const history = this.store.list('proposal').filter(t => this.config.mode !== 'auto' || t.mode === 'auto').slice(0, 100).map(t => ({ key: t.key, title: t.title }));
		const result = await this.agent({ role: 'planner', cwd: this.root, signal, maxSteps: 12,
			prompt: `Inspect this project's documentation and code; infer useful work within these written rules: ${JSON.stringify(this.config.rules)}. Do not suggest duplicates of: ${JSON.stringify(history)}. Inspect AGENTS.md, README and docs before proposing. Return only JSON.` });
		if (!Array.isArray(result.tasks) || result.tasks.length > 3) { throw new Error('Planner must return at most three tasks'); }
		for (const candidate of result.tasks) {
			this.config = validateConfig(JSON.parse(fs.readFileSync(path.join(this.stateDir, 'config.json'), 'utf8')));
			if (this.stopping || this.config.mode === 'paused') { break; }
			const task = validateTask(candidate, this.config); const id = taskKey(task);
			const previous = this.store.get('proposal', id);
			if (usage.tasks >= this.config.maxTasksPerDay || (previous && !(previous.mode === 'observe' && this.config.mode === 'auto'))) { continue; }
			this.store.atomic(() => {
				this.store.set('proposal', id, { ...task, mode: this.config.mode, at: new Date().toISOString() });
				if (this.config.mode !== 'auto') { return; }
				this.engine.receive({ id, source: 'project', threads: [{ source: 'project', id }], actor: { source: 'project', id: 'discovery' }, human: false, at: new Date().toISOString(), text: task.task, meta: { evidence: task.evidence } });
				this.engine.decide(id, { kind: 'accept', title: task.title, scope: task.task, reason: task.evidence, rules: [task.ruleId] });
				usage.tasks++; this.store.set('usage', today, usage);
			});
		}
	}
	async execute(id, controller) {
		const signal = controller.signal;
		const ticket = this.store.tickets.get(id); const assignment = ticket.assignments.at(-1);
		const worktree = path.join(this.stateDir, 'worktrees', id);
		const branch = `mobius/autonomous/${id}`;
		try {
			this.engine.assignmentStarted(id, assignment.id);
			this.engine.inputsDelivered(id, assignment.id, ticket.undelivered);
			this.engine.inputsRead(id, ticket.undelivered);
			if (!fs.existsSync(worktree)) { await this.git(['worktree', 'add', '-b', branch, worktree, 'HEAD'], this.root, signal); }
			const base = this.store.get('execution', id)?.base ?? await this.git(['rev-parse', 'HEAD'], worktree, signal);
			this.store.set('execution', id, { worktree, branch, base });
			const result = await this.agent({ role: 'worker', cwd: worktree, signal,
				prompt: `Assigned task: ${ticket.mandate.scope}\nWritten policy: ${JSON.stringify(this.config.rules)}\nIndependent verification commands: ${JSON.stringify(this.config.verification)}\nOnly work in ${worktree}. Do not create new tasks. Return a JSON report.` });
			if (!['ready', 'blocked', 'failed'].includes(result.state) || typeof result.summary !== 'string' || !result.summary.trim()) { throw new Error('Worker returned invalid report'); }
			if (result.state !== 'ready') {
				this.engine.report(id, { state: result.state, summary: result.summary }); this.notify(id, result.state, result.summary); return;
			}
			if (typeof result.evidence !== 'string' || !result.evidence.trim()) { throw new Error('Ready report is missing verification evidence'); }
			const checks = [];
			for (const [program, ...args] of this.config.verification) {
				const check = await this.command(program, args, worktree, { signal, timeout: this.config.taskTimeoutSeconds * 1000 });
				checks.push({ command: [program, ...args], code: check.code, output: check.text.slice(-8000) });
				this.store.set('verification', id, checks);
				if (check.code !== 0) { throw new Error(`Verification failed: ${program} ${args.join(' ')}`); }
			}
			await this.git(['diff', '--check'], worktree, signal);
			await this.git(['add', '-A'], worktree, signal);
			await this.git(['diff', '--cached', '--check', base], worktree, signal);
			const changes = await this.git(['diff', '--cached', '--name-only', base], worktree, signal);
			if (!changes) { throw new Error('No reviewable changes produced'); }
			if (await this.git(['diff', '--cached', '--name-only'], worktree, signal)) {
				await this.git(['-c', 'user.name=Mobius Super Agent', '-c', 'user.email=mobius-agent@localhost', 'commit', '-m', `feat: autonomous task ${id}`], worktree, signal);
			}
			const commit = await this.git(['rev-parse', 'HEAD'], worktree, signal);
			this.store.set('execution', id, { worktree, branch, base, commit, evidence: result.evidence });
			this.engine.report(id, { state: 'ready', summary: result.summary });
			this.notify(id, 'review', result.summary);
		} catch (error) {
			const current = this.store.tickets.get(id);
			if (!current.ended) { this.engine.report(id, { state: signal.aborted ? 'blocked' : 'failed', summary: error.message }); }
			this.notify(id, signal.aborted ? 'blocked' : 'failed', error.message);
		}
	}
	dispatch() {
		this.config = validateConfig(JSON.parse(fs.readFileSync(path.join(this.stateDir, 'config.json'), 'utf8')));
		if (this.stopping || this.config.mode !== 'auto') { return; }
		for (const id of this.pending) {
			if (this.active.size >= this.config.maxParallel) { break; }
			const ticket = this.store.tickets.get(id);
			if (!ticket || ticket.ended) { this.pending.delete(id); continue; }
			if (ticket.mandate.policyVersion !== createHash('sha256').update(JSON.stringify(this.config.rules)).digest('hex')) {
				this.pending.delete(id); this.engine.report(id, { state: 'blocked', summary: 'Written policy changed before execution. Review this task under the new policy.' });
				this.notify(id, 'blocked', 'Written policy changed before execution.'); continue;
			}
			this.pending.delete(id);
			const controller = new AbortController();
			const timer = setTimeout(() => controller.abort(), this.config.taskTimeoutSeconds * 1000);
			const promise = this.execute(id, controller).finally(() => { clearTimeout(timer); this.active.delete(id); });
			this.active.set(id, { controller, promise });
		}
	}
	async tick() {
		this.config = validateConfig(JSON.parse(fs.readFileSync(path.join(this.stateDir, 'config.json'), 'utf8')));
		if (this.stopping || this.config.mode === 'paused') { return; }
		this.dispatch();
		if (this.active.size < this.config.maxParallel) {
			this.discovery = new AbortController();
			try { await this.discover(this.discovery.signal); }
			catch (error) { if (!this.stopping) { this.notify('discovery', 'failed', error.message); } }
			finally { this.discovery = undefined; }
		}
		this.dispatch();
	}
	snapshot() {
		return { mode: this.config.mode, active: this.active.size, pending: this.pending.size,
			attention: this.store.list('attention'), proposals: this.store.list('proposal').slice(0, 30),
			tickets: this.store.tickets.list().map(t => ({ id: t.id, title: t.title, stage: ticketStage(t), report: t.assignments.at(-1)?.report, execution: this.store.get('execution', t.id) })) };
	}
	async stop() {
		this.stopping = true; this.discovery?.abort();
		for (const active of this.active.values()) { active.controller.abort(); }
		await Promise.allSettled([...this.active.values()].map(a => a.promise));
	}
}
