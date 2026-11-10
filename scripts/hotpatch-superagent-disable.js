/*
 * Hot patch: retire Super Agent in the *installed* Mobius build.
 *
 * The source changes (default off + no UI entry) only reach the app after a full
 * rebuild. This patches the shipped workbench bundle so the running install stops
 * routing to Super Agent and stops showing its button/status bar item.
 *
 * Usage:  node scripts/hotpatch-superagent-disable.js [path-to-workbench.desktop.main.js]
 * Re-runnable: already-patched anchors are detected and skipped.
 * Restore: copy the *.bak-superagent file back over the bundle.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const target = process.argv[2] || path.join(
	process.env.LOCALAPPDATA || '',
	'Programs', 'Mobius', 'resources', 'app', 'out', 'vs', 'workbench', 'workbench.desktop.main.js',
);

if (!fs.existsSync(target)) {
	console.error(`Target not found: ${target}`);
	process.exit(1);
}

/** [label, before, after] */
const patches = [
	[
		'route command: hard-disable (returns {handled:false} immediately)',
		'if(!t.getValue("mobius.superagent.autoRoute")||i.root.scheme!=="file"||!l.isWorkspaceTrusted())return{handled:!1};',
		'if(!0||i.root.scheme!=="file"||!l.isWorkspaceTrusted())return{handled:!1};',
	],
	[
		'setting default: true -> false',
		'"mobius.superagent.autoRoute":{type:"boolean",default:!0,',
		'"mobius.superagent.autoRoute":{type:"boolean",default:!1,',
	],
	[
		'chat input menu: remove the Super Agent button',
		'menu:[{id:A.ChatInput,group:"navigation",order:7}]',
		'menu:[]',
	],
	[
		'status bar: drop the Super Agent entry',
		'i.addEntry({...r,tooltip:d(11332,null)},mce.ID,1,50)',
		'{update(){},dispose(){}}',
	],
];

const original = fs.readFileSync(target, 'utf8');
let next = original;
let applied = 0;

for (const [label, before, after] of patches) {
	const beforeCount = next.split(before).length - 1;
	const afterCount = next.split(after).length - 1;
	if (afterCount > 0 && beforeCount === 0) {
		console.log(`skip    ${label} (already patched)`);
		continue;
	}
	if (beforeCount !== 1) {
		console.error(`abort   ${label}: expected exactly 1 anchor, found ${beforeCount}`);
		process.exit(2);
	}
	next = next.split(before).join(after);
	applied++;
	console.log(`patched ${label}`);
}

if (applied === 0) {
	console.log('Nothing to do — bundle already patched.');
	process.exit(0);
}

const backup = `${target}.bak-superagent`;
if (!fs.existsSync(backup)) {
	fs.writeFileSync(backup, original, 'utf8');
	console.log(`backup  ${backup}`);
}

fs.writeFileSync(target, next, 'utf8');
console.log(`wrote   ${target} (${next.length} bytes, ${applied} patch(es))`);
console.log('Fully quit Mobius and start it again for the patch to load.');