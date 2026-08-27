#!/usr/bin/env node
/**
 * Mobius — custom-fpga-mcp diagnostic fallback.
 *
 * Started by scripts/fpga-mcp-launcher.js only when the Python server cannot
 * run (no venv, fastmcp not importable, checkout not found).
 *
 * Why this exists: an MCP server that fails to start leaves chip mode with an
 * empty toolset and no explanation, which is indistinguishable from a broken
 * feature. This server registers the same tool names as the real one, answers
 * the hardware-free ones for real, and answers the rest with the specific reason
 * it cannot help plus the command that fixes it. The agent stays honest instead
 * of guessing at shell commands.
 *
 * Zero dependencies: MCP stdio transport (newline-delimited JSON-RPC) on top of
 * the Node standard library, matching scripts/godot-mcp-server.js.
 */
'use strict';

const path = require('path');
const readline = require('readline');
const { spawnSync } = require('child_process');
const resolve = require('./fpga-mcp-resolve');

const SERVER_NAME = 'custom-fpga-mcp (fallback)';
const SERVER_VERSION = '1.0.0';
const PROTOCOL_VERSION = '2024-11-05';

const REASON = process.env.FPGA_MCP_FALLBACK_REASON
  || 'the Python MCP server could not be started';

// ---------------------------------------------------------------------------
// Environment probing
// ---------------------------------------------------------------------------

const { isFile } = resolve;

const ROOT = resolve.findRepoRoot();

/**
 * An interpreter that can import the package, or null.
 *
 * This is the whole reason the fallback is more than an error message. Most of
 * the Python package is stdlib-only — `detect`, `paths`, `setup`, `reference`,
 * `lint` and `simulate` never touch fastmcp or pyserial — so a plain system
 * interpreter is enough to run them for real. fastmcp is only needed to *speak*
 * MCP, which is the job this Node process has taken over.
 *
 * Resolved once: probing costs a subprocess, and the answer cannot change while
 * we are running.
 */
const CLI_PYTHON = ROOT ? resolve.resolveInterpreter(ROOT, 'custom_fpga_mcp') : null;

function which(name) {
  const pathVar = process.env.PATH || process.env.Path || '';
  const sep = process.platform === 'win32' ? ';' : ':';
  const exts = process.platform === 'win32'
    ? (process.env.PATHEXT || '.EXE;.CMD;.BAT').split(';')
    : [''];
  for (const dir of pathVar.split(sep)) {
    if (!dir) continue;
    for (const ext of exts) {
      const candidate = path.join(dir, name + ext);
      if (isFile(candidate)) return path.resolve(candidate);
    }
    if (isFile(path.join(dir, name))) return path.resolve(path.join(dir, name));
  }
  if (ROOT) {
    const binDirs = [
      path.join(ROOT, 'tools', 'mingw', 'bin'),
      path.join(ROOT, 'tools', 'openxc7', 'bin'),
      path.join(ROOT, 'tools', 'oss-cad-suite', 'bin'),
    ];
    const bundled = name === 'verilator'
      ? ['verilator_bin.exe', 'verilator.exe', 'verilator']
      : name === 'openFPGALoader'
        ? ['openFPGALoader.exe', 'openFPGALoader']
        : name === 'yosys'
          ? ['yosys.exe', 'yosys']
          : name === 'nextpnr-xilinx'
            ? ['nextpnr-xilinx.exe', 'nextpnr-xilinx']
            : name === 'g++'
              ? ['g++.exe', 'g++']
              : name === 'make'
                ? ['make.exe', 'mingw32-make.exe', 'make']
                : [name];
    for (const bin of binDirs) {
      for (const file of bundled) {
        const candidate = path.join(bin, file);
        if (isFile(candidate)) return path.resolve(candidate);
      }
    }
  }
  return null;
}

function probeVersion(bin, args, timeout = 15000) {
  if (!bin) return null;
  const res = spawnSync(bin, args, { encoding: 'utf8', timeout, stdio: ['ignore', 'pipe', 'pipe'] });
  if (res.status !== 0) return null;
  return String(res.stdout || res.stderr || '').split(/\r?\n/).find((l) => l.trim()) || '';
}

function venvPython() {
  if (!ROOT) return null;
  const p = resolve.venvPython(ROOT);
  return isFile(p) ? p : null;
}

function detect() {
  const docker = which('docker');
  const loader = which('openFPGALoader');
  const verilator = which('verilator');
  const yosys = which('yosys');
  const pnr = which('nextpnr-xilinx');
  const python = which(process.platform === 'win32' ? 'python' : 'python3');
  const venv = venvPython();

  const tools = [
    {
      name: 'mcp-server',
      available: false,
      detail: CLI_PYTHON
        ? `Running the Node diagnostic fallback: ${REASON}. RTL work (lint, `
          + 'simulate, paths, reference) still runs via a plain interpreter; '
          + 'synthesis, flashing and sampling need the Python server.'
        : `Running the Node diagnostic fallback: ${REASON}. Chip-design tools are unavailable until the Python server starts.`,
    },
    {
      name: 'delegation',
      available: Boolean(CLI_PYTHON),
      path: CLI_PYTHON,
      detail: CLI_PYTHON
        ? 'stdlib-only subcommands are delegated to this interpreter, so they return real results'
        : 'no interpreter can import custom_fpga_mcp — every tool is unavailable',
    },
    {
      name: 'checkout',
      available: Boolean(ROOT),
      path: ROOT,
      detail: ROOT ? 'Mobius checkout located' : 'could not locate the Mobius checkout — set MOBIUS_ROOT',
    },
    {
      name: 'python-venv',
      available: Boolean(venv),
      path: venv,
      detail: venv
        ? 'venv exists but fastmcp is not importable from it — re-run npm run chip:setup'
        : 'no chip-design/.venv — run: npm run chip:setup',
    },
    {
      name: 'python',
      available: Boolean(python),
      path: python,
      version: probeVersion(python, ['--version']),
      detail: python ? 'host interpreter found' : 'no python on PATH — install Python 3.10+',
    },
    {
      name: 'docker',
      available: Boolean(docker),
      path: docker,
      detail: docker ? 'docker CLI found (optional fallback; native openXC7 is preferred)' : 'optional — native synth uses npm run chip:openxc7',
    },
    {
      name: 'openFPGALoader',
      available: Boolean(loader),
      path: loader,
      detail: loader ? 'host JTAG programmer found' : 'needed to flash the Arty A7 — must run on the host, never in Docker',
    },
    {
      name: 'verilator',
      available: Boolean(verilator),
      path: verilator,
      version: probeVersion(verilator, ['--version']),
      detail: verilator ? 'RTL simulator found' : 'needed for lint/simulate — npm run chip:cad-suite',
    },
    {
      name: 'yosys',
      available: Boolean(yosys),
      path: yosys,
      detail: yosys ? 'native synthesis frontend found' : 'needed for fpga_synthesize — npm run chip:cad-suite',
    },
    {
      name: 'nextpnr-xilinx',
      available: Boolean(pnr),
      path: pnr,
      detail: pnr ? 'native Xilinx 7-series P&R found' : 'needed for fpga_synthesize — npm run chip:openxc7',
    },
  ];

  return {
    mode: 'fallback',
    ok: false,
    reason: REASON,
    repo_root: ROOT,
    capabilities: {
      lint_and_simulate: Boolean(CLI_PYTHON && verilator),
      synthesize: Boolean(yosys && pnr),
      synthesize_native: Boolean(yosys && pnr),
      flash: false,
      sample_tokens: false,
    },
    tools,
    blockers: tools.filter((t) => !t.available).map((t) => `${t.name}: ${t.detail}`),
    fix: [
      'npm run chip:setup',
      'then reload the window so the IDE re-spawns the MCP server',
    ],
  };
}

// ---------------------------------------------------------------------------
// Tools
// ---------------------------------------------------------------------------

/**
 * Tool names must stay identical to chip-design/mcp/custom_fpga_mcp/server.py.
 * A missing name here means Chip mode looks like a different product depending
 * on whether the venv exists.
 */
