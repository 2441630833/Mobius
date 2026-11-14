/**
 * Installs a locally built workbench bundle into the running Mobius
 * installation (the "compile locally, then update in place" path).
 *
 * Source:  vscode/out-vscode-min/vs/workbench/workbench.desktop.main.js
 * Target:  %LOCALAPPDATA%\Programs\Mobius\resources\app\out\vs\workbench\...
 *
 * Safety:
 *  - refuses to install when the freshly built bundle still contains the
 *    `supportsVision ?? false` gate (i.e. the fix is missing)
 *  - keeps a timestamped backup next to the target
 *  - `--revert` restores the newest backup
 *
 * Usage:
 *   node scripts/install-local-bundle.js --check
 *   node scripts/install-local-bundle.js --install
 *   node scripts/install-local-bundle.js --revert
 */
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const source = path.join(repoRoot, 'vscode', 'out-vscode-min', 'vs', 'workbench', 'workbench.desktop.main.js');
const targetRoot = path.join(
	process.env.LOCALAPPDATA || '',
	'Programs',
	'Mobius',
	'resources',
	'app',
	'out',
	'vs',
	'workbench',
);
const target = path.join(targetRoot, 'workbench.desktop.main.js');

const UNPATCHED_MARKER = 'supportsVision??!1';
const PATCHED_MARKER = 'TIGNN_STRICT_VISION';

function stats(file) {
	const stat = fs.statSync(file);
	return `${(stat.size / 1024 / 1024).toFixed(2)} MB, ${stat.mtime.toISOString()}`;
}

function fingerprint(file) {
	const text = fs.readFileSync(file, 'utf8');
	return {
		size: (text.length / 1024 / 1024).toFixed(2) + ' MB chars',
		hasUnpatchedGate: text.includes(UNPATCHED_MARKER),
		hasResolver: text.includes(PATCHED_MARKER),
	};
}

const mode = process.argv[2] || '--check';

if (!fs.existsSync(source)) {
	console.error('missing locally built bundle: ' + source);
	console.error('run: cd vscode && npx gulp minify-vscode');
	process.exit(2);
}

console.log('source ' + source);
console.log('       ' + stats(source));
const sourceInfo = fingerprint(source);
console.log('       unpatchedGate=' + sourceInfo.hasUnpatchedGate + ' resolver=' + sourceInfo.hasResolver);
console.log('target ' + target);
if (fs.existsSync(target)) {
	console.log('       ' + stats(target));
}

switch (mode) {
	case '--check': {
		const ok = sourceInfo.hasResolver && !sourceInfo.hasUnpatchedGate;
		console.log('');
		console.log(ok ? 'READY: built bundle contains the resolver' : 'NOT READY: built bundle predates the fix');
		process.exit(ok ? 0 : 3);
		break;
	}
	case '--install': {
		if (!sourceInfo.hasResolver || sourceInfo.hasUnpatchedGate) {
			console.error('refusing to install: built bundle predates the fix');
			process.exit(3);
		}
		if (!fs.existsSync(targetRoot)) {
			console.error('missing target folder: ' + targetRoot);
			process.exit(4);
		}
		if (fs.existsSync(target)) {
			const backup = target + '.bak-localinstall-' + Date.now();
			fs.copyFileSync(target, backup);
			console.log('backup ' + backup);
		}
		fs.copyFileSync(source, target);
		console.log('installed ' + target);
		console.log('');
		const after = fingerprint(target);
		console.log('verify unpatchedGate=' + after.hasUnpatchedGate + ' resolver=' + after.hasResolver);
		break;
	}
	case '--revert': {
		const backups = fs
			.readdirSync(targetRoot)
			.filter(name => name.startsWith('workbench.desktop.main.js.bak-'))
			.sort();
		if (backups.length === 0) {
			console.error('no backups found in ' + targetRoot);
			process.exit(5);
		}
		const newest = path.join(targetRoot, backups[backups.length - 1]);
		fs.copyFileSync(newest, target);
		console.log('reverted from ' + newest);
		break;
	}
	default: {
		console.error('unknown mode: ' + mode);
		process.exit(1);
	}
}