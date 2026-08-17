#!/usr/bin/env node
/**
 * Mobius — Godot MCP server.
 *
 * Exposes Godot as tools to the Continue agent so it can scaffold, import,
 * run and test games without leaving the workspace. Projects live under
 * game-dev/ (text files: .gd / .tscn / .tres), so Godot auto-imports whatever
 * the agent writes — "import into Godot" is just writing files.
 *
 * Zero runtime dependencies: implements the MCP stdio transport (newline-
 * delimited JSON-RPC) directly with the Node standard library.
 *
 * Godot resolution order:
 *   1. GODOT_BIN env var
 *   2. tools/godot/godot.exe (installed by scripts/setup-godot.ps1)
 *   3. `godot` / `godot4` on PATH
 *   4. common install locations (Programs/Godot, scoop, /usr/local/bin...)
 */
'use strict';

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const readline = require('readline');

const SERVER_NAME = 'mobius-godot';
const SERVER_VERSION = '1.0.0';
const PROTOCOL_VERSION = '2024-11-05';

// ---------------------------------------------------------------------------
// Godot + workspace resolution
// ---------------------------------------------------------------------------

function isFile(p) {
  try { return fs.statSync(p).isFile(); } catch { return false; }
}

function resolveGodot() {
  const exe = process.platform === 'win32' ? '.exe' : '';
  const candidates = [];

  if (process.env.GODOT_BIN) candidates.push(process.env.GODOT_BIN);

  const root = findWorkspaceRoot();
  if (root) {
    // Written by scripts/setup-godot.ps1 when Godot was detected elsewhere.
    const pointer = path.join(root, 'tools', 'godot', 'godot.path');
    if (isFile(pointer)) {
      try {
        const pointed = fs.readFileSync(pointer, 'utf8').split(/\r?\n/)[0].trim();
        if (pointed) candidates.unshift(pointed);
      } catch { /* pointer unreadable — ignore */ }
    }
    candidates.push(path.join(root, 'tools', 'godot', `godot${exe}`));
    candidates.push(path.join(root, 'tools', 'godot', 'godot.exe'));
    candidates.push(path.join(root, 'tools', 'godot', 'godot'));
  }

  if (process.platform === 'win32') {
    const local = process.env.LOCALAPPDATA;
    if (local) candidates.push(path.join(local, 'Programs', 'Godot', 'Godot.exe'));
    candidates.push('C:\\Program Files\\Godot\\Godot.exe');
    candidates.push('C:\\Program Files (x86)\\Godot\\Godot.exe');
    const home = process.env.USERPROFILE;
    if (home) {
      candidates.push(path.join(home, 'scoop', 'apps', 'godot', 'current', 'godot.exe'));
      candidates.push(path.join(home, 'scoop', 'shims', 'godot.exe'));
    }
  } else {
    candidates.push('/usr/local/bin/godot', '/usr/bin/godot', '/opt/godot/godot');
    const home = process.env.HOME;
    if (home) candidates.push(path.join(home, '.local', 'bin', 'godot'));
  }

  for (const c of candidates) {
    if (c && isFile(c)) return path.resolve(c);
  }

  // Fall back to PATH lookup (any godot* binary).
  const fromPath = searchPathForGodot(exe);
  if (fromPath) return fromPath;

  return null;
}

function searchPathForGodot(exe) {
  const pathVar = process.env.PATH || process.env.Path || '';
  const sep = process.platform === 'win32' ? ';' : ':';
  const names = process.platform === 'win32'
    ? ['godot.exe', 'godot4.exe', 'Godot.exe']
    : ['godot', 'godot4'];

  for (const dir of pathVar.split(sep)) {
    if (!dir) continue;
    for (const name of names) {
      const p = path.join(dir, name);
      if (isFile(p)) return path.resolve(p);
    }
    if (process.platform === 'win32') {
      // Matches e.g. Godot_v4.4.1-stable_win64.exe placed on PATH.
      try {
        for (const entry of fs.readdirSync(dir)) {
          if (/^Godot/i.test(entry) && /\.exe$/i.test(entry) && !/console/i.test(entry)) {
            return path.resolve(path.join(dir, entry));
          }
        }
      } catch { /* dir unreadable — keep scanning */ }
    }
  }
  return null;
}

