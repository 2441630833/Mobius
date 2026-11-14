// Prints every context where a language model advertises vision capability,
// so we can see which code path sets `capabilities.vision`.
// Usage: node scripts/dump-vision-sites.js [bundle]
const fs = require('fs');
const path = require('path');

const file =
	process.argv[2] ||
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

const text = fs.readFileSync(file, 'utf8');
const patterns = ['vision:', 'supportsVision', 'image_input'];
let shown = 0;

for (const pattern of patterns) {
	let idx = -1;
	let hits = 0;
	console.log('########## ' + pattern + ' ##########');
	while ((idx = text.indexOf(pattern, idx + 1)) >= 0) {
		hits++;
		if (shown < 40) {
			const start = Math.max(0, idx - 220);
			const end = Math.min(text.length, idx + 220);
			console.log('--- @' + idx + ' ---');
			console.log(text.slice(start, end).replace(/\n/g, ' '));
			shown++;
		}
	}
	console.log('hits=' + hits);
	console.log('');
}