#!/usr/bin/env node
/**
 * Mobius — ECC Agent Preflight Runner
 *
 * Runs before every request in Mobius Agent mode:
 * 1. Analyzes workspace project structure and language/framework signals using ECC.
 * 2. Matches user prompt against ECC's 300+ skills and component catalog.
 * 3. Prepares optimized context (active instincts, quality gates, recommended skills).
 * 4. Outputs structured JSON for integration into ContinueChatAgent.
 */

'use strict';

const path = require('node:path');
const fs = require('node:fs');

function resolveEccRoot(startDir) {
	const candidates = [];
	if (process.env.MOBIUS_ECC_ROOT) {
		candidates.push(process.env.MOBIUS_ECC_ROOT);
	}
	if (startDir) {
		candidates.push(path.join(startDir, 'resources', 'mobius-ecc'));
		candidates.push(path.join(startDir, 'ECC'));
	}
	// Packaged app: scripts/ -> sibling resources/mobius-ecc
	candidates.push(path.join(__dirname, '..', 'resources', 'mobius-ecc'));
	// Packaged app: inside resources/mobius-ecc/scripts -> parent resources/mobius-ecc
	candidates.push(path.join(__dirname, '..'));
	// Monorepo checkout: scripts/ -> sibling ECC
	candidates.push(path.join(__dirname, '..', 'ECC'));
	// Current working directory
	candidates.push(path.join(process.cwd(), 'resources', 'mobius-ecc'));
	candidates.push(path.join(process.cwd(), 'ECC'));
	if (process.env.LOCALAPPDATA) {
		candidates.push(path.join(process.env.LOCALAPPDATA, 'Programs', 'Mobius', 'resources', 'mobius-ecc'));
	}
	for (const candidate of candidates) {
		try {
			if (candidate && fs.existsSync(candidate) && fs.existsSync(path.join(candidate, 'package.json')) && (fs.existsSync(path.join(candidate, 'scripts', 'ecc.js')) || fs.existsSync(path.join(candidate, 'manifests', 'install-components.json')))) {
				return path.resolve(candidate);
			}
		} catch {
			// continue search
		}
	}
	return undefined;
}

function runPreflight(options = {}) {
	const prompt = (options.prompt || '').trim();
	const cwd = options.cwd ? path.resolve(options.cwd) : process.cwd();
	const eccRoot = options.eccRoot ? path.resolve(options.eccRoot) : resolveEccRoot(cwd);

	if (!eccRoot) {
		return {
			ok: false,
			error: 'ECC submodule not found or uninitialized',
			summary: 'ECC: Not installed or submodule uninitialized',
			systemPrompt: '',
			matchedSkills: [],
			matchedAgents: [],
			projectType: null,
		};
	}

	let projectType = null;
	try {
		const { detectProjectType } = require(path.join(eccRoot, 'scripts', 'lib', 'project-detect.js'));
		projectType = detectProjectType(cwd);
	} catch (err) {
		// Non-fatal fallback
		projectType = { languages: [], frameworks: [], primary: 'unknown', projectDir: cwd };
	}

	let consultResult = null;
	const matchedSkills = [];
	const matchedAgents = [];

	if (prompt) {
		try {
			const { buildConsultation } = require(path.join(eccRoot, 'scripts', 'consult.js'));
			consultResult = buildConsultation({
				query: prompt,
				target: 'antigravity',
				limit: 5,
			});

			for (const match of consultResult.matches || []) {
				if (match.family === 'skill' || match.family === 'capability') {
					const cleanName = match.componentId.replace(/^(skill|capability):/, '');
					matchedSkills.push(cleanName);
				} else if (match.family === 'agent') {
					const cleanName = match.componentId.replace(/^agent:/, '');
					matchedAgents.push(cleanName);
				}
			}
		} catch (err) {
			// Non-fatal fallback
		}
	}

	// Build summary line for chat progress
	const summaryParts = [];
	if (projectType && projectType.primary && projectType.primary !== 'unknown') {
		summaryParts.push(`Stack: ${projectType.primary}`);
	}
	if (matchedSkills.length > 0) {
		summaryParts.push(`Skills: ${matchedSkills.slice(0, 3).map(s => `\`${s}\``).join(', ')}`);
	}
	if (matchedAgents.length > 0) {
		summaryParts.push(`Agents: ${matchedAgents.slice(0, 2).map(a => `\`${a}\``).join(', ')}`);
	}
	const summary = summaryParts.length > 0
		? `ECC Preflight: Active (${summaryParts.join(' | ')})`
		: 'ECC Preflight: Active (General dev optimized)';

	// Build XML system prompt injection
	const promptLines = [
		'<ecc-context origin="submodules/ECC">',
		'<!-- Everything Claude Code (ECC) engineering harness active for this request -->',
		'<ecc-status readiness="active" />',
	];

	if (projectType) {
		promptLines.push(
			`<project-environment languages="${(projectType.languages || []).join(',')}" frameworks="${(projectType.frameworks || []).join(',')}" primary="${projectType.primary || ''}" root="${projectType.projectDir || cwd}" />`
		);
	}

	if (matchedSkills.length > 0 || matchedAgents.length > 0) {
		promptLines.push('<ecc-recommendations>');
		if (matchedSkills.length > 0) {
			promptLines.push(`  <recommended-skills>${matchedSkills.join(', ')}</recommended-skills>`);
		}
		if (matchedAgents.length > 0) {
			promptLines.push(`  <recommended-agents>${matchedAgents.join(', ')}</recommended-agents>`);
		}
		for (const match of (consultResult?.matches || []).slice(0, 3)) {
			promptLines.push(`  <match id="${match.componentId}" reason="${(match.reasons || []).join('; ')}">${match.description}</match>`);
		}
		promptLines.push('</ecc-recommendations>');
	}

	promptLines.push(
		'<ecc-engineering-principles>',
		'- Disciplined Engineering Loop: Plan -> Test/Audit -> Implement -> Verify -> Document.',
		'- Verification Gate: Never declare complete without verifying with get_errors / build / test.',
		'- Security & Safety: Validate inputs, inspect modified files, protect secrets.',
		'- ECC Tools: You have access to ecc_run, ecc_consult, and ecc_skill for specialized auditing, workflows, and rules.',
		'</ecc-engineering-principles>',
		'</ecc-context>'
	);

	const systemPrompt = promptLines.join('\n');

	return {
		ok: true,
		summary,
		systemPrompt,
		matchedSkills,
		matchedAgents,
		projectType,
	};
}

function parseArgs(args) {
	const options = { prompt: '', cwd: process.cwd(), json: false };
	for (let i = 0; i < args.length; i++) {
		const arg = args[i];
		if (arg === '--json') {
			options.json = true;
		} else if (arg === '--cwd' && i + 1 < args.length) {
			options.cwd = args[++i];
		} else if (!arg.startsWith('--')) {
			options.prompt = options.prompt ? `${options.prompt} ${arg}` : arg;
		}
	}
	return options;
}

function main() {
	const options = parseArgs(process.argv.slice(2));
	const result = runPreflight(options);

	if (options.json) {
		console.log(JSON.stringify(result, null, 2));
	} else {
		console.log(result.summary);
		if (result.systemPrompt) {
			console.log('\n--- System Prompt ---\n' + result.systemPrompt);
		}
	}
}

if (require.main === module) {
	main();
}

module.exports = {
	resolveEccRoot,
	runPreflight,
};
