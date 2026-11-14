// Locates Mobius installations whose workbench bundle actually contains the
// OCR/vision gate, so hot patches target the copy that is really running.
// Usage: node scripts/find-vision-bundle.js
const fs = require('fs');
const path = require('path');

const needle = 'does not declare image support';
const altNeedle = 'Image request cancelled';

const roots = [
	path.join(process.env.LOCALAPPDATA || '', 'Programs'),
	path.join(process.env.PROGRAMFILES || '', ''),
	path.join(process.env['PROGRAMFILES(X86)'] || '', ''),
	'E:\\MobiusCode\\Mobius',
	process.env.USERPROFILE || '',
];

function walk(dir, depth, out) {
	if (depth > 4 || out.length > 200) {
		return;
	}
	let entries;
	try {
		entries = fs.readdirSync(dir, { withFileTypes: true });
	} catch {
		return;
	}
	for (const entry of entries) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === 'node_modules' || entry.name === '.git' || entry.name === 'out' ) {
				// 'out' may hold the bundle we want, handled below
				if (entry.name !== 'out') {
					continue;
				}
			}
			walk(full, depth + 1, out);
		} else if (entry.name === 'workbench.desktop.main.js') {
			out.push(full);
		}
	}
}

const bundles = [];
for (const root of roots) {
	if (root && fs.existsSync(root)) {
		walk(root, 0, bundles);
	}
}

console.log('candidate bundles: ' + bundles.length);
for (const file of bundles) {
	let text;
	try {
		text = fs.readFileSync(file, 'utf8');
	} catch {
		console.log('unreadable ' + file);
		continue;
	}
	const hasOcr = text.includes(needle);
	const hasCancel = text.includes(altNeedle);
	const hasPatch = text.includes('MOBIUS_VISION_PATCH');
	const hasChatImages = text.includes('vscode-chat-images');
	const mtime = fs.statSync(file).mtime.toISOString();
	console.log(
		[
			hasOcr ? 'OCR-GATE' : 'no-gate ',
			hasCancel ? 'cancel-msg' : 'no-cancel ',
			hasPatch ? 'PATCHED' : 'unpatched',
			hasChatImages ? 'chat-images' : '-',
			mtime,
			file,
		].join(' | '),
	);
}