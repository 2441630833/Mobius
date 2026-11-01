// Mobius adapter for the pinned, unmodified MIT-licensed Super Agent domain engine.
import { registerHooks, stripTypeScriptTypes } from 'node:module';
import { readFileSync } from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

const upstream = new URL('../../dsh-superagent-prototype/src/core/', import.meta.url);
registerHooks({
	load(url, context, next) {
		if (url.startsWith(upstream.href) && url.endsWith('.ts')) {
			return { format: 'module', shortCircuit: true, source: stripTypeScriptTypes(readFileSync(new URL(url), 'utf8'), { mode: 'transform', sourceUrl: url }) };
		}
		return next(url, context);
	},
});
export const { Engine, ticketStage } = await import(new URL('index.ts', upstream));

/** Implements upstream Repositories with durable synchronous transactions. */
export class Store {
	constructor(file) {
		this.db = new DatabaseSync(file);
		this.db.exec('PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS records (kind TEXT, id TEXT, value TEXT NOT NULL, PRIMARY KEY(kind,id))');
		this.depth = 0;
		this.triggers = { get: id => this.get('trigger', id), save: row => this.set('trigger', row.id, row), disposition: id => this.get('disposition', id), saveDisposition: (id, row) => this.set('disposition', id, row) };
		this.threads = { get: id => this.get('thread', id), save: row => this.set('thread', row.key, row), list: () => this.list('thread'), active: () => this.list('thread').filter(t => t.pending.length || t.evaluating) };
		this.tickets = { get: id => this.get('ticket', id), save: row => this.set('ticket', row.id, row), list: () => this.list('ticket'), open: () => this.list('ticket').filter(t => !t.ended), active: () => this.list('ticket').filter(t => t.undelivered.length || ['pending', 'running'].includes(t.assignments.at(-1)?.state)) };
		this.decisions = { get: id => this.get('decision', id), save: row => this.set('decision', row.id, row), byThread: id => this.list('decision').filter(d => d.threadKey === id) };
	}
	get(kind, id) { const row = this.db.prepare('SELECT value FROM records WHERE kind=? AND id=?').get(kind, id); return row ? JSON.parse(row.value) : undefined; }
	set(kind, id, value) { this.db.prepare('INSERT INTO records VALUES (?,?,?) ON CONFLICT(kind,id) DO UPDATE SET value=excluded.value').run(kind, id, JSON.stringify(value)); }
	delete(kind, id) { this.db.prepare('DELETE FROM records WHERE kind=? AND id=?').run(kind, id); }
	list(kind) { return this.db.prepare('SELECT value FROM records WHERE kind=? ORDER BY rowid DESC').all(kind).map(row => JSON.parse(row.value)); }
	atomic(work) {
		if (this.depth) { return work(); }
		this.db.exec('BEGIN IMMEDIATE'); this.depth++;
		try { const result = work(); this.db.exec('COMMIT'); return result; }
		catch (error) { this.db.exec('ROLLBACK'); throw error; }
		finally { this.depth--; }
	}
	close() { this.db.close(); }
}
