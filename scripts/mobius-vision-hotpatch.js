#!/usr/bin/env node
/*
 * mobius-vision-hotpatch.js
 *
 * Local hot patch for the Mobius/Continue image-capability gate, OCR retirement,
 * and removing the robot icon from the chat input area.
 *
 * Changes:
 *   1) agent-host model capability: vision defaults to true
 *   2) chat agent vision gate: Hr defaults to true
 *   3) chat model metadata helper: jOo returns true
 *   4) chat agent OCR consent prompt: WHo returns true (no OCR prompt/detour)
 *   5) chat input toolbar: remove local OCR toggle button
 *   6) chat input mode picker: remove robot icon from Agent mode
 *   7) CSS: hide .codicon-mobius-mode-agent
 *   8) delete local GLM-OCR ONNX model weights
 *
 * Usage:
 *   node scripts/mobius-vision-hotpatch.js            # report only
 *   node scripts/mobius-vision-hotpatch.js --apply    # patch installs
 *   node scripts/mobius-vision-hotpatch.js --restore  # undo
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

const WORKBENCH = path.join('resources', 'app', 'out', 'vs', 'workbench', 'workbench.desktop.main.js');
const WORKBENCH_CSS = path.join('resources', 'app', 'out', 'vs', 'workbench', 'workbench.desktop.main.css');

const MARKER = 'MOBIUS_VISION_PATCH';

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
    {
        name: 'chat agent OCR consent prompt (always allow vision)',
        from: 'async function WHo(s,i,e,t,o,n){return n.isCancellationRequested?!1:!s||i||t.getValue(BH)===!0?!0:!(await o.confirm({message:d(11297,null),detail:d(11296,null,e),primaryButton:d(11295,null),cancelButton:d(11294,null)})).confirmed||n.isCancellationRequested?!1:(await t.updateValue(BH,!0,2),!n.isCancellationRequested)}',
        to: 'async function WHo(){return!0/*MOBIUS_VISION_PATCH*/}',
    },
    {
        name: 'chat input menu: remove OCR toolbar button',
        from: 'menu:[{id:A.ChatInput,group:"navigation",order:5,when:x.and(oe.location.isEqualTo("panel"),oe.inQuickChat.negate())},{id:A.ChatExecute,group:"navigation",order:3,when:x.and(oe.location.isEqualTo("panel"),x.or(oe.inQuickChat,oe.location.isEqualTo("editor")))}]',
        to: 'menu:[]/*MOBIUS_VISION_PATCH*/',
    },
    {
        name: 'chat input mode picker: remove robot icon from Agent mode',
        from: 'function gpt(s){return l1i(s)?nLn:d1i(s)?rLn:u1i(s)?sLn:LQt(s)?JFo:s.icon.get()??JFo}',
        to: 'function gpt(s){return l1i(s)?nLn:d1i(s)?rLn:u1i(s)?sLn:void 0/*MOBIUS_VISION_PATCH*/}',
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
        counts: PATCHES.map((p) => {
            if (text.includes(p.to)) return 'patched';
            return count(text, p.from);
        }),
    };
}

function patch(file) {
    let out = fs.readFileSync(file, 'utf8');
    const log = [];
    let modified = false;

    for (const p of PATCHES) {
        if (out.includes(p.to)) {
            log.push(`already patched: ${p.name}`);
            continue;
        }
        const c = count(out, p.from);
        if (c === 1) {
            out = out.replace(p.from, p.to);
            log.push(`patched: ${p.name}`);
            modified = true;
        } else {
            log.push(`skip / anchor not found (${c}x): ${p.name}`);
        }
    }

    if (modified) {
        const backup = file + '.bak-vision';
        if (!fs.existsSync(backup)) fs.copyFileSync(file, backup);
        fs.writeFileSync(file, out, 'utf8');
    }
    return log;
}

function patchCss(cssFile) {
    if (!fs.existsSync(cssFile)) return [];
    let out = fs.readFileSync(cssFile, 'utf8');
    const marker = '/*MOBIUS_HIDE_ROBOT*/';
    if (out.includes(marker)) return ['CSS already patched (robot hidden)'];
    const rule = '\n.monaco-workbench .codicon.codicon-mobius-mode-agent{display:none!important}/*MOBIUS_HIDE_ROBOT*/\n';
    fs.writeFileSync(cssFile, out + rule, 'utf8');
    return ['patched CSS: hide robot icon'];
}

function cleanModels(root) {
    const p = path.join(root, 'resources', 'app', 'extensions', 'continue', 'models', 'onnx-community');
    if (fs.existsSync(p)) {
        fs.rmSync(p, { recursive: true, force: true });
        return ['removed GLM-OCR model weights: ' + p];
    }
    return [];
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

for (const root of roots) {
    const file = path.join(root, WORKBENCH);
    const cssFile = path.join(root, WORKBENCH_CSS);
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
        lines.forEach((l) => console.log('    ' + l));
        const cssLines = patchCss(cssFile);
        cssLines.forEach((l) => console.log('    ' + l));
        const modelLines = cleanModels(root);
        modelLines.forEach((l) => console.log('    ' + l));
        continue;
    }
    const s = state(file);
    console.log(`    size    : ${(fs.statSync(file).size / 1024 / 1024).toFixed(1)} MB`);
    PATCHES.forEach((p, i) => console.log(`    status  : ${s.counts[i]} -> ${p.name}`));
}