const HARDWARE_UNAVAILABLE = {
  fpga_synthesize: 'Native Yosys + openXC7 synthesis is orchestrated by the Python server (needs fastmcp).',
  fpga_clean: 'Build cleanup runs from the Python server.',
  fpga_flash: 'JTAG programming is orchestrated by the Python server.',
  fpga_list_cables: 'JTAG probe enumeration runs from the Python server.',
  fpga_device_info: 'Serial access needs pyserial in the chip-design venv.',
  fpga_sample_token: 'Serial access needs pyserial in the chip-design venv.',
  fpga_sample_sequence: 'Serial access needs pyserial in the chip-design venv.',
  fpga_verify_distribution: 'Serial access needs pyserial in the chip-design venv.',
  fpga_trng_entropy: 'Serial access needs pyserial in the chip-design venv.',
  fpga_self_test: 'The end-to-end hardware check needs the Python server.',
  fpga_close_link: 'No serial link is open in fallback mode.',
};

/** Stdlib-only CLI subcommands. Delegated when a plain interpreter can import the package. */
const DELEGATED = {
  fpga_paths: { argv: () => ['paths'], timeout: 15000 },
  fpga_lint: { argv: (args) => ['lint', ...(args.top ? ['--top', String(args.top)] : [])], timeout: 300000 },
  fpga_simulate: {
    argv: (args) => [
      'simulate',
      '--samples', String(args.samples == null ? 2000 : args.samples),
      '--seed', String(args.seed == null ? 1 : args.seed),
    ],
    timeout: 900000,
  },
  fpga_reference_distribution: {
    argv: (args) => ['reference', JSON.stringify(args.logits || [])],
    timeout: 15000,
  },
};

const TOOL_DESCRIPTIONS = {
  fpga_detect: 'Report what this host can do. The Python MCP server is not running; this fallback still diagnoses the gap.',
  fpga_setup: 'Return the exact commands needed to make the chip-design toolchain work.',
  fpga_paths: 'Show resolved project paths (delegated to a plain interpreter when possible).',
  fpga_lint: 'Verilator lint. Delegated when a plain interpreter can import custom_fpga_mcp.',
  fpga_simulate: 'Statistical testbench. Delegated when a plain interpreter can import custom_fpga_mcp.',
  fpga_reference_distribution: 'Host-side hardware distribution model. No board needed.',
};

const TOOL_NAMES = [
  'fpga_detect',
  'fpga_paths',
  'fpga_setup',
  'fpga_lint',
  'fpga_simulate',
  'fpga_synthesize',
  'fpga_clean',
  'fpga_flash',
  'fpga_list_cables',
  'fpga_device_info',
  'fpga_sample_token',
  'fpga_sample_sequence',
  'fpga_verify_distribution',
  'fpga_trng_entropy',
  'fpga_self_test',
  'fpga_close_link',
  'fpga_reference_distribution',
];

const TOOLS = TOOL_NAMES.map((name) => ({
  name,
  description: TOOL_DESCRIPTIONS[name]
    || (HARDWARE_UNAVAILABLE[name]
      ? `UNAVAILABLE until the Python MCP server starts. ${HARDWARE_UNAVAILABLE[name]} Run \`npm run chip:setup\` and reload.`
      : name),
  inputSchema: { type: 'object', additionalProperties: true },
}));

function delegatePython(argv, timeout) {
  if (!CLI_PYTHON || !ROOT) return null;
  const res = spawnSync(CLI_PYTHON, ['-m', 'custom_fpga_mcp', ...argv], {
    encoding: 'utf8',
    timeout,
    env: resolve.pythonEnv(ROOT),
    cwd: ROOT,
  });
  const text = String(res.stdout || res.stderr || '').trim() || `exit ${res.status}`;
  let isError = res.status !== 0;
  try {
    const parsed = JSON.parse(res.stdout);
    if (parsed && parsed.ok === false) isError = true;
  } catch { /* CLI may print non-JSON on a hard crash */ }
  return { text, isError };
}