function findWorkspaceRoot() {
  let cur = process.env.MOBIUS_ROOT ? path.resolve(process.env.MOBIUS_ROOT) : process.cwd();
  while (true) {
    if (fs.existsSync(path.join(cur, 'game-dev'))) return cur;
    const pkg = path.join(cur, 'package.json');
    if (isFile(pkg)) {
      try {
        const p = JSON.parse(fs.readFileSync(pkg, 'utf8'));
        if (p.name === 'Mobius') return cur;
      } catch { /* not our package.json */ }
    }
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  return cur;
}

function projectPath(override) {
  const root = findWorkspaceRoot();
  if (override) return path.resolve(root, override);
  if (process.env.GODOT_PROJECT) return path.resolve(root, process.env.GODOT_PROJECT);
  return path.join(root, 'game-dev');
}

// ---------------------------------------------------------------------------
// Godot execution
// ---------------------------------------------------------------------------

function runGodot(args, opts = {}) {
  const bin = resolveGodot();
  if (!bin) {
    return { ok: false, error: 'Godot not found. Run: npm run godot:setup -- -Install' };
  }
  const cwd = opts.cwd || findWorkspaceRoot();
  const res = spawnSync(bin, args, {
    cwd,
    encoding: 'utf8',
    timeout: opts.timeout || 120000,
    env: { ...process.env, NO_COLOR: '1' },
    windowsHide: true,
  });
  const out = (res.stdout || '') + (res.stderr || '');
  return {
    ok: res.status === 0 || res.signal === null || res.status === null,
    status: res.status,
    output: out,
    bin,
    timedOut: res.error && res.error.code === 'ETIMEDOUT',
  };
}

// ---------------------------------------------------------------------------
// Tool implementations
// ---------------------------------------------------------------------------

function toolGodotDetect() {
  const bin = resolveGodot();
  const proj = projectPath();
  if (!bin) {
    return {
      isError: true,
      text: 'Godot executable not found.\n\n' +
        'Install it with:\n  npm run godot:setup -- -Install\n\n' +
        'Or point GODOT_BIN at an existing Godot 4 executable and restart the IDE.',
    };
  }
  const v = runGodot(['--version'], { timeout: 30000 });
  const version = v.ok ? v.output.trim().split('\n')[0] : '(could not read version)';
  return {
    isError: false,
    text: [
      `Godot: ${bin}`,
      `Version: ${version}`,
      `Project dir: ${proj}`,
      `Project exists: ${fs.existsSync(path.join(proj, 'project.godot'))}`,
    ].join('\n'),
  };
}

function scaffoldProject(dir) {
  fs.mkdirSync(path.join(dir, 'tests'), { recursive: true });

  const projectGodot = `; Engine configuration file (Godot 4)\nconfig_version=5\n\n[application]\nconfig/name="Mobius Game"\nrun/main_scene="res://main.tscn"\nconfig/features=PackedStringArray("4.4")\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\nrenderer/rendering_method.mobile="gl_compatibility"\n`;

  const mainTscn = `[gd_scene load_steps=2 format=3]\n\n[ext_resource type="Script" path="res://main.gd" id="1_main"]\n\n[node name="Main" type="Node2D"]\nscript = ExtResource("1_main")\n`;

  const mainGd = `extends Node2D\n\n\nfunc _ready() -> void:\n\tprint("[Mobius GameDev] Main scene ready.")\n`;

  const testRunner = `extends SceneTree\n# Headless test runner used by the Godot MCP godot_test tool.\n# Run: godot --headless --path . --script res://tests/test_runner.gd\n# Agent: add more test_* functions here and call them from _initialize().\n\nvar _passed := 0\nvar _failed := 0\nvar _assertions := 0\n\n\nfunc _initialize() -> void:\n\ttest_sample()\n\ttest_node_creation()\n\t_finish()\n\n\nfunc check(cond: bool, label: String) -> void:\n\t_assertions += 1\n\tif cond:\n\t\t_passed += 1\n\t\tprint("PASS: " + label)\n\telse:\n\t\t_failed += 1\n\t\tprinterr("FAIL: " + label)\n\n\nfunc _finish() -> void:\n\tprint("TESTS: %d passed, %d failed, %d assertions" % [_passed, _failed, _assertions])\n\tquit(1 if _failed > 0 else 0)\n\n\nfunc test_sample() -> void:\n\tcheck(1 + 1 == 2, "sample arithmetic")\n\n\nfunc test_node_creation() -> void:\n\tvar n := Node.new()\n\tcheck(n != null, "Node.new() returns an instance")\n\tn.free()\n`;

  writeFile(path.join(dir, 'project.godot'), projectGodot);
  writeFile(path.join(dir, 'main.tscn'), mainTscn);
  writeFile(path.join(dir, 'main.gd'), mainGd);
  writeFile(path.join(dir, 'tests', 'test_runner.gd'), testRunner);
}

function writeFile(p, content) {
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, content, 'utf8');
}

