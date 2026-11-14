// Scans an installed Mobius workbench bundle for vision-gate fingerprints.
// Usage: node scripts/vision-bundle-check.js [path-to-workbench.desktop.main.js]
const fs = require('fs');
const path = require('path');

const defaultPath = path.join(
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

const target = process.argv[2] || defaultPath;
const keys = [
	'MOBIUS_VISION_PATCH',
	'does not declare image support',
	'Image request cancelled',
	'Send Images Anyway',
	'send images anyway',
	'capabilities?.vision===!0',
	'confirmLocalOcrForImages',
	'resolveModelVision',
	'vscode-chat-images',
];

if (!fs.existsSync(target)) {
	console.error('MISSING ' + target);
	process.exit(2);
}

const text = fs.readFileSync(target, 'utf8');
console.log('file   ' + target);
console.log('size   ' + (text.length / 1024 / 1024).toFixed(2) + ' MB chars');
console.log('');
for (const key of keys) {
	let count = 0;
	let idx = -1;
	while ((idx = text.indexOf(key, idx + 1)) >= 0) {
		count++;
	}
	console.log(String(count).padStart(3) + '  ' + JSON.stringify(key));
}