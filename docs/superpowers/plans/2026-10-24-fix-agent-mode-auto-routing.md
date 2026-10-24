# Fix Agent Mode Auto-Routing False Positives

## Root cause

When a user prompt such as `git pull the latest code and 启动服务` is submitted in Mobius, it is erroneously auto-routed to `Chip` mode, triggering `fpga_detect (Chip mode, automatic)` on a general web project.
Analysis revealed multiple compounding root causes:
1. **Stopword Hash Collisions**: In `continueSkillEmbeddings.ts`, `embedTextLocal` computes character 3-grams and tokens without stopword filtering. In short prompts containing common English words (`and`, `the`), collision with Chip utterances (`... Verilog RTL with verilator and inspect waveforms`) yields ~0.2621 cosine similarity purely by chance.
2. **Artificial 2x Multiplier**: In `continueSemanticRouter.ts`, any `semanticScore >= 0.25` is multiplied by 2.0 (`0.2621 * 2 = 0.5242`), crossing the Chip threshold of 0.50 without any lexical keywords.
3. **Missing Lexical Hard-Gating for Specialized Hardware/Engine Modes**: `CHIP_ROUTE` and `GAME_ROUTE` are invasive modes that auto-run hardware/engine probes (`fpga_detect`, Godot). They should never trigger on pure weak semantic similarity without domain keywords.
4. **General Dev / DevOps Signals Not Prioritized**: `AGENT_SIGNAL` and general DevOps commands (`git`, `pull`, `commit`, `service`, `启动`, `npm`) were not checked before semantic routing, nor treated as anti-patterns for specialized modes.
5. **Auto-routing Setting Not Wired**: `mobius.autoModeRouting.enabled` was defined but not checked.

## Goal

1. Guarantee that at least 80% of daily requests (especially Git, service startup, file manipulation, and general software engineering) default cleanly to `Agent` mode.
2. For intrusive vertical modes (`chip`, `game`), enforce **Lexical Hard-Gating**: require explicit domain keywords (e.g. `fpga`, `verilog`, `rtl`, `godot`) before routing to them.
3. Filter high-frequency stopwords (`and`, `the`, `with`, `for`, `in`, `to`, `is`, `of`, `在`, `和`, `的`, etc.) in `tokenizeForEmbed` to eliminate spurious n-gram hash collisions on short texts.
4. Remove the `semanticScore * 2.0` artificial inflation in `continueSemanticRouter.ts`. Use calibrated, strict thresholds.
5. Add general DevOps / Git / server anti-patterns to `CHIP_ROUTE` and `GAME_ROUTE`.
6. Add `GENERAL_DEV_FAST_PATH` in `inferMobiusModeFromPrompt` so general dev operations immediately stay in default `agent` mode.
7. Add comprehensive unit tests in `continueMobiusModeRouting.test.ts`.

## Non-goals

- Disabling intentional slash commands (`/chip`, `/game`, `/ppt`, `/agent`).
- Breaking legitimate presentation generation requests routed to PPT mode (`/ppt` or "制作一份关于量子计算的PPT").
- Altering the underlying `fpga_detect` tool or `ppt-master` skill implementations.

## Tasks

1. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueSkillEmbeddings.ts`: filter high-frequency stopwords in `tokenizeForEmbed`.
2. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueSemanticRouter.ts`:
   - Add `requiresLexicalPattern: true` for `CHIP_ROUTE` and `GAME_ROUTE`.
   - Remove `semanticScore * 2.0` artificial inflation; compute calibrated composite score.
   - Add DevOps/Git/service anti-patterns to `CHIP_ROUTE` and `GAME_ROUTE`.
3. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueMobiusModeRouting.ts`:
   - Add `GENERAL_DEV_SIGNAL` check before fallback to specialized modes.
4. [x] Update `vscode/src/vs/workbench/contrib/continue/test/browser/continueMobiusModeRouting.test.ts`:
   - Add test cases for `git pull the latest code and 启动服务`, `git pull origin main`, `拉取最新代码并启动本地服务`, `帮我启动一下后端服务`, `运行测试用例 npm test`.
   - Verify all tests pass.
5. [x] Verify compilation and tests with 0 errors.
6. [x] Commit changes cleanly.

## Acceptance criteria

- `inferMobiusModeFromPrompt('git pull the latest code and 启动服务')` returns `agent` (or undefined, defaulting to agent), NEVER `chip`.
- All common DevOps/Git/service prompts stay in `agent` mode.
- Legitimate chip requests (`在chip-design里检查FPGA...`, `编写Verilog...`, `/chip`) still route to `chip`.
- Legitimate game requests (`在game-dev里用Godot...`, `/game`) still route to `game`.
- Legitimate PPT requests (`制作一份关于量子计算的PPT`, `/ppt`) still route to `ppt`.
- Compilation and unit tests pass with 0 errors.
