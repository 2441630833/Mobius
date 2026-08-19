---
name: godot-mcp-integration
description: "Use when adding or maintaining an agent-controllable Godot game development workflow via an MCP server and headless import/run/test commands."
auto-generated: true
generated-at: 2026-08-17T12:32:36.543Z
source-task: "增加个game dev mode, 通过agent 控制godot开发游戏，帮我实现这个功能，文件还是在mobius工作区，不过把godot集成进来后，就可以控制agent将生成的文件直接导入到godot里面去，实时修改，agent也能在godot环境里面做测试"
---
## When to use
- Use when adding or maintaining an agent-controllable Godot game development workflow.
- Use when integrating an external game engine or tool into an MCP-capable coding agent workspace.

## Steps
1. Inspect the workspace MCP config loader and schema (e.g. workspace-level JSON files under .continue/mcpServers in Continue, or equivalent). Make the server config auto-load with cwd set to workspace root. Reuse any existing command transport for stdio.
2. Implement a zero-dependency MCP stdio server. Read newline-delimited JSON-RPC messages from stdin; handle initialize, notifications/initialized, tools/list, and tools/call. Wrap calls in try/catch and always return MCP text content.
3. Expose focused tools:
   - detect: locate the engine binary, version, and target project path from a local pointer file or PATH.
   - project_init: scaffold a minimal project (project config, main scene, main script, test runner).
   - import: run the engine headless with --import --path and return exit code plus logs.
   - run: run headless for a fixed number of frames, scanning output for engine errors.
   - test: run a res:// test runner scene/script and parse pass/fail counts.
4. Add a setup/install script that detects an existing engine install, otherwise downloads a pinned release into an ignored tools directory and writes a local path pointer. Do not commit binaries.
5. Add package scripts that map to the same tool with subcommands for manual fallback (setup, init, import, run, test).
6. Add an alwaysApply workspace rule that teaches the agent to use the tools after writing files and iterate import -> test -> run. Emphasize reading tool results rather than assuming availability.
7. Verify end to end:
   - syntax-check the server script;
   - parse any JSON config;
   - run a self-test flag that exercises tools/list and tools/call over a pipe;
   - run install, import, run, and test against the scaffolded project;
   - commit only source, config, rules, and scaffold; ignore engine binaries and generated cache directories.

## Pitfalls
- MCP config schema mismatches cause silent load failures; match the expected server config shape exactly and avoid extra fields.
- Headless import may fail if the engine binary path has spaces or the project path is relative; always quote and resolve absolute paths.
- Tests must use a res:// path; ensure the project file and main scene are valid.
- Use --quit-after on headless run so the process exits reliably.
- Keep generated engine binaries out of version control by using a path pointer file and ignore rule.
- Validate line-delimited JSON-RPC handling; MCP stdio is newline-delimited, not a single JSON stream.

## Example
Workflow for a request like game dev mode: create a small game:
1. Agent writes scene/script/test files into the project directory.
2. Agent calls detect to confirm engine binary/version.
3. Agent calls import; expect exit 0.
4. Agent calls test; expect pass count greater than 0 and fail count 0.
5. Agent calls run for N frames; expect exit 0 and no engine error lines.
6. Agent reports success and tells the user how to open the editor for live preview.
