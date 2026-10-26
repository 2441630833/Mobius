// Apply recommended extensions fallback & tips fix to a Mobius installation or build.
// Usage: node scripts/patch-ide-recommendations.mjs [resources/app directory]
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';

const targetArg = process.argv[2];
let appRoot;
if (targetArg) {
	appRoot = path.resolve(targetArg);
} else if (process.env.LOCALAPPDATA) {
	appRoot = path.resolve(path.join(process.env.LOCALAPPDATA, 'Programs/Mobius/resources/app'));
} else {
	throw new Error('Pass the installed Mobius resources/app directory.');
}

const productPath = path.join(appRoot, 'product.json');
if (!fs.existsSync(productPath)) {
	throw new Error(`product.json not found at ${productPath}`);
}

const sourceProductPath = path.resolve('vscode/product.json');
const sourceProduct = JSON.parse(fs.readFileSync(sourceProductPath, 'utf8'));
const targetProduct = JSON.parse(fs.readFileSync(productPath, 'utf8'));

// 1. Merge tip and recommendation configurations into product.json
const tipKeys = [
	'extensionRecommendations',
	'configBasedExtensionTips',
	'exeBasedExtensionTips',
	'keymapExtensionTips',
	'languageExtensionTips',
	'remoteExtensionTips',
	'virtualWorkspaceExtensionTips',
	'webExtensionTips'
];

let productModified = false;
for (const key of tipKeys) {
	if (sourceProduct[key]) {
		targetProduct[key] = sourceProduct[key];
		productModified = true;
	}
}

// 2. Patch workbench.desktop.main.js
const jsPath = path.join(appRoot, 'out/vs/workbench/workbench.desktop.main.js');
if (!fs.existsSync(jsPath)) {
	throw new Error(`workbench.desktop.main.js not found at ${jsPath}`);
}

let jsSource = fs.readFileSync(jsPath, 'utf8');
const marker = '/* mobius-recommendations-fix */';
let jsModified = false;

// Remove old marker if updating
if (jsSource.startsWith(marker)) {
	jsSource = jsSource.slice(marker.length).trimStart();
}

// Pattern 1: In getAllRecommendationsModel(e,t), fallback to gallery popular extensions when result is empty
if (!jsSource.includes('recommendations-all-fallback')) {
	const regex1 = /return new ([A-Za-z0-9_$]+)\(c\)\}async searchRecommendations/;
	if (regex1.test(jsSource)) {
		jsSource = jsSource.replace(regex1, (_m, modelClass) => {
			return `if(c.length===0){try{let p=await this.extensionsWorkbenchService.queryGallery({...e,sortBy:4,pageSize:8,source:"recommendations-all-fallback"},t),m=p.firstPage.filter(g=>!n.includes(g.identifier.id.toLowerCase()));if(m.length)return new ${modelClass}(m.slice(0,8))}catch{}}return new ${modelClass}(c)}async searchRecommendations`;
		});
		jsModified = true;
		console.log('Patched Pattern 1 (getAllRecommendationsModel fallback)');
	} else {
		console.log('Pattern 1 regex not matched');
	}
} else {
	console.log('Pattern 1 already patched');
}

// Pattern 2: In getOtherRecommendationsModel(e,t,o), fallback when result is empty
if (!jsSource.includes('recommendations-other-fallback')) {
	const regex2 = /,a=([A-Za-z0-9_$]+)\(n\.map\(c=>r\.find\(l=>([A-Za-z0-9_$]+)\(l\.identifier,\{id:c\}\)\)\)\);return new ([A-Za-z0-9_$]+)\(a\)\}/;
	if (regex2.test(jsSource)) {
		jsSource = jsSource.replace(regex2, (_m, coalesceFn, sameExtFn, modelClass) => {
			return `,a=${coalesceFn}(n.map(c=>r.find(l=>${sameExtFn}(l.identifier,{id:c}))));if(a.length===0){try{let p=await this.extensionsWorkbenchService.queryGallery({...t,sortBy:4,pageSize:8,source:"recommendations-other-fallback"},o),m=(await this.extensionsWorkbenchService.queryLocal(this.options.server)).map(g=>g.identifier.id.toLowerCase()),g=p.firstPage.filter(f=>!m.includes(f.identifier.id.toLowerCase()));if(g.length)return new ${modelClass}(g.slice(0,8))}catch{}}return new ${modelClass}(a)}`;
		});
		jsModified = true;
		console.log('Patched Pattern 2 (getOtherRecommendationsModel fallback)');
	} else {
		console.log('Pattern 2 regex not matched');
	}
} else {
	console.log('Pattern 2 already patched');
}

// Pattern 3: In DefaultRecommendedExtensionsView.show, collapse when model.length === 0
if (!jsSource.includes('t.length===0&&this.setExpanded(!1)')) {
	const regex3 = /return this\.extensionsWorkbenchService\.local\.some\(o=>!o\.isBuiltin\)\|\|this\.setExpanded\(t\.length>0\),t\}/;
	if (regex3.test(jsSource)) {
		jsSource = jsSource.replace(regex3, 'return !this.extensionsWorkbenchService.local.some(o=>!o.isBuiltin)?this.setExpanded(t.length>0):t.length===0&&this.setExpanded(!1),t}');
		jsModified = true;
		console.log('Patched Pattern 3 (DefaultRecommendedExtensionsView collapse on empty)');
	} else {
		console.log('Pattern 3 regex not matched');
	}
} else {
	console.log('Pattern 3 already patched');
}

if (jsModified) {
	jsSource = `${marker}\n${jsSource}`;
	const backup = `${jsPath}.mobius-rec.bak`;
	if (!fs.existsSync(backup)) {
		fs.copyFileSync(jsPath, backup);
	}
	fs.writeFileSync(jsPath, jsSource, 'utf8');
	console.log(`Updated ${jsPath}`);
}

// 3. Update checksums in product.json
if (targetProduct.checksums && targetProduct.checksums['vs/workbench/workbench.desktop.main.js']) {
	const currentContent = fs.readFileSync(jsPath);
	targetProduct.checksums['vs/workbench/workbench.desktop.main.js'] = createHash('sha256').update(currentContent).digest('base64').replace(/=+$/, '');
	productModified = true;
}

if (productModified) {
	fs.writeFileSync(productPath, `${JSON.stringify(targetProduct, null, '\t')}\n`, 'utf8');
	console.log(`Updated ${productPath}`);
}

console.log(`Recommendations fix successfully applied to ${appRoot}`);
