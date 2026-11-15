#!/usr/bin/env node
// Mobius Linux smoke test — drives a packaged build end-to-end under Xvfb.
//   node scripts/smoke-test-linux.mjs /usr/share/mobius/mobius
// Requires: playwright-core (npm i playwright-core), xvfb-run.
// Checks the web-search regression on Linux:
//   1. app starts, main workbench renders
//   2. a stale `continue.webSearch.enabled: false` (left by older builds) is repaired on startup
//   3. Agents window opens with a workspace + model (mock OpenAI-compatible server)
//   4. the model is offered search_web and no <web-search-disabled> hint is injected
//   5. a search_web call is executed (not rejected as "disabled by the user"/"no network")
//   6. Web Search chip renders "On"; Off really stops search_web; On restores it; both persist
import { chromium } from 'playwright-core';
import { spawn } from 'child_process';
import http from 'http'; import fs from 'fs'; import os from 'os'; import path from 'path';

// Mock OpenAI-compatible server. 1st turn: asks to call search_web. Next turn: records the
// tool result Mobius sent back and replies with a final answer.
function startMockLlm(port, logFile) {
  const log = (o) => fs.appendFileSync(logFile, JSON.stringify(o) + '\n');
  const srv = http.createServer((req, res) => {
    let body = ''; req.on('data', c => body += c); req.on('end', () => {
      if (req.method === 'GET') { res.setHeader('content-type', 'application/json'); return res.end(JSON.stringify({ object: 'list', data: [{ id: 'mock-model', object: 'model' }] })); }
      let j = {}; try { j = JSON.parse(body); } catch {}
      const msgs = j.messages || [];
      const toolMsgs = msgs.filter(m => m.role === 'tool');
      const toolNames = (j.tools || []).map(t => t.function?.name);
      log({ disabledHint: /web-search-disabled/.test(JSON.stringify(msgs)), path: req.url, stream: !!j.stream, nMsgs: msgs.length, hasSearchTool: toolNames.includes('search_web'), toolNames: toolNames.slice(0, 80), lastUser: (msgs.filter(m => m.role === 'user').pop()?.content || '').toString().slice(-600), toolResults: toolMsgs.map(m => (typeof m.content === 'string' ? m.content : JSON.stringify(m.content)).slice(0, 1500)) });
      const wantsTool = toolNames.includes('search_web') && !toolMsgs.some(m => true) && /latest|search|最新/i.test(JSON.stringify(msgs.slice(-1)));
      const chunk = (delta, finish = null) => `data: ${JSON.stringify({ id: 'x', object: 'chat.completion.chunk', created: 0, model: 'mock-model', choices: [{ index: 0, delta, finish_reason: finish }] })}\n\n`;
      if (j.stream) {
        res.writeHead(200, { 'content-type': 'text/event-stream' });
        if (wantsTool) {
          res.write(chunk({ role: 'assistant', tool_calls: [{ index: 0, id: 'call_1', type: 'function', function: { name: 'search_web', arguments: '' } }] }));
          res.write(chunk({ tool_calls: [{ index: 0, function: { arguments: JSON.stringify({ query: 'latest Node.js LTS release' }) } }] }));
          res.write(chunk({}, 'tool_calls'));
        } else {
          res.write(chunk({ role: 'assistant', content: 'MOCK_FINAL_ANSWER done.' }));
          res.write(chunk({}, 'stop'));
        }
        res.end('data: [DONE]\n\n');
      } else {
        res.setHeader('content-type', 'application/json');
        res.end(JSON.stringify({ id: 'x', object: 'chat.completion', created: 0, model: 'mock-model', choices: [{ index: 0, finish_reason: wantsTool ? 'tool_calls' : 'stop', message: wantsTool ? { role: 'assistant', content: null, tool_calls: [{ id: 'call_1', type: 'function', function: { name: 'search_web', arguments: JSON.stringify({ query: 'latest Node.js LTS release' }) } }] } : { role: 'assistant', content: 'MOCK_FINAL_ANSWER done.' } }] }));
      }
    });
  });
  srv.listen(port, '127.0.0.1');
  return srv;
}


