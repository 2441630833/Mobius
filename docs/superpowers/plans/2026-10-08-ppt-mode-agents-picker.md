# PPT Mode in Mobius Agents Window Picker

## Root cause

Mobius previously supported Agent, Game, and Chip modes in the Agents picker (`ModePickerActionItem` + `getMobiusChatModes()`).
The user wants to add a dedicated **PPT mode** to the Agents picker, backed by the `ppt-master` skill project (`https://github.com/hugohe3/ppt-master`), specifically designed for AI-powered PowerPoint / presentation generation and slide design.

## Goal

- `ppt-master` is cloned and integrated as a native skill / payload in Mobius.
- PPT mode appears in the Agents dropdown alongside Agent, Game, and Chip, with its own icon, hover documentation, and detail line ("Make presentations · slide design").
- Selecting PPT mode:
  - Uses Agent tools (file edits, read, search, bash/terminal, etc.) without auto-opening Godot.
  - Injects PPT system instructions and skills context from `ppt-master`.
  - Supports slash command `/ppt` and auto-intent routing for presentation/slides keywords.
  - Has bundled agent definitions in `.github/agents/PPT.agent.md` and `vscode/src/vs/workbench/contrib/continue/mobius/agents/PPT.agent.md`.
- Builds and typechecks pass with 0 errors.

## Non-goals

- Altering existing Game or Chip workflows.
- Touching unrelated submodule pointer changes.

## Tasks

1. [x] Pull latest code in main repo.
2. [x] Finish cloning/extracting `ppt-master` and place skill in `.agents/skills/ppt-master` / workspace.
3. [x] Create `.github/agents/PPT.agent.md`, `vscode/.github/agents/PPT.agent.md`, and `vscode/src/vs/workbench/contrib/continue/mobius/agents/PPT.agent.md`.
4. [x] Update `vscode` mode picker & icons:
   - `continueProduct.ts`: add `CONTINUE_PPT_AGENT_ID`.
   - `continueMobiusBundledAgents.ts`: include `PPT` in `MOBIUS_BUNDLED_AGENT_NAMES`.
   - `continueMobiusModeIcons.ts`: add `MOBIUS_MODE_PPT_ICON`, `isMobiusPptMode`, update `getMobiusChatModeIcon`.
   - `continue.contribution.ts`: register icon `mobius-mode-ppt`.
   - `continueMobiusModeIcons.css`: add SVG icon styling for `codicon-mobius-mode-ppt`.
5. [x] Update mode routing & intent detection:
   - `continueMobiusModeRouting.ts`:
     - add `PPT` to `getMobiusChatModes`.
     - add hover and detail line for PPT mode.
     - add `'ppt'` to `MobiusRoutableMode`.
     - add `/ppt` slash override and `hasPptIntent` detection.
     - update `resolveMobiusChatMode` and test prompts.
   - `continueChatAgent.ts`:
     - recognize PPT mode as agent mode (`isPptModeSelected`, `isAgentMode`).
     - inject PPT system prompt / instructions.
     - ensure Godot is NOT auto-bootstrapped.
6. [x] Verify compilation and tests in `vscode` (`compile-client` finished with 0 errors).
7. [x] Clean up temporary files, stage and commit changes.

## Acceptance criteria

- Agents picker list contains Agent, Game, Chip, PPT.
- PPT detail line: "Make presentations · slide design".
- PPT mode hover explains slide deck generation and presentation design.
- PPT mode does not bootstrap Godot.
- PPT mode inherits full Agent editing tools and injects PPT skill instructions.
