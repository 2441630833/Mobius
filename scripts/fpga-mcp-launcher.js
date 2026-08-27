#!/usr/bin/env node
/**
 * Mobius — custom-fpga-mcp launcher.
 *
 * The real server is Python (fastmcp + pyserial) and lives in
 * chip-design/mcp/custom_fpga_mcp. The IDE, however, can only be relied on to
 * have Node, and it spawns MCP servers with an unpredictable cwd. This shim
 * bridges the two:
 *
 *   1. Walk upward to find the Mobius checkout (chip-design/mcp/custom_fpga_mcp).
 *   2. Resolve an interpreter that can actually import fastmcp, in order:
 *        FPGA_MCP_PYTHON  ->  chip-design/.venv  ->  python/python3/py on PATH
 *   3. exec `<python> -m custom_fpga_mcp serve` with PYTHONPATH pointed at the
 *      package, inheriting stdio so the MCP stream passes straight through.
 *
 * If no usable interpreter exists we do NOT fail silently. Chip mode would then
 * present an agent with no tools and no explanation, which reads to the user as
 * "the feature is broken". Instead we hand over to scripts/fpga-mcp-fallback.js:
 * a zero-dependency Node MCP server that answers with the real diagnosis and the
 * exact command to fix it.
 *
 * Deliberately does not install anything. Building a venv or pulling a
 * multi-gigabyte Docker image during IDE startup would hang the extension host
 * with no progress indication; `npm run chip:setup` does that explicitly.
 */
'use strict';

const path = require('path');
const { spawn, spawnSync } = require('child_process');
const resolve = require('./fpga-mcp-resolve');

const REQUIRED_TOOLS = [
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

function parseJsonLines(text) {
  const out = [];
  for (const line of String(text || '').split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try { out.push(JSON.parse(trimmed)); } catch { /* ignore non-JSON (stderr leaked) */ }
  }
  return out;
}

function roundTripFallback(fallbackPath) {
  const input = [
    JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'initialize', params: {} }),
    JSON.stringify({ jsonrpc: '2.0', id: 2, method: 'tools/list' }),
    JSON.stringify({ jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'fpga_paths' } }),
  ].join('\n') + '\n';

  const res = spawnSync(process.execPath, [fallbackPath], {
    input,
    encoding: 'utf8',
    timeout: 60000,
    env: { ...process.env, FPGA_MCP_FALLBACK_REASON: 'self-test' },
  });
  if (res.error) {
    return { ok: false, error: res.error.message, stdout: res.stdout, stderr: res.stderr };
  }
  const messages = parseJsonLines(res.stdout);
  const byId = new Map(messages.filter((m) => m && m.id != null).map((m) => [m.id, m]));
  const init = byId.get(1);
  const list = byId.get(2);
  const call = byId.get(3);
  const names = ((list && list.result && list.result.tools) || []).map((t) => t.name);
  const missing = REQUIRED_TOOLS.filter((n) => !names.includes(n));
  const detectText = call && call.result && call.result.content && call.result.content[0]
    ? call.result.content[0].text
    : '';
  let callJson = null;
  try { callJson = JSON.parse(detectText); } catch { callJson = null; }
  const ok = Boolean(init && init.result)
    && missing.length === 0
    && callJson
    && typeof callJson === 'object';
  return {
    ok,
    missing,
    tool_count: names.length,
    tools: names,
    call: { name: 'fpga_paths', result: callJson, isError: Boolean(call && call.result && call.result.isError) },
    stderr: res.stderr,
    exit_code: res.status,
  };
}

function runSelfTest() {
  const root = resolve.findRepoRoot();
  const fallback = path.join(__dirname, 'fpga-mcp-fallback.js');
  const pythonFastmcp = root ? resolve.resolveInterpreter(root, 'fastmcp') : null;
  const pythonPkg = root ? resolve.resolveInterpreter(root, 'custom_fpga_mcp') : null;

  const report = {
    ok: false,
    repo_root: root,
    fallback: resolve.isFile(fallback) ? fallback : null,
    interpreter_fastmcp: pythonFastmcp,
    interpreter_package: pythonPkg,
    mode: pythonFastmcp ? 'python' : 'fallback',
  };

  if (!resolve.isFile(fallback)) {
    report.error = 'scripts/fpga-mcp-fallback.js is missing';
    process.stdout.write(JSON.stringify(report, null, 2) + '\n');
    process.exit(1);
  }

  const roundTrip = roundTripFallback(fallback);
  report.fallback_round_trip = roundTrip;

  if (pythonPkg && root) {
    try {
      const detect = spawnSync(pythonPkg, ['-m', 'custom_fpga_mcp', 'detect'], {
        encoding: 'utf8',
        timeout: 120000,
        env: resolve.pythonEnv(root),
        cwd: root,
      });
      report.python_detect_exit = detect.status;
      try { report.python_detect = JSON.parse(detect.stdout); } catch {
        report.python_detect_stdout = (detect.stdout || '').slice(0, 2000);
      }
    } catch (err) {
      report.python_detect_error = err.message;
    }
  }

  report.ok = Boolean(roundTrip.ok);
  process.stdout.write(JSON.stringify(report, null, 2) + '\n');
  process.exit(report.ok ? 0 : 1);
}

if (process.argv.includes('--self-test')) {
  runSelfTest();
} else {
function handOffToFallback(reason) {
  const fallback = path.join(__dirname, 'fpga-mcp-fallback.js');
  if (!resolve.isFile(fallback)) {
    process.stderr.write(
      `custom-fpga-mcp: ${reason}\n` +
      'custom-fpga-mcp: fallback server missing too — run `npm run chip:setup`.\n',
    );
    process.exit(1);
  }
  process.stderr.write(`custom-fpga-mcp: ${reason} — starting diagnostic fallback server.\n`);
  const child = spawn(process.execPath, [fallback, ...process.argv.slice(2)], {
    stdio: 'inherit',
    env: { ...process.env, FPGA_MCP_FALLBACK_REASON: reason },
  });
  child.on('exit', (code, signal) => process.exit(signal ? 1 : (code ?? 1)));
}

const root = resolve.findRepoRoot();
if (!root) {
  handOffToFallback('cannot locate the Mobius checkout (set MOBIUS_ROOT)');
} else {
  const python = resolve.resolveInterpreter(root, 'fastmcp');

  if (!python) {
    handOffToFallback('no interpreter with fastmcp installed');
  } else {
    const child = spawn(python, ['-m', 'custom_fpga_mcp', 'serve', ...process.argv.slice(2)], {
      stdio: 'inherit',
      env: resolve.pythonEnv(root),
      cwd: root,
    });

    child.on('error', (err) => {
      process.stderr.write(`custom-fpga-mcp: failed to spawn ${python}: ${err.message}\n`);
      process.exit(1);
    });
    child.on('exit', (code, signal) => process.exit(signal ? 1 : (code ?? 1)));
  }
}
}
