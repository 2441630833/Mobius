// Apply the source branding fix to an existing Mobius installation.
// Usage: node scripts/patch-ide-branding.mjs [resources/app directory]
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

if (!process.argv[2] && !process.env.LOCALAPPDATA) {
	throw new Error('Pass the installed Mobius resources/app directory.');
}
const appRoot = path.resolve(process.argv[2] ?? path.join(process.env.LOCALAPPDATA, 'Programs/Mobius/resources/app'));
const productPath = path.join(appRoot, 'product.json');
const productText = fs.readFileSync(productPath, 'utf8');
const product = JSON.parse(productText);
if (product.nameShort !== 'Mobius') {
	throw new Error(`Expected a Mobius installation at ${appRoot}`);
}

// Prepare every replacement before changing any installed files.
const edits = new Map();
const brandPattern = String.raw`\b(?:Visual Studio Code|VS Code|Code - OSS)\b`;
const marker = '/* mobius-product-branding */';
for (const bundle of ['workbench/workbench', 'sessions/sessions']) {
	const jsPath = path.join(appRoot, 'out/vs', `${bundle}.desktop.main.js`);
	const source = fs.readFileSync(jsPath, 'utf8');
	if (source.includes(marker) || source.includes(brandPattern)) {
		continue;
	}
	// Identify the minified NLS formatter by its zero-argument/placeholder branches.
	// Do not depend on generated function or variable names.
	const formatter = /function [\w$]+\(([\w$]+),([\w$]+)\)\{(?=let ([\w$]+);return \2\.length===0\?\3=\1:\3=\1\.replace\(\/\\\{\(\\d\+\)\\\}\/g,)/g;
	let matches = 0;
	const updated = source.replace(formatter, (header, message) => {
		matches++;
		return `${header}${marker}${message}=${message}.replace(/${brandPattern}/g,"Mobius");`;
	});
	if (matches !== 1) {
		throw new Error(`Expected one NLS formatter in ${jsPath}, found ${matches}. Rebuild this version from source.`);
	}
	edits.set(jsPath, updated);
}

const logoPath = path.join(appRoot, 'out/media/logo.png');
if (!fs.existsSync(logoPath)) {
	throw new Error(`Missing installed Mobius logo: ${logoPath}`);
}
const cssPath = path.join(appRoot, 'out/vs/workbench/workbench.desktop.main.css');
const css = fs.readFileSync(cssPath, 'utf8');
let watermarks = 0;
const updatedCss = css.replace(/([^{}]*\.editor-group-watermark\s+\.letterpress)\{([^}]*)\}/g, (_rule, selector, body) => {
	watermarks++;
	const opacity = /\.hc-(?:light|black)\b/.test(selector) ? 1 : selector.includes('.vs-dark') ? 0.3 : 0.25;
	const declarations = body.replace(/(?:background-image|background-position-x|background-position|opacity)\s*:[^;}]*(?:;|$)/g, '');
	return `${selector}{${declarations}${declarations.endsWith(';') ? '' : ';'}background-image:url("../../media/logo.png");background-position:center;opacity:${opacity}}`;
});
if (watermarks !== 4) {
	throw new Error(`Expected four editor watermark theme rules, found ${watermarks}.`);
}
if (updatedCss !== css) {
	edits.set(cssPath, updatedCss);
}

for (const keymap of product.onboardingKeymaps ?? []) {
	if (keymap.id === 'vscode' && keymap.label === 'VS Code') {
		keymap.label = 'Mobius';
	}
}
// Keep the installed resource integrity metadata in sync with these edits.
for (const relative of ['vs/workbench/workbench.desktop.main.js', 'vs/sessions/sessions.desktop.main.js', 'vs/workbench/workbench.desktop.main.css']) {
	if (product.checksums?.[relative]) {
		const file = path.join(appRoot, 'out', relative);
		const content = edits.get(file) ?? fs.readFileSync(file);
		product.checksums[relative] = createHash('sha256').update(content).digest('base64').replace(/=+$/, '');
	}
}
const updatedProduct = `${JSON.stringify(product, null, '\t')}\n`;
if (updatedProduct !== productText) {
	edits.set(productPath, updatedProduct);
}

for (const [file, content] of edits) {
	const backup = `${file}.mobius-branding.bak`;
	if (!fs.existsSync(backup)) {
		fs.copyFileSync(file, backup);
	}
	fs.writeFileSync(file, content, 'utf8');
	console.log(`Updated ${file}`);
}
console.log(edits.size ? 'Mobius branding updated. Reload the IDE window to see the changes.' : 'Mobius branding is already current.');