const exe = process.argv[2];
if (!exe) { console.error('usage: smoke-test-linux.mjs <path-to-mobius-binary>'); process.exit(2); }
const OUT = process.env.SMOKE_OUT || fs.mkdtempSync(path.join(os.tmpdir(), 'mobius-smoke-')); fs.mkdirSync(OUT, { recursive: true });
const results = [];
const check = (name, ok, detail = '') => {
  results.push({ name, ok, detail });
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  — ' + detail : ''}`);
  if (process.env.GITHUB_ACTIONS) console.log(`::${ok ? 'notice' : 'error'} title=smoke::${ok ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + String(detail).replace(/[\r\n]+/g, ' ').slice(0, 900) : ''}`);
};
const sleep = ms => new Promise(r => setTimeout(r, ms));

const ud = fs.mkdtempSync(path.join(os.tmpdir(), 'mobius-ud-'));
const ws = fs.mkdtempSync(path.join(os.tmpdir(), 'mobius-ws-'));
const home = fs.mkdtempSync(path.join(os.tmpdir(), 'mobius-home-'));
const llmPort = 18000 + Math.floor(Math.random() * 1000);
const llmLog = path.join(OUT, 'mockllm.jsonl'); fs.writeFileSync(llmLog, '');
const llm = startMockLlm(llmPort, llmLog);
fs.writeFileSync(path.join(ws, 'README.md'), '# smoke\n');
fs.mkdirSync(path.join(home, '.continue'), { recursive: true });
fs.writeFileSync(path.join(home, '.continue', 'config.yaml'), `name: mock\nversion: 0.0.1\nschema: v1\nmodels:\n  - name: mock-model\n    provider: openai\n    model: mock-model\n    apiBase: http://127.0.0.1:${llmPort}/v1\n    apiKey: sk-mock\n    roles: [chat, edit, apply]\n    capabilities: [tool_use]\n`);
const settingsPath = path.join(ud, 'User', 'settings.json');
fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
fs.writeFileSync(settingsPath, JSON.stringify({ 'continue.webSearch.enabled': false, 'security.workspace.trust.enabled': false }, null, 2));
const readSetting = () => { try { return JSON.parse(fs.readFileSync(settingsPath, 'utf8'))['continue.webSearch.enabled']; } catch { return '<unreadable>'; } };

const cdpPort = 9300 + Math.floor(Math.random() * 500);
const proc = spawn(exe, ['--no-sandbox', '--disable-gpu', `--remote-debugging-port=${cdpPort}`, `--user-data-dir=${ud}`, '--skip-welcome', '--skip-release-notes', ws],
  { env: { ...process.env, HOME: home, ELECTRON_ENABLE_LOGGING: '1' } });
const appLog = fs.createWriteStream(path.join(OUT, 'app.log')); proc.stdout.pipe(appLog); proc.stderr.pipe(appLog);
const finish = async (browser) => {
  await browser?.close().catch(() => {}); proc.kill(); llm.close();
  console.log(`\n${results.filter(r => r.ok).length}/${results.length} checks passed  (artifacts in ${OUT})`);
  process.exit(results.every(r => r.ok) ? 0 : 1);
};

let browser;
for (let i = 0; i < 90 && !browser; i++) { try { browser = await chromium.connectOverCDP(`http://127.0.0.1:${cdpPort}`); } catch { await sleep(1000); } }
if (!browser) { check('app exposes a window', false, 'no debugging endpoint — app failed to start (see app.log)'); await finish(); }
const pages = () => browser.contexts().flatMap(c => c.pages());
const errors = [];
let main;
for (let i = 0; i < 90 && !main; i++) { for (const p of pages()) if (await p.$('.monaco-workbench').catch(() => null)) main = p; if (!main) await sleep(1000); }
check('main workbench window opens', !!main, main ? await main.title() : '');
if (!main) await finish(browser);
main.on('pageerror', e => errors.push(e.message));

let v = readSetting();
for (let i = 0; i < 30 && v === false; i++) { await sleep(1000); v = readSetting(); }
check('stale continue.webSearch.enabled=false is repaired on startup', v !== false, `value now: ${JSON.stringify(v)}`);