function callTool(name, args) {
  const params = args && typeof args === 'object' ? args : {};

  if (name === 'fpga_detect') {
    const delegated = delegatePython(['detect'], 60000);
    if (delegated) return delegated;
    return { text: JSON.stringify(detect(), null, 2), isError: false };
  }
  if (name === 'fpga_setup') {
    const delegated = delegatePython(['setup'], 60000);
    if (delegated) return delegated;
    const steps = [
      {
        why: 'the Python MCP server is not running',
        run: 'npm run chip:setup',
        detail: REASON,
      },
      {
        why: 'the IDE caches MCP server processes',
        run: 'reload the window (Developer: Reload Window) after setup completes',
      },
    ];
    if (!ROOT) {
      steps.unshift({
        why: 'the Mobius checkout could not be located from this working directory',
        run: 'open the Mobius repo as the workspace folder, or set MOBIUS_ROOT',
      });
    }
    return {
      text: JSON.stringify({ ok: false, mode: 'fallback', outstanding: steps }, null, 2),
      isError: false,
    };
  }
  if (DELEGATED[name]) {
    const spec = DELEGATED[name];
    const delegated = delegatePython(spec.argv(params), spec.timeout);
    if (delegated) return delegated;
    return {
      text: JSON.stringify({
        ok: false,
        mode: 'fallback',
        error: `${name} needs an interpreter that can import custom_fpga_mcp`,
        fix: 'npm run chip:setup, then reload the window',
      }, null, 2),
      isError: true,
    };
  }
  if (HARDWARE_UNAVAILABLE[name]) {
    return {
      text: JSON.stringify(
        {
          ok: false,
          mode: 'fallback',
          error: `${name} is unavailable: ${REASON}`,
          detail: HARDWARE_UNAVAILABLE[name],
          fix: 'npm run chip:setup, then reload the window',
        },
        null,
        2,
      ),
      isError: true,
    };
  }
  return { text: `Unknown tool: ${name}`, isError: true };
}

// ---------------------------------------------------------------------------
// MCP stdio transport
// ---------------------------------------------------------------------------

function respond(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: '2.0', id, result }) + '\n');
}

function handle(msg) {
  if (!msg || typeof msg !== 'object') return;

  if (msg.method === 'initialize') {
    respond(msg.id, {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: { tools: {} },
      serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
      instructions:
        'DEGRADED MODE. The chip-design Python MCP server could not start '
        + `(${REASON}), so no synthesis, flashing, simulation or sampling is `
        + 'possible right now. Call fpga_detect for the diagnosis and fpga_setup '
        + 'for the fix. Do not invent shell commands to work around this, and do '
        + 'not report FPGA results you did not obtain.',
    });
    return;
  }

  if (typeof msg.method === 'string' && msg.method.startsWith('notifications/')) {
    return; // notifications carry no response
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
    const out = callTool(name, args);
    respond(msg.id, {
      content: [{ type: 'text', text: out.text }],
      isError: Boolean(out.isError),
    });
    return;
  }

  if (msg.id !== undefined) {
    process.stdout.write(JSON.stringify({
      jsonrpc: '2.0',
      id: msg.id,
      error: { code: -32601, message: `Method not found: ${msg.method}` },
    }) + '\n');
  }
}

if (process.argv.includes('--self-test')) {
  const names = TOOLS.map((t) => t.name);
  const missing = TOOL_NAMES.filter((n) => !names.includes(n));
  process.stdout.write(JSON.stringify({
    ok: missing.length === 0,
    server: SERVER_NAME,
    version: SERVER_VERSION,
    tools: names,
    missing,
    detect: detect(),
  }, null, 2) + '\n');
  process.exit(missing.length ? 1 : 0);
}

if (process.argv.includes('--detect')) {
  // Same code path as the MCP tool, for `npm run chip:detect` style checks.
  process.stdout.write(JSON.stringify(detect(), null, 2) + '\n');
  process.exit(0);
}

process.stderr.write(`${SERVER_NAME} ${SERVER_VERSION}: ${REASON}\n`);

const rl = readline.createInterface({ input: process.stdin, terminal: false });
rl.on('line', (line) => {
  const trimmed = line.trim();
  if (!trimmed) return;
  try {
    handle(JSON.parse(trimmed));
  } catch {
    // A malformed line has no id, so there is nobody to answer. Dropping it is
    // correct; writing to stdout would corrupt the JSON-RPC stream.
  }
});
rl.on('close', () => process.exit(0));
