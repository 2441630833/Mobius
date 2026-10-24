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

function resolveEccRoot() {
	const candidates = [
		path.join(__dirname, '..', 'ECC'),
		path.join(process.cwd(), 'ECC'),
	];
	for (const candidate of candidates) {
		try {
			if (fs.existsSync(candidate) && fs.existsSync(path.join(candidate, 'package.json'))) {
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
