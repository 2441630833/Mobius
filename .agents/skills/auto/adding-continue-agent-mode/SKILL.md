---
name: adding-continue-agent-mode
description: "Use when adding a new message mode to a Continue-based IDE extension, including the mode selector UI, system prompt routing, auto-approve behavior, and context gathering."
auto-generated: true
generated-at: 2026-08-17T23:28:31.552Z
source-task: "i remember this project used to have the mode selection, like the plan mode add game mode to that mode selection panel, and only select the game mode triggger the `game-dev/` → `godot_import` → `godo…"
---
## When to use
Use when you need to add a new mode (e.g. specialized agent mode) to a Continue-based IDE extension and want it to be selectable, behave differently, and route to a dedicated system message. If a similar mode-extension skill already exists, update it instead of creating a duplicate.

## Steps
1. Locate the shared message-mode union type in the core definitions and add the new mode string. This is the source of truth for all mode checks.
2. Update the mode selection UI: add the new option to the mode dropdown and cycle logic; add an icon in the mode icon component if needed.
3. Update mode-specific behavior utilities:
   - auto-approve rules: decide whether the mode should auto-approve tool calls/diffs like agent mode.
   - editor context resolution and mention dropdown: ensure the mode passes or gathers the same context as agent mode if it should use tools.
4. Add or route to a dedicated system message: create a default system message constant and update the base system message selector to return it for the new mode.
5. Verify tool availability: check the active-tools selector to confirm the mode inherits the desired tools. Often any mode other than chat/plan already gets all write tools automatically; do not duplicate that logic.
6. If the mode triggers an external loop, add any missing MCP/CLI tool (e.g. preview, run) to the relevant server script and register it in the tool list, self-test, and help output.
7. Validate: run syntax checks on modified scripts, run TypeScript no-emit checks, run the external tool's self-test/test/run commands, and verify the mode cycles and system message routing manually or via existing tests.
8. Commit changes in logical groups, separating mode wiring from external loop wiring when possible.

## Pitfalls
- The mode union type is used in many places; failing to update it causes TypeScript errors downstream.
- The mode selector cycle order and keyboard shortcut may be hard-coded in several spots; update all occurrences.
- Auto-approve and context gathering are often keyed by explicit modes. A new mode silently falls back to chat/plan behavior when not added.
- Tool availability may already be correct for any non-chat/plan mode; check before adding duplicate tool-selection logic.
- External MCP tools usually require both command registration and help/self-test updates; missing one breaks tool discovery.
- System message routing may have unit tests that assert exact mode arrays; update the expected arrays/modes in those tests.

## Example
Adding a custom "research" mode:
- Add "research" to the core mode union.
- Add a Research option with an icon to the mode selection component and cycle list.
- In auto-approve, treat research like agent if it should run unattended.
- In editor content resolution and the mention dropdown, include research alongside agent if it needs context.
- Add DEFAULT_RESEARCH_SYSTEM_MESSAGE and route mode === "research" to it in the base system message selector.
- Run type checks and existing unit tests. If research drives an external MCP loop, add any missing tool (e.g. preview or run) to the MCP server and update its tool list.