await sleep(4000);
await main.click('.open-in-agents-titlebar-widget', { timeout: 15000 }).catch(() => main.keyboard.press('Control+Shift+A'));
let agents;
for (let i = 0; i < 60 && !agents; i++) { for (const p of pages()) if (/\/sessions\//.test(p.url())) agents = p; if (!agents) await sleep(1000); }
check('Agents window opens', !!agents);
if (!agents) await finish(browser);
agents.on('pageerror', e => errors.push(e.message));
let modelLabel = '';
for (let i = 0; i < 40 && !/mock/.test(modelLabel); i++) { modelLabel = await agents.$eval('.model-picker-split', e => e.textContent.trim()).catch(() => ''); if (!/mock/.test(modelLabel)) await sleep(1000); }
check('model from ~/.continue/config.yaml is loaded', /mock/.test(modelLabel), modelLabel);

await agents.screenshot({ path: path.join(OUT, '1-agents-ready.png') });

await agents.click('.interactive-input-editor').catch(() => {});
await agents.keyboard.type('Please search the latest Node.js LTS release');
await agents.keyboard.press('Enter');
const readReqs = () => fs.readFileSync(llmLog, 'utf8').trim().split('\n').filter(Boolean).map(l => JSON.parse(l));
let reqs = [];
for (let i = 0; i < 120; i++) { reqs = readReqs(); if (reqs.some(r => r.toolResults.length)) break; await sleep(1000); }
await sleep(3000);
await agents.screenshot({ path: path.join(OUT, '2-after-search.png') });
check('model request received', reqs.length > 0, `${reqs.length} request(s)`);
check('search_web offered to the model', reqs.some(r => r.hasSearchTool), reqs.length ? `tools: ${reqs[0].toolNames.slice(0, 25).join(',')}` : '');
check('no <web-search-disabled> hint injected', !reqs.some(r => r.disabledHint));
const toolResult = (reqs.find(r => r.toolResults.length)?.toolResults || []).join(' ');
check('search_web was executed, not rejected', !!toolResult && !/disabled by the user|no network connection detected/i.test(toolResult), toolResult.slice(0, 400) || 'no tool result came back');

// --- Web Search chip (rendered once a session is active) ---
const chip = agents.locator('.action-label.chat-web-search-button').first();
let chipFound = false;
for (let i = 0; i < 20 && !chipFound; i++) { chipFound = await chip.count() > 0; if (!chipFound) await sleep(1000); }
check('Web Search chip is rendered in the session input', chipFound);
if (chipFound) {
  const state = async () => ({ text: (await chip.textContent())?.trim(), cls: await chip.getAttribute('class') });
  const s0 = await state();
  check('chip shows On and is clickable', /On/.test(s0.text) && /\bchecked\b/.test(s0.cls) && !/(^|\s)disabled(\s|$)/.test(s0.cls), `${s0.text} [${s0.cls}]`);
  await chip.click(); await sleep(1500);
  const s1 = await state();
  check('chip click -> Off (persisted to settings.json)', /Off/.test(s1.text) && readSetting() === false, `${s1.text} / setting=${JSON.stringify(readSetting())}`);
  // With search Off, a new request must not offer search_web and must carry the disabled hint.
  const before = readReqs().length;
  await agents.click('.interactive-input-editor').catch(() => {});
  await agents.keyboard.type('Please search the latest Python release');
  await agents.keyboard.press('Enter');
  for (let i = 0; i < 60 && readReqs().length <= before; i++) await sleep(1000);
  await sleep(5000);
  const offReqs = readReqs().slice(before);
  check('with chip Off the agent does not offer search_web', offReqs.length > 0 && !offReqs.some(r => r.hasSearchTool) && offReqs.some(r => r.disabledHint), `${offReqs.length} request(s)`);
  await chip.click(); await sleep(1500);
  const s2 = await state();
  check('chip click -> On again (persisted)', /On/.test(s2.text) && readSetting() === true, `${s2.text} / setting=${JSON.stringify(readSetting())}`);
  await agents.screenshot({ path: path.join(OUT, '3-chip.png') });
}

const fatal = errors.filter(e => !/ResizeObserver|Canceled|Found unexpected null/.test(e));
if (fatal.length) console.log('INFO  renderer errors:', fatal.slice(0, 5).join(' | '));
await finish(browser);
