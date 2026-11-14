// Dumps the code context around the vision-capability read in a Mobius bundle.
// Usage: node scripts/dump-gate-context.js [needle] [before] [after]
const fs = require('fs');
const path = require('path');

const file = path.join(
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

const needle = process.argv[2] || 'capabilities?.vision===!0';
const before = Number(process.argv[3] || 700);
const after = Number(process.argv[4] || 900);

const text = fs.readFileSync(file, 'utf8');
let idx = -1;
let n = 0;
while ((idx = text.indexOf(needle, idx + 1)) >= 0) {
	n++;
	const start = Math.max(0, idx - before);
	const end = Math.min(text.length, idx + after);
	console.log('===== hit ' + n + ' @' + idx + ' =====');
	console.log(text.slice(start, end));
	console.log('');
}
console.log('total hits: ' + n);