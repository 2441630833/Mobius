// Run with the packaged Electron executable, ELECTRON_RUN_AS_NODE=1.
// This checks the shipped node-pty binary/ABI and real shell I/O, not host Node.
'use strict';
const assert = require('node:assert/strict');
const path = require('node:path');
const { createRequire } = require('node:module');

assert.equal(process.platform, 'linux', 'Terminal package verification requires Linux');
assert.equal(process.arch, process.argv[3], 'Run verification on the target architecture');
const appRequire = createRequire(path.join(path.resolve(process.argv[2]), 'resources/app/package.json'));
const pty = appRequire('node-pty');
const sentinel = 'MOBIUS_PTY_' + process.pid;
const terminal = pty.spawn('/bin/sh', ['-c', 'read value; printf "%s\\n" "$value"'], {
  name: 'xterm-256color', cols: 80, rows: 24,
  cwd: '/tmp', env: { ...process.env, TERM: 'xterm-256color' },
});
let output = '';
const timer = setTimeout(() => {
  terminal.kill();
  console.error('Terminal smoke test timed out: ' + output);
  process.exit(1);
}, 15_000);
terminal.onData(data => { output += data; });
terminal.onExit(({ exitCode }) => {
  clearTimeout(timer);
  assert.equal(exitCode, 0, output);
  assert.ok(output.includes(sentinel), 'PTY did not return shell output');
  console.log('PASS packaged Linux ' + process.arch + ' terminal: shell input/output and exit');
});
terminal.write(sentinel + '\r');
