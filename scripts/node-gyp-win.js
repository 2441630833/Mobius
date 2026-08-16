#!/usr/bin/env node
'use strict';

/**
 * Windows node-gyp wrapper: passes /p:SpectreMitigation=false to MSBuild.
 * npm's npm_config_msbuild_args is not read by node-gyp; VS 2026 + Electron
 * headers emit vcxproj files with SpectreMitigation=Spectre (MSB8040 / LNK1181).
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

function resolveNodeGypBin() {
  const npmNodeGyp = path.join(
    path.dirname(process.execPath),
    'node_modules',
    'npm',
    'node_modules',
    'node-gyp',
    'bin',
    'node-gyp.js',
  );
  if (fs.existsSync(npmNodeGyp)) {
    return npmNodeGyp;
  }

  try {
    return require.resolve('node-gyp/bin/node-gyp.js');
  } catch {
    // fall through
  }
  if (process.env.MOBIUS_NODE_GYP_BIN && fs.existsSync(process.env.MOBIUS_NODE_GYP_BIN)) {
    return process.env.MOBIUS_NODE_GYP_BIN;
  }
  if (process.env.NPM_NODE_GYP_BIN) {
    return process.env.NPM_NODE_GYP_BIN;
  }
  try {
    return require.resolve('node-gyp/bin/node-gyp.js');
  } catch {
    const npmRoot = path.join(path.dirname(process.execPath), 'node_modules', 'npm', 'node_modules', 'node-gyp', 'bin', 'node-gyp.js');
    if (fs.existsSync(npmRoot)) {
      return npmRoot;
    }
    throw new Error('node-gyp not found');
  }
}

function runNodeGyp(nodeGyp, args, extraEnv = {}) {
  const result = spawnSync(process.execPath, [nodeGyp, ...args], {
    stdio: 'inherit',
    env: { ...process.env, ...extraEnv },
    shell: false,
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function readConfigGypi() {
  const configPath = path.join(process.cwd(), 'build', 'config.gypi');
  const raw = fs.readFileSync(configPath, 'utf8').replace(/#.+\n/, '');
  return JSON.parse(raw);
}

function platformForArch(arch) {
  switch ((arch || '').toLowerCase()) {
    case 'x64': return 'x64';
    case 'arm64': return 'ARM64';
    case 'arm': return 'ARM';
    default: return 'Win32';
  }
}

function runMsBuildWithSpectreDisabled() {
  const config = readConfigGypi();
  const msbuild = config.variables?.msbuild_path;
  if (!msbuild) {
    console.error('node-gyp-win: msbuild_path missing in build/config.gypi');
    process.exit(1);
  }

  const buildDir = path.join(process.cwd(), 'build');
  const sln = fs.readdirSync(buildDir).find((name) => name.endsWith('.sln'));
  if (!sln) {
    console.error('node-gyp-win: no .sln under build/');
    process.exit(1);
  }

  const buildType = config.target_defaults?.default_configuration || 'Release';
  const platform = platformForArch(config.variables?.target_arch);

  const result = spawnSync(
    msbuild,
    [
      path.join('build', sln),
      '/nologo',
      '/clp:Verbosity=minimal',
      '/nodeReuse:false',
      `/p:Configuration=${buildType}`,
      `/p:Platform=${platform}`,
      '/p:SpectreMitigation=false',
    ],
    { stdio: 'inherit', cwd: process.cwd(), shell: false, env: process.env },
  );
  process.exit(result.status ?? 1);
}

const nodeGyp = resolveNodeGypBin();
const args = process.argv.slice(2);
const command = args[0];

if (process.platform === 'win32' && (command === 'build' || command === 'rebuild')) {
  if (command === 'rebuild') {
    runNodeGyp(nodeGyp, ['clean', ...args.slice(1)]);
    runNodeGyp(nodeGyp, ['configure', ...args.slice(1)]);
  } else {
    runNodeGyp(nodeGyp, ['configure', ...args.slice(1)]);
  }
  runMsBuildWithSpectreDisabled();
}

runNodeGyp(nodeGyp, args);
