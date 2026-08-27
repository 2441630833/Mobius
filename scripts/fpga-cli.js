#!/usr/bin/env node
/**
 * Mobius — `npm run chip:*` shim.
 *
 * Forwards its arguments to `python -m custom_fpga_mcp <args>` using the same
 * interpreter ladder as the MCP launcher. A bare `python -m custom_fpga_mcp`
 * in package.json would only work for someone whose active shell already had
 * the venv activated and PYTHONPATH set, i.e. almost nobody, and would fail with
 * "No module named custom_fpga_mcp" — which reads as a broken repo rather than
 * an un-run setup step.
 *
 * The required import is the package itself, not fastmcp: `detect`, `paths`,
 * `setup` and `reference` are stdlib-only by design, so they must keep working
 * on a plain interpreter before any setup has happened. That is precisely when
 * their answers are most useful.
 */
'use strict';

const { spawn } = require('child_process');
const resolve = require('./fpga-mcp-resolve');

const args = process.argv.slice(2);

const root = resolve.findRepoRoot();
if (!root) {
  process.stderr.write(
    'chip: cannot locate the Mobius checkout. Run this from inside the repo, ' +
    'or set MOBIUS_ROOT.\n',
  );
  process.exit(1);
}

// The package is pure stdlib at import time; anything heavier is imported inside
// the individual subcommands so they can report their own missing dependency.
const python = resolve.resolveInterpreter(root, 'custom_fpga_mcp');
if (!python) {
  process.stderr.write(
    'chip: no usable Python interpreter found.\n' +
    '  Install Python 3.10+ and run: npm run chip:setup\n' +
    '  Or point FPGA_MCP_PYTHON at an interpreter explicitly.\n',
  );
  process.exit(1);
}

const child = spawn(python, ['-m', 'custom_fpga_mcp', ...args], {
  stdio: 'inherit',
  env: resolve.pythonEnv(root),
  cwd: root,
});

child.on('error', (err) => {
  process.stderr.write(`chip: failed to spawn ${python}: ${err.message}\n`);
  process.exit(1);
});
child.on('exit', (code, signal) => process.exit(signal ? 1 : (code ?? 1)));