function toolGodotProjectInit(args) {
  const proj = projectPath(args.name);
  const exists = fs.existsSync(path.join(proj, 'project.godot'));
  if (exists) {
    return {
      isError: false,
      text: `Project already exists at ${proj} (left untouched).\nRun godot_import to re-import, then godot_test to verify.`,
    };
  }
  scaffoldProject(proj);
  return {
    isError: false,
    text: [
      `Created Godot project at ${proj}`,
      '  project.godot, main.tscn, main.gd, tests/test_runner.gd',
      '',
      'Next: godot_import (auto-imports assets), then godot_test.',
    ].join('\n'),
  };
}

function toolGodotImport(args) {
  const proj = projectPath(args.project);
  if (!fs.existsSync(path.join(proj, 'project.godot'))) {
    return { isError: true, text: `No project.godot at ${proj}. Run godot_project_init first.` };
  }
  const r = runGodot(['--headless', '--editor', '--path', proj, '--quit'], { timeout: 120000 });
  if (r.error) return { isError: true, text: r.error };
  const tail = r.output.split('\n').filter(Boolean).slice(-60).join('\n');
  return { isError: false, text: `Import finished (exit ${r.status}).\n\n${tail}` };
}

function toolGodotRun(args) {
  const proj = projectPath(args.project);
  if (!fs.existsSync(path.join(proj, 'project.godot'))) {
    return { isError: true, text: `No project.godot at ${proj}. Run godot_project_init first.` };
  }
  const frames = Number(args.frames) > 0 ? Number(args.frames) : 120;
  const argv = ['--headless', '--path', proj, `--quit-after`, String(frames)];
  if (args.scene) argv.push(args.scene);
  const r = runGodot(argv, { timeout: 120000 });
  if (r.error) return { isError: true, text: r.error };
  const tail = r.output.split('\n').filter(Boolean).slice(-80).join('\n');
  const errors = (r.output.match(/ERROR|SCRIPT ERROR|Parse Error/g) || []).length;
  return {
    isError: errors > 0,
    text: `Ran ${frames} frames (exit ${r.status}). ${errors > 0 ? `Detected ${errors} error line(s).` : 'No Godot errors detected.'}\n\n${tail}`,
  };
}

function toolGodotTest(args) {
  const proj = projectPath(args.project);
  if (!fs.existsSync(path.join(proj, 'tests', 'test_runner.gd'))) {
    return { isError: true, text: `No tests/test_runner.gd at ${proj}. Run godot_project_init first.` };
  }
  const r = runGodot(['--headless', '--path', proj, '--script', 'res://tests/test_runner.gd'], { timeout: 120000 });
  if (r.error) return { isError: true, text: r.error };
  const m = r.output.match(/TESTS:\s*(\d+)\s*passed,\s*(\d+)\s*failed/i);
  const summary = m ? `Result: ${m[1]} passed, ${m[2]} failed` : 'Result: could not parse TEST summary';
  const failed = m ? Number(m[2]) : (r.status === 0 ? 0 : 1);
  return {
    isError: failed > 0,
    text: `${summary} (exit ${r.status})\n\n${r.output.split('\n').filter(Boolean).slice(-120).join('\n')}`,
  };
}

