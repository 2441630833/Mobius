/**
 * Mobius — shared resolution for the chip-design Python package.
 *
 * The MCP launcher and the `npm run chip:*` CLI shim both need to answer the
 * same two questions — where is the Mobius checkout, and which interpreter can
 * actually import what I am about to use — and they must answer them
 * identically. When they drifted, `chip:detect` reported a healthy toolchain
 * while the IDE was running the diagnostic fallback, which is exactly the kind
 * of contradiction that costs an afternoon.
 *
 * One resolver, one ladder, two callers.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

const PKG_RELATIVE = path.join('chip-design', 'mcp', 'custom_fpga_mcp');

function isFile(p) {
  try { return fs.statSync(p).isFile(); } catch { return false; }
}

function isDir(p) {
  try { return fs.statSync(p).isDirectory(); } catch { return false; }
}

function isMobiusRoot(dir) {
  if (isDir(path.join(dir, PKG_RELATIVE))) return true;
  const pkg = path.join(dir, 'package.json');
  if (!isFile(pkg)) return false;
  try {
    return JSON.parse(fs.readFileSync(pkg, 'utf8')).name === 'Mobius';
  } catch {
    return false;
  }
}

/** Ladder of starting points, each walked up to the filesystem root. */
function findRepoRoot() {
  const starts = [];
  if (process.env.MOBIUS_ROOT) starts.push(process.env.MOBIUS_ROOT);
  starts.push(process.cwd());
  starts.push(path.join(__dirname, '..'));

  for (const start of starts) {
    let cur;
    try { cur = path.resolve(start); } catch { continue; }
    for (;;) {
      if (isMobiusRoot(cur)) return cur;
      const parent = path.dirname(cur);
      if (parent === cur) break;
      cur = parent;
    }
  }
  return null;
}

/** Parent directory of the package, i.e. what PYTHONPATH must contain. */
function pkgParent(root) {
  return path.join(root, 'chip-design', 'mcp');
}

function venvPython(root) {
  return process.platform === 'win32'
    ? path.join(root, 'chip-design', '.venv', 'Scripts', 'python.exe')
    : path.join(root, 'chip-design', '.venv', 'bin', 'python');
}

function candidateInterpreters(root) {
  const out = [];
  if (process.env.FPGA_MCP_PYTHON) out.push(process.env.FPGA_MCP_PYTHON);
  out.push(venvPython(root));
  // A system interpreter only helps if the required module happens to be
  // installed there, which canImport() verifies before we commit to it.
  if (process.platform === 'win32') {
    out.push('python.exe', 'python', 'py');
  } else {
    out.push('python3', 'python');
  }
  return out;
}

/**
 * Existence is not proof: a venv can be half-built, and a recorded path can come
 * from another machine entirely. Probe the import we are about to depend on.
 */
function canImport(python, root, moduleName) {
  if (!python) return false;
  const probe = spawnSync(python, ['-c', `import ${moduleName}`], {
    env: { ...process.env, PYTHONPATH: pkgParent(root), PYTHONIOENCODING: 'utf-8' },
    stdio: 'ignore',
    timeout: 30000,
  });
  return probe.status === 0;
}

/**
 * First interpreter on the ladder that can import `requires`, or null.
 *
 * `requires` differs by caller on purpose: serving MCP needs `fastmcp`, while
 * `chip:lint` only needs the package itself. Demanding fastmcp for a lint run
 * would send a perfectly working interpreter to the fallback.
 */
function resolveInterpreter(root, requires) {
  return candidateInterpreters(root).find((c) => canImport(c, root, requires)) || null;
}

/** Environment for a child Python process rooted at this checkout. */
function pythonEnv(root) {
  const parent = pkgParent(root);
  return {
    ...process.env,
    MOBIUS_ROOT: process.env.MOBIUS_ROOT || root,
    PYTHONPATH: process.env.PYTHONPATH
      ? `${parent}${path.delimiter}${process.env.PYTHONPATH}`
      : parent,
    // Without this a Windows console codepage mangles the em-dashes in tool
    // descriptions, and for the MCP server that makes the JSON-RPC stream
    // invalid UTF-8.
    PYTHONIOENCODING: 'utf-8',
    PYTHONUNBUFFERED: '1',
  };
}

module.exports = {
  PKG_RELATIVE,
  isFile,
  isDir,
  findRepoRoot,
  pkgParent,
  venvPython,
  candidateInterpreters,
  canImport,
  resolveInterpreter,
  pythonEnv,
};
