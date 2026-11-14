// Finds which bundle/source file owns the OCR consent gate, including the
// localized-string tables that hold the user-visible English text.
// Usage: node scripts/find-ocr-gate-source.js
const fs = require('fs');
const path = require('path');

const needles = [
	'does not declare image support',
	'Enable local OCR',
	'Image request cancelled',
	'select a multimodal model',
	'ocr.declined',
	'confirmLocalOcrForImages',
];

const roots = [
	path.join(process.env.LOCALAPPDATA || '', 'Programs', 'Mobius', 'resources', 'app'),
	path.join('E:\\MobiusCode\\Mobius', 'continue', 'extensions', 'vscode', 'src'),
	path.join('E:\\MobiusCode\\Mobius', 'continue', 'core'),
	path.join('E:\\MobiusCode\\Mobius', 'vscode', 'src', 'vs', 'workbench', 'contrib', 'continue'),
];

const exts = new Set(['.js', '.ts', '.json', '.mjs']);
const skipDirs = new Set(['node_modules', '.git', '.vscode-test']);

const hits = [];
let scanned = 0;

function walk(dir, depth) {
	if (depth > 8 || hits.length > 120) {
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
			if (!skipDirs.has(entry.name)) {
				walk(full, depth + 1);
			}
			continue;
		}
		if (!exts.has(path.extname(entry.name))) {
			continue;
		}
		let stat;
		try {
			stat = fs.statSync(full);
		} catch {
			continue;
		}
		if (stat.size > 80 * 1024 * 1024) {
			continue;
		}
		let text;
		try {
			text = fs.readFileSync(full, 'utf8');
		} catch {
			continue;
		}
		scanned++;
		for (const needle of needles) {
			if (text.includes(needle)) {
				let count = 0;
				let idx = -1;
				while ((idx = text.indexOf(needle, idx + 1)) >= 0) {
					count++;
				}
				hits.push({ file: full, needle, count });
			}
		}
	}
}

for (const root of roots) {
	if (fs.existsSync(root)) {
		walk(root, 0);
	}
}

console.log('scanned files: ' + scanned);
console.log('');
if (hits.length === 0) {
	console.log('no hits');
} else {
	const grouped = new Map();
	for (const hit of hits) {
		const key = hit.file;
		if (!grouped.has(key)) {
			grouped.set(key, []);
		}
		grouped.get(key).push(hit.needle + ' x' + hit.count);
	}
	for (const [file, found] of grouped) {
		console.log(file);
		console.log('    ' + found.join(' | '));
	}
}