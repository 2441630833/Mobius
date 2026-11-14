/**
 * Hot patches the *installed* Mobius workbench bundle so that models which do
 * not report `supportsVision` are no longer treated as text-only.
 *
 * Two surgical, idempotent replacements:
 *   1. `vision:X.supportsVision ?? false`  ->  `vision:!0`
 *      (agent-host language model provider: user-configured endpoints such as
 *      the Continue `ali` entry never appear in the upstream model catalogue,
 *      so the flag arrived as `undefined` and every pasted image was swallowed)
 *   2. `Hr = model?.capabilities?.vision === !0`  ->  `Hr = !0`
 *      (Continue chat agent: the OCR-consent gate itself, which cancelled the
 *      request whenever the flag above was false)
 *
 * Usage:
 *   node scripts/hotpatch-agent-vision.js --verify
 *   node scripts/hotpatch-agent-vision.js --apply
 *   node scripts/hotpatch-agent-vision.js --revert
 *
 * Optional: pass a bundle path as the second argument to target a specific
 * installation (defaults to %LOCALAPPDATA%\Programs\Mobius\...).
 */
const fs = require('fs');
const path = require('path');

const MODE = process.argv[2] || '--verify';
const target =
	process.argv[3] ||
	path.join(
		process.env.LOCALAPPDATA || '',
		'Programs',
		'Mobius',
		'resources',
		'app',
		'out',
		'vs',
		'workbench',
		'workbench.desktop.main.js',
	);

const backup = target + '.bak-agentvision';

const RULES = [
	{
		name: 'agent-host provider: vision flag',
		// vision:<ident>.supportsVision??!1  ->  vision:!0
		pattern: /vision:([A-Za-z_$][\w$]*)\.supportsVision\?\?!1/g,
		replace: () => 'vision:!0',
		applied: /vision:!0/,
	},
	{
		name: 'continue agent: OCR gate',
		// <ident>=<ident>?.capabilities?.vision===!0  ->  <ident>=!0
		pattern: /([A-Za-z_$][\w$]*)=([A-Za-z_$][\w$]*)\?\.capabilities\?\.vision===!0/g,
		replace: (_match, lhs) => `${lhs}=!0`,
		applied: /(?:^|[^.\w$])[A-Za-z_$][\w$]*=!0;/,
	},
];

if (!fs.existsSync(target)) {
	console.error('MISSING bundle: ' + target);
	process.exit(2);
}

function read() {
	return fs.readFileSync(target, 'utf8');
}

function report(text) {
	console.log('bundle  ' + target);
	console.log('size    ' + (text.length / 1024 / 1024).toFixed(2) + ' MB');
	console.log('');
	for (const rule of RULES) {
		rule.pattern.lastIndex = 0;
		const matches = text.match(rule.pattern);
		const count = matches ? matches.length : 0;
		console.log(`${count === 0 ? 'PATCHED ' : 'PENDING '}  ${rule.name}  (matches=${count})`);
	}
}

switch (MODE) {
	case '--verify': {
		report(read());
		break;
	}
	case '--apply': {
		const original = read();
		let next = original;
		for (const rule of RULES) {
			rule.pattern.lastIndex = 0;
			next = next.replace(rule.pattern, rule.replace);
		}
		if (next === original) {
			console.log('nothing to do (already patched)');
			report(original);
			break;
		}
		if (!fs.existsSync(backup)) {
			fs.writeFileSync(backup, original);
			console.log('backup  ' + backup);
		}
		fs.writeFileSync(target, next);
		console.log('written ' + target);
		console.log('');
		report(next);
		break;
	}
	case '--revert': {
		if (!fs.existsSync(backup)) {
			console.error('no backup found: ' + backup);
			process.exit(3);
		}
		fs.writeFileSync(target, fs.readFileSync(backup, 'utf8'));
		console.log('reverted from ' + backup);
		report(read());
		break;
	}
	default: {
		console.error('unknown mode: ' + MODE);
		console.error('use --verify | --apply | --revert');
		process.exit(1);
	}
}