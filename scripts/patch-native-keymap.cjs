const fs = require('node:fs');
const path = require('node:path');

// native-keymap 3.3.9 uses Node-API exclusively. Avoid pulling V8 headers
// through node.h when compiling against Electron's restricted V8 API.
function patchNativeKeymap(packageDirectory) {
    if (!packageDirectory) return false;
    const filename = path.join(packageDirectory, 'src', 'keymapping.cc');
    if (!fs.existsSync(filename)) {
        console.warn(`[WARN] native-keymap source file not found at ${filename}`);
        return false;
    }
    const source = fs.readFileSync(filename, 'utf8');
    if (!/^\s*#include\s*<node\.h>\s*$/m.test(source)) {
        if (/^\s*#include\s*<node_api\.h>\s*$/m.test(source)) return false;
        throw new Error('Unrecognized native-keymap header layout');
    }
    if (/\b(?:node|v8)::/.test(source)) {
        throw new Error('native-keymap now uses V8 APIs; review the compatibility patch');
    }
    fs.writeFileSync(filename, source.replace(/^(\s*#include\s*)<node\.h>/m, '$1<node_api.h>'), 'utf8');
    return true;
}

module.exports = { patchNativeKeymap };
if (require.main === module) {
    const candidateDirs = [
        process.argv[2],
        path.join(process.cwd(), 'node_modules', 'native-keymap'),
        path.join(__dirname, '..', 'vscode', 'node_modules', 'native-keymap')
    ].filter(Boolean);
    const directory = candidateDirs.find(d => fs.existsSync(d)) || candidateDirs[candidateDirs.length - 1];
    console.log(patchNativeKeymap(directory) ? 'Patched native-keymap to use Node-API headers' : 'native-keymap already uses Node-API headers');
}
