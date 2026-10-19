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

  // Verify @vscode/sqlite3 native module can load and execute queries in the target runtime
  try {
    const sqlite3 = appRequire('@vscode/sqlite3');
    assert.ok(typeof sqlite3.Database === 'function', 'sqlite3.Database must be a function');
    const db = new sqlite3.Database(':memory:');
    db.serialize(() => {
      db.run('CREATE TABLE test (val TEXT)');
      db.run('INSERT INTO test VALUES (?)', ['persistence_check']);
      db.get('SELECT val FROM test', (err, row) => {
        assert.ifError(err);
        assert.equal(row.val, 'persistence_check');
        db.close();
        console.log('PASS packaged Linux ' + process.arch + ' sqlite3: in-memory database query');
      });
    });
  } catch (err) {
    console.error('FAIL packaged Linux ' + process.arch + ' sqlite3 verification: ' + err.message);
    process.exit(1);
  }
});
terminal.write(sentinel + '\r');
