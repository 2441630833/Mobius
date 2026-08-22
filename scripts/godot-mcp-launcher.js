#!/usr/bin/env node
/**
 * MCP entrypoint when the workspace folder is not the Mobius repo root (e.g. e:\godot).
 * Walks upward from cwd / MOBIUS_ROOT to find scripts/godot-mcp-server.js, sets
 * MOBIUS_ROOT + GODOT_PROJECT when missing, then execs the real server with the same argv.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function isFile(p) {
  try { return fs.statSync(p).isFile(); } catch { return false; }
}

function findGodotMcpScript() {
  const starts = [];
  if (process.env.MOBIUS_ROOT) starts.push(process.env.MOBIUS_ROOT);
  starts.push(process.cwd());
  starts.push(path.join(__dirname, '..'));
  for (const start of starts) {
    let cur = path.resolve(start);
    while (true) {
      const script = path.join(cur, 'scripts', 'godot-mcp-server.js');
      if (isFile(script)) return { script, mobiusRoot: cur };
      const parent = path.dirname(cur);
      if (parent === cur) break;
      cur = parent;
    }
  }
  return null;
}

function resolveGodotProject(mobiusRoot) {
  if (process.env.GODOT_PROJECT) {
    return path.resolve(process.env.GODOT_PROJECT);
  }
  const cwd = path.resolve(process.cwd());
  if (isFile(path.join(cwd, 'project.godot'))) {
    return cwd;
  }
  const nested = path.join(cwd, 'game-dev');
  if (isFile(path.join(nested, 'project.godot')) || fs.existsSync(nested)) {
    return nested;
  }
  return path.join(mobiusRoot, 'game-dev');
}

const found = findGodotMcpScript();
if (!found) {
  process.stderr.write(
    'godot MCP launcher: cannot find scripts/godot-mcp-server.js — open the Mobius repo or set MOBIUS_ROOT.\n',
  );
  process.exit(1);
}

const env = { ...process.env };
if (!env.MOBIUS_ROOT) env.MOBIUS_ROOT = found.mobiusRoot;
if (!env.GODOT_PROJECT) env.GODOT_PROJECT = resolveGodotProject(found.mobiusRoot);

const result = spawnSync(process.execPath, [found.script, ...process.argv.slice(2)], {
  stdio: 'inherit',
  env,
});
process.exit(result.status ?? 1);
