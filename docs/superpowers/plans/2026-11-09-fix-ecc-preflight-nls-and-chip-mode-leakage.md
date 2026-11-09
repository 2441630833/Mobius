# Fix ECC Preflight NLS Cache Mismatch and Chip Mode Tool Leakage

## Root Cause

1. **NLS Language Pack Cache Index Shift (Regressions 1, 2, 4)**:
   - When Mobius runs in Simplified Chinese (`zh-cn`), VS Code main process (`main.js`) generates and caches translated messages in `C:\Users\mi\AppData\Roaming\Mobius\clp\<hash>.zh-cn\<commit>\nls.messages.json`.
   - The commit in `product.json` remained unchanged at `37d16c72c8035ee6455b1c522e4dc21c75bc6f80`.
   - Between that older build and the current bundle, the English message list shifted by 1 at index 2206 (20894 vs 20893 items).
   - Because `clp\...` already had a cached `nls.messages.json` for commit `37d16c72...`, VS Code reused the stale cache rather than regenerating it.
   - Consequently, when the newly built bundle called:
     - `d(11300)` (`continue.ecc.visiblePreflight`) -> loaded index 11300 from stale cache = `'not identified'`!
     - `d(11304)` (`continue.selection.candidates`) -> loaded index 11304 from stale cache = `'not specified'`!
     - `d(11305)` (`continue.selection.none`) in `summary()` -> loaded index 11305 from stale cache = `'Automatic routing — suggested skills: {0}; ECC agent profiles: {1}...'`!
     - `d(11311)` (`continue.selection.summary`) in `summary()` -> loaded index 11311 from stale cache = `'Skill read: {0}'`!
     - Result: `Skill read: Automatic routing — suggested skills: {0}; ECC agent profiles: {1}...` displayed with raw unsubstituted placeholders, while ECC preflight and routing banners displayed only `not identified` and `not specified`.

2. **Chip Design & FPGA Tool Schema Leakage into General Workspaces (Regression 3)**:
   - `loadContinueAgentTools` in `continueAgentToolsBridge.ts` unconditionally merged `FPGA_TOOL_SCHEMAS` and `GODOT_TOOL_SCHEMAS` into the general agent tool list.
   - Even when the workspace is completely unrelated (e.g., `e:\JupyterTIGNN\isaac-lab-gr00-t`), `fpga_lint` (top `sampler_uart_top`, Verilator, openXC7, Arty A7), `fpga_simulate`, `fpga_build`, and `fpga_sample` were advertised as available tools to the LLM.
   - When the user greeted the assistant with "hi", the model inspected the available tools in context, saw the FPGA chip design tools alongside TIGNN rules, and incorrectly synthesized both into its opening response.

---

## Goal

1. Restrict `FPGA_TOOL_SCHEMAS` exclusively to Chip mode (`isChipMode === true`).
2. Restrict `GODOT_TOOL_SCHEMAS` exclusively to Game mode (`isGameMode || isGameModeSelected`).
3. Update `apply_hotfix.py` to:
   - Purge stale cached language packs under `AppData\Roaming\Mobius\clp` so VS Code regenerates matching NLS tables.
   - Update `product.json` commit to match current git commit hash so future builds never collide with stale cached language packs.
   - Recompute checksums in `product.json`.
4. Verify typecheck, compile bundle, deploy, and verify NLS message alignment and tool scoping.

---

## Non-Goals

- Do not modify core ECC preflight script logic (`scripts/ecc-agent-preflight.js`).
- Do not commit unrelated dirty submodules (`hermes-agent`, `vendor/fastmcp`, `vendor/litex`, `vendor/litex-boards`, `vendor/mcp-python-sdk`, `vendor/openFPGALoader`).

---

## Tasks

- [x] Task 1: Gate FPGA and Godot tool schemas in `continueAgentToolsBridge.ts`, `continueCopilotToolsBridge.ts`, `continueChatAgent.ts`, and `continueDeepSeekHarness.ts`.
- [x] Task 2: Update `apply_hotfix.py` to clear the `clp` language pack cache and synchronize `product.json` commit with git rev-parse HEAD.
- [x] Task 3: Run client typecheck (`npm --prefix vscode run typecheck-client`).
- [x] Task 4: Build desktop bundle (`bundle --minify --nls --mangle-privates --out out-vscode-min --target desktop`).
- [x] Task 5: Deploy hotfix to `C:\Users\mi\AppData\Local\Programs\Mobius`, clear stale `clp` caches, and verify NLS indices.
- [x] Task 6: Commit changes to vscode submodule and Mobius root repo using UTF-8 safe git commands.

---

## Acceptance Criteria

1. In non-chip mode / non-game mode workspaces (such as `isaac-lab-gr00-t`), `agentTools` contains zero FPGA tools and zero Godot tools.
2. In Chip mode (`/chip` or chip mode selection), `FPGA_TOOL_SCHEMAS` are available.
3. In Game mode (`/game` or game mode selection), `GODOT_TOOL_SCHEMAS` are available.
4. NLS translations in Simplified Chinese correctly show:
   - `ECC preflight — detected stack: ...` (not `not identified`)
   - `Automatic routing — suggested skills: ...` (not `not specified`)
   - `Selection results — skills read/in context: none...` (not `Skill read: Automatic routing — suggested skills: {0}...`)
5. Typecheck exits with code 0; syntax checks pass on all deployed bundles.
