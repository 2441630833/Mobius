# Pinned Providers + Add Provider Implementation Plan

> **For agentic workers:** Execute every task below in this session. Checkboxes track progress.

**Goal:** All `.env` AI profiles appear as pinned options in the Agents + Continue chat pickers by default, and users can add/modify providers from those pickers without hand-editing `.env`.

**Architecture:**
1. Continue GUI `ModelSelect` + Settings `OpenAiEnvSection` (Add Provider create mode).
2. VS Code Agents `chatModelPicker` (new session + chat input): Mobius filterActions (+ / gear) and bottom **Providers** section calling `continue.addModelProvider` / `continue.openModelProviderSettings`; auto-pin all Continue vendor models.

**Tech Stack:** Continue GUI React/Redux, VS Code chat model picker, IdeMessenger `physicalAI/*`, `physicalAiModelEnv.ts` / `continueModelConfig.ts`.

## Root cause

- Chat `ModelSelect` is a flat list with no pinned grouping and no add entry.
- Settings Profile control is a `<select>` of existing profiles only — cannot create a new profile id.
- `OpenAiEnvSection` still selects models as `profileId/model` while config titles are bare profile ids.

## Non-goals

- Changing Cursor IDE itself (screenshots are the UX reference).
- Committing unrelated dirty worktree files (`Directory.Build.targets`, ollama scripts, hermes-agent, vscode submodule pointer unless required for the vscode copy of physicalAiModelEnv).
- Per-message provider switching (already covered by per-chat plan).

## Files to modify

| File | Responsibility |
|------|----------------|
| `continue/gui/src/components/modelSelection/ModelSelect.tsx` | Continue chat picker: Pinned + Add provider |
| `continue/gui/src/pages/config/sections/OpenAiEnvSection.tsx` | Add Provider create mode |
| `continue/gui/src/util/navigation.ts` | `SETTINGS_ADD_PROVIDER` route |
| `continue/gui/src/components/Layout.tsx` | `addModel` → create mode |
| `vscode/.../chatModelPicker.ts` | Agents picker: Add/Modify actions + default pin |
| `vscode/.../continue.contribution.ts` | Auto-pin on reload; F1 actions |
| `continue/extensions/vscode/src/commands.ts` + `package.json` | `continue.addModelProvider` / `openModelProviderSettings` |

## Tasks

- [x] 1. Plan written (this file)
- [x] 2. Upgrade ModelSelect: search, Pinned section, Add provider
- [x] 3. OpenAiEnvSection: Add Provider create-mode + `addProvider=1`
- [x] 4. Wire CONFIG_ROUTES / navigate with addProvider flag
- [x] 5. Agents chatModelPicker: Add Provider + Modify Providers (search bar + list footer)
- [x] 6. Auto-pin all Continue models; register continue commands
- [x] 7. Lint-check edited files; mark tasks done

## Acceptance criteria

1. Agents new-session and chat input model pickers show **Add Provider...** and **Modify Providers...**.
2. Search bar shows + / gear filter actions for the same flows.
3. All Continue/.env profiles default under **Pinned**.
4. Add/Modify opens an Agents-visible QuickInput wizard (not webview navigate alone).
5. Continue chat ModelSelect still has Add provider entry.

---