// ---------------------------------------------------------------------------
// Tool registry
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: 'godot_detect',
    description: 'Locate the Godot executable, report its version, and show the game-dev project directory.',
    inputSchema: { type: 'object', properties: {} },
  },
  {
    name: 'godot_project_init',
    description: 'Scaffold a new Godot 4 project (project.godot, main scene, headless test runner) under game-dev/. No-op if it already exists.',
    inputSchema: {
      type: 'object',
      properties: {
        name: { type: 'string', description: 'Project folder name, relative to the workspace (default: game-dev).' },
      },
    },
  },
  {
    name: 'godot_import',
    description: 'Run the Godot editor headless to import/re-import assets and generate .import files after files change.',
    inputSchema: {
      type: 'object',
      properties: {
        project: { type: 'string', description: 'Project folder name (default: game-dev).' },
      },
    },
  },
  {
    name: 'godot_run',
    description: 'Run the project headless for a fixed number of frames and return stdout/stderr plus a scan for Godot errors.',
    inputSchema: {
      type: 'object',
      properties: {
        project: { type: 'string', description: 'Project folder name (default: game-dev).' },
        scene: { type: 'string', description: 'Optional scene path to run instead of the main scene (e.g. res://main.tscn).' },
        frames: { type: 'number', description: 'Frames to run before quitting (default: 120).' },
      },
    },
  },
  {
    name: 'godot_test',
    description: 'Run the GDScript test suite headlessly and report passed/failed counts.',
    inputSchema: {
      type: 'object',
      properties: {
        project: { type: 'string', description: 'Project folder name (default: game-dev).' },
      },
    },
  },
];

const TOOL_MAP = {
  godot_detect: toolGodotDetect,
  godot_project_init: toolGodotProjectInit,
  godot_import: toolGodotImport,
  godot_run: toolGodotRun,
  godot_test: toolGodotTest,
};

// ---------------------------------------------------------------------------
// JSON-RPC loop (stdio, newline-delimited)
// ---------------------------------------------------------------------------

function respond(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n');
}

function respondError(id, code, message) {
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, error: { code, message } }) + '\n');
}

function handle(msg) {
  if (!msg || typeof msg !== 'object') return;

  if (msg.method === 'initialize') {
    respond(msg.id, {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: { tools: {} },
      serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
    });
    return;
  }

  if (msg.method === 'notifications/initialized' || msg.method === 'notifications/cancelled') {
    return; // notifications have no response
  }

  if (msg.method === 'ping') {
    respond(msg.id, {});
    return;
  }

  if (msg.method === 'tools/list') {
    respond(msg.id, { tools: TOOLS });
    return;
  }

  if (msg.method === 'tools/call') {
    const name = msg.params && msg.params.name;
    const args = (msg.params && msg.params.arguments) || {};
    const fn = TOOL_MAP[name];
    if (!fn) {
      respond(msg.id, {
        content: [{ type: 'text', text: `Unknown tool: ${name}` }],
        isError: true,
      });
      return;
    }
    try {
      const out = fn(args);
      respond(msg.id, {
        content: [{ type: 'text', text: out.text }],
        isError: Boolean(out.isError),
      });
    } catch (e) {
      respond(msg.id, {
        content: [{ type: 'text', text: `Tool ${name} failed: ${e && e.stack ? e.stack : e}` }],
        isError: true,
      });
    }
    return;
  }

  respondError(msg.id, -32601, `Method not found: ${msg.method}`);
}

// CLI conveniences so a human can drive the same code paths as the agent.
function runCli() {
  const flag = ['--init', '--import', '--run', '--test'].find((f) => process.argv.includes(f));
  const out = flag === '--init' ? toolGodotProjectInit({})
    : flag === '--import' ? toolGodotImport({})
    : flag === '--run' ? toolGodotRun({})
    : flag === '--test' ? toolGodotTest({})
    : null;
  if (out) {
    console.log(out.text);
    process.exit(out.isError ? 1 : 0);
  }
}

function main() {
  // Self-test mode: exercises detection + tool list without needing a client.
  if (process.argv.includes('--self-test')) {
    console.log(`${SERVER_NAME} v${SERVER_VERSION} (protocol ${PROTOCOL_VERSION})`);
    console.log('godot:', resolveGodot() || 'NOT FOUND');
    console.log('project:', projectPath());
    console.log('tools:', TOOLS.map((t) => t.name).join(', '));
    process.exit(0);
  }

  runCli();

  const rl = readline.createInterface({ input: process.stdin, terminal: false });
  rl.on('line', (line) => {
    const trimmed = line.trim();
    if (!trimmed) return;
    try {
      handle(JSON.parse(trimmed));
    } catch {
      // Non-JSON line on stdin: ignore rather than crash the transport.
    }
  });
  rl.on('close', () => process.exit(0));
}

main();
