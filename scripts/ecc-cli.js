#!/usr/bin/env node
/**
 * Mobius — ECC CLI Tool Runner
 *
 * Exposes ECC commands to Mobius agent loops, terminal tools, and scripts.
 * Forwards arguments to ECC/scripts/ecc.js or handles subcommands.
 */

'use strict';

const path = require('node:path');
const fs = require('node:fs');
const { spawnSync } = require('node:child_process');

function resolveEccRoot(startDir) {
	const candidates = [];
	if (process.env.MOBIUS_ECC_ROOT) {
		candidates.push(process.env.MOBIUS_ECC_ROOT);
	}
	if (startDir) {
		candidates.push(path.join(startDir, 'resources', 'mobius-ecc'));
		candidates.push(path.join(startDir, 'ECC'));
	}
	// Packaged app: scripts/ -> sibling resources/mobius-ecc
	candidates.push(path.join(__dirname, '..', 'resources', 'mobius-ecc'));
	// Packaged app: inside resources/mobius-ecc/scripts -> parent resources/mobius-ecc
	candidates.push(path.join(__dirname, '..'));
	// Monorepo checkout: scripts/ -> sibling ECC
	candidates.push(path.join(__dirname, '..', 'ECC'));
	// Current working directory
	candidates.push(path.join(process.cwd(), 'resources', 'mobius-ecc'));
	candidates.push(path.join(process.cwd(), 'ECC'));
	if (process.env.LOCALAPPDATA) {
		candidates.push(path.join(process.env.LOCALAPPDATA, 'Programs', 'Mobius', 'resources', 'mobius-ecc'));
	}
	for (const candidate of candidates) {
		try {
			if (candidate && fs.existsSync(candidate) && fs.existsSync(path.join(candidate, 'package.json')) && (fs.existsSync(path.join(candidate, 'scripts', 'ecc.js')) || fs.existsSync(path.join(candidate, 'manifests', 'install-components.json')))) {
				return path.resolve(candidate);
			}
		} catch {
			// continue
		}
	}
	return undefined;
}

function main() {
	const eccRoot = resolveEccRoot();
	if (!eccRoot) {
		console.error('[Mobius][ECC] Error: ECC submodule is not initialized at ECC/. Run: git submodule update --init ECC');
		process.exit(1);
	}

	const eccScript = path.join(eccRoot, 'scripts', 'ecc.js');
	if (!fs.existsSync(eccScript)) {
		console.error(`[Mobius][ECC] Error: ${eccScript} does not exist.`);
		process.exit(1);
	}

	const args = process.argv.slice(2);
	const result = spawnSync(process.execPath, [eccScript, ...args], {
		cwd: eccRoot,
		stdio: 'inherit',
		env: process.env,
	});

	process.exit(result.status ?? 0);
}

if (require.main === module) {
	main();
}

module.exports = {
	resolveEccRoot,
};
