// Prints context around every occurrence of a needle in any text file.
// Usage: node scripts/dump-needle.js <file> <needle> [before] [after] [maxHits]
const fs = require('fs');

const [, , file, needle, beforeArg, afterArg, maxArg] = process.argv;
if (!file || !needle) {
	console.error('usage: node scripts/dump-needle.js <file> <needle> [before] [after] [maxHits]');
	process.exit(1);
}

const before = Number(beforeArg || 240);
const after = Number(afterArg || 240);
const maxHits = Number(maxArg || 20);

const text = fs.readFileSync(file, 'utf8');
let idx = -1;
let hits = 0;

while ((idx = text.indexOf(needle, idx + 1)) >= 0) {
	hits++;
	if (hits <= maxHits) {
		const start = Math.max(0, idx - before);
		const end = Math.min(text.length, idx + after);
		console.log('===== hit ' + hits + ' @' + idx + ' =====');
		console.log(text.slice(start, end).replace(/\n/g, ' '));
		console.log('');
	}
}

console.log('total hits: ' + hits);