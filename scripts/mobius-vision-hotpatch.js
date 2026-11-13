#!/usr/bin/env node
/*
 * mobius-vision-hotpatch.js
 *
 * Local hot patch for the Mobius/Continue image-capability gate.
 *
 * Symptom it removes:
 *   "Enable local OCR for this model? <model> does not declare image support."
 *   -> "Image request cancelled. Enable local OCR or select a multimodal
 *      model before resending."
 *
 * Root cause (compiled build, out/vs/workbench/workbench.desktop.main.js):
 *
 *   let gx = this._languageModelsService.lookupLanguageModel(n),
 *       Hr  = gx?.capabilities?.vision === !0;              // <- gating flag
 *   if (!Hr && Cg.length > 0) { warn(...); return {}; }
 *   if (!await WHo(zl.length, Hr, gx?.family ?? n, ...)) { ...cancel... }
 *
 *   WHo() shows the local-OCR dialog and, on cancel, the request is dropped,
 *   so images never reach a model that is perfectly able to read them.
 *
 * The patch forces Hr = true, which makes Mobius take the real image path
 * (VUo -> image parts) instead of the OCR-text fallback.
 *
 * Usage:
 *   node scripts/mobius-vision-hotpatch.js            # report only
 *   node scripts/mobius-vision-hotpatch.js --apply    # patch installs
 *   node scripts/mobius-vision-hotpatch.js --restore  # undo
 *   node scripts/mobius-vision-hotpatch.js --apply --root "D:\\Mobius"
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

const WORKBENCH = path.join('resources', 'app', 'out', 'vs', 'workbench', 'workbench.desktop.main.js');

const MARKER = 'MOBIUS_VISION_PATCH';

/*
 * Each entry is [anchor, replacement]. Anchors are taken verbatim from the
 * shipped workbench bundle (no whitespace to guess).
 *
 *  1) agent-host model list: the server flag defaulted to "no vision".
 *  2) chat agent gate:      Hr (supportsVision) drives the OCR dialog.
 *  3) chat model helper:    Joo() feeds the UI/attachment capability checks.
 */
const PATCHES = [
    {
        name: 'agent-host model capability',
        from: 'vision:o.supportsVision??!1',
        to: 'vision:!0/*MOBIUS_VISION_PATCH*/',
    },
    {
        name: 'chat agent vision gate',
        from: ',gx=this._languageModelsService.lookupLanguageModel(n),Hr=gx?.capabilities?.vision===!0;',
        to: ',gx=this._languageModelsService.lookupLanguageModel(n),Hr=!0/*MOBIUS_VISION_PATCH*/;',
    },
    {
        name: 'chat model metadata helper',
        from: 'function jOo(s){return s?.metadata.capabilities?.vision??!1}',
        to: 'function jOo(s){return!0/*MOBIUS_VISION_PATCH*/}',
    },
];

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const restore = args.includes('--restore');
const rootArgIdx = args.indexOf('--root');
const explicitRoot = rootArgIdx >= 0 ? args[rootArgIdx + 1] : undefined;

function candidateRoots() {
    if (explicitRoot) return explicitRoot.split(';').filter(Boolean);

    const out = new Set();
    const local = process.env.LOCALAPPDATA;
    const pf = process.env.ProgramFiles;
    const pf86 = process.env['ProgramFiles(x86)'];

    for (const base of [local && path.join(local, 'Programs'), local, pf, pf86]) {
        if (!base) continue;
        for (const name of ['Mobius', 'MobiusCode', 'Mobius - Insiders']) {
            const p = path.join(base, name);
            if (fs.existsSync(path.join(p, 'resources', 'app'))) out.add(p);
        }
    }

    // repo build outputs (gulp vscode-win32-x64 etc.)
    const repo = path.resolve(__dirname, '..');
    for (const e of fs.readdirSync(repo, { withFileTypes: true })) {
        if (!e.isDirectory() || !/win32/i.test(e.name)) continue;
        const dir = path.join(repo, e.name);
        const direct = path.join(dir, 'resources', 'app');
        if (fs.existsSync(direct)) out.add(dir);
    }
    return [...out];
}

function count(haystack, needle) {
    return haystack.split(needle).length - 1;
}

function state(file) {
    const text = fs.readFileSync(file, 'utf8');
    return {
        text,
        hasPatched: text.includes(MARKER),
        counts: PATCHES.map((p) => count(text, p.from)),
    };
}

function patch(file) {
    const { text, hasPatched, counts } = state(file);
    if (hasPatched) return ['already patched'];

    for (let i = 0; i < PATCHES.length; i++) {
        if (counts[i] !== 1) {
            return [
                `ABORT: anchor "${PATCHES[i].name}" matched ${counts[i]}x (expected 1) - build version differs`,
            ];
        }
    }

    const backup = file + '.bak-vision';
    if (!fs.existsSync(backup)) fs.copyFileSync(file, backup);

    let out = text;
    const log = [];
    for (const p of PATCHES) {
        out = out.replace(p.from, p.to);
        log.push(`patched: ${p.name}`);
    }

    fs.writeFileSync(file, out, 'utf8');
    return log;
}

function unpatch(file) {
    const backup = file + '.bak-vision';
    if (!fs.existsSync(backup)) return 'no backup - nothing to restore';
    fs.copyFileSync(backup, file);
    fs.unlinkSync(backup);
    return 'RESTORED';
}

const roots = candidateRoots();
if (roots.length === 0) {
    console.log('No Mobius installation found. Use --root "<folder containing resources\\app>".');
    process.exit(2);
}

let failures = 0;
for (const root of roots) {
    const file = path.join(root, WORKBENCH);
    console.log(`=== ${root}`);
    if (!fs.existsSync(file)) {
        console.log('    workbench bundle missing - skipped');
        continue;
    }
    if (restore) {
        console.log('    ' + unpatch(file));
        continue;
    }
    if (apply) {
        const lines = patch(file);
        if (lines.some((l) => l.startsWith('ABORT'))) failures++;
        lines.forEach((l) => console.log('    ' + l));
        continue;
    }
    const s = state(file);
    console.log(`    size    : ${(fs.statSync(file).size / 1024 / 1024).toFixed(1)} MB`);
    console.log(`    patched : ${s.hasPatched}`);
    PATCHES.forEach((p, i) => console.log(`    ${s.counts[i]}x      : ${p.name}`));
}

if (failures) process.exit(1);