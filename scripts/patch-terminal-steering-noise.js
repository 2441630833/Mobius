#!/usr/bin/env node
/**
 * Hot patch: stop background-terminal "steering" messages from being injected
 * into the chat transcript.
 *
 * Symptom it removes:
 *   [Terminal <id> notification: command completed. The terminal has been cleaned up.]
 *   [Terminal <id> notification: command may be waiting for input ...]
 *
 * Why: RunInTerminalTool sends `IChatService.sendRequest(..., queue: 'steering')`
 * when a background terminal command finishes or asks for input. A steering
 * request preempts the turn that is currently running, so the transcript jumps
 * back to the user lane mid-task and the agent stops after a couple of todo
 * items. The Continue agent loop already receives every command's stdout/exit
 * code as a tool result, so the steering message is redundant for Mobius.
 *
 * What it does: rewrites only the two `sendRequest(...)` calls at those sites
 * into `Promise.resolve()`, which keeps the trailing `.catch(...)` chain
 * syntactically valid while sending nothing. Terminal disposal, artifact
 * capture and output collection are untouched.
 *
 * Usage:
 *   node scripts/patch-terminal-steering-noise.js            # patch installed Mobius
 *   node scripts/patch-terminal-steering-noise.js --revert   # restore backups
 *   node scripts/patch-terminal-steering-noise.js --dry-run  # report only
 */

'use strict';

const fs = require('fs');
const path = require('path');

const BAK_SUFFIX = '.mobius-steering.bak';
const MARKER = '/*mobius:steering-off*/';

const TARGETS = [
	'C:/Users/mi/AppData/Local/Programs/Mobius/resources/app/out/vs/workbench/workbench.desktop.main.js',
	'C:/Users/mi/AppData/Local/Programs/Mobius/resources/app/out/vs/sessions/sessions.desktop.main.js',
];

/**
 * Both bundles are minified with slightly different variable names for the
 * session resource (`o` in the workbench bundle, `i` in the sessions bundle),
 * but the options object literal is byte-identical. Match on the stable tail
 * and capture the receiver prefix so the replacement stays bundle-agnostic.
 *
 * localize ids: 17733 = input needed, 17734 = command completed.
 */
const CALL_PATTERN =
	/(this\._chatService\.sendRequest\(\s*[A-Za-z_$][\w$]*\s*,\s*[A-Za-z_$][\w$]*\s*,\s*\{\.\.\.f,\s*queue:"steering",\s*isSystemInitiated:!0,\s*systemInitiatedLabel:d\((?:17733|17734),null,p\),\s*terminalExecutionId:t\s*\}\)(?!\s*\/\*mobius:steering-off\*\/))/g;

function replaceAll(content, dryRun, label) {
	let hits = 0;
	const next = content.replace(CALL_PATTERN, () => {
		hits++;
		return `(Promise.resolve())${MARKER}`;
	});
	if (hits > 0 && !dryRun) {
		fs.writeFileSync(label, next, 'utf8');
	}
	return { hits, next };
}

function patchFile(file, dryRun) {
	if (!fs.existsSync(file)) {
		return { file, status: 'missing' };
	}
	const original = fs.readFileSync(file, 'utf8');

	if (original.includes(MARKER)) {
		return { file, status: 'already-patched' };
	}

	const next = original.replace(CALL_PATTERN, () => `(Promise.resolve())${MARKER}`);
	const hits = (original.match(CALL_PATTERN) || []).length;
	if (hits === 0) {
		return { file, status: 'no-match' };
	}

	const bak = file + BAK_SUFFIX;
	if (!fs.existsSync(bak)) {
		fs.copyFileSync(file, bak);
	}

	if (dryRun) {
		return { file, status: 'would-patch', hits };
	}

	fs.writeFileSync(file, next, 'utf8');
	return { file, status: 'patched', hits, backup: bak };
}

function revertFile(file) {
	const bak = file + BAK_SUFFIX;
	if (!fs.existsSync(bak)) {
		return { file, status: 'no-backup' };
	}
	fs.copyFileSync(bak, file);
	fs.unlinkSync(bak);
	return { file, status: 'reverted' };
}

function main() {
	const args = process.argv.slice(2);
	const dryRun = args.includes('--dry-run');
	const revert = args.includes('--revert');

	console.log(revert ? '== reverting steering hot patch ==' : '== patching steering hot patch ==');

	let failures = 0;
	for (const file of TARGETS) {
		const result = revert ? revertFile(file) : patchFile(file, dryRun);
		const rel = path.basename(path.dirname(file)) + '/' + path.basename(file);
		console.log(`  ${rel}: ${result.status}${result.hits ? ` (${result.hits} call site(s))` : ''}`);
		if (result.status === 'missing' || result.status === 'no-match') {
			failures++;
		}
	}

	console.log('');
	if (revert) {
		console.log('Backups restored. Restart Mobius to reload the original bundles.');
	} else if (dryRun) {
		console.log('Dry run only — nothing written.');
	} else {
		console.log('Done. Fully quit Mobius (all windows) and start it again for the patch to load.');
		console.log(`Revert with: node ${path.basename(__filename)} --revert`);
	}
	if (failures > 0) {
		console.log(`\nNOTE: ${failures} bundle(s) did not match. The app may have been updated — rebuild anchors before retrying.`);
	}
}

main();