# 2026-09-03 — Show agent outputs live during Thinking/Evaluating

## Root cause
Agent tool/thinking content is pinned into a collapsed thinking container (`chat.agent.thinking.collapsedTools` default `always`). While running, the UI often only shows a shimmer phrase like Evaluating/Thinking, so users cannot see live tool results or streamed text.

## Goal
While an agent turn is running, stream thinking text and tool outputs in the open chat surface so users can see the agent is working.

## Non-goals
- Removing the Thinking/Evaluating status label
- Changing tool permission / auto-approve behavior

## Tasks
1. [x] Default `chat.agent.thinking.collapsedTools` to `off` so tools render as normal chat parts.
2. [x] Default `chat.agent.thinkingStyle` to `collapsedPreview` so thinking expands while streaming and collapses when done.
3. [x] For FixedScrolling users: start expanded while streaming so the panel content is in the foreground.
4. [x] Also set Continue extension `configurationDefaults` so Mobius installs pick up the live-output defaults.
5. [x] Keep elapsed-time status from the prior fix.

## Verified evidence

- `chat.shared.contribution.ts`: `ChatConfiguration.ThinkingStyle` default = `'collapsedPreview'` (grep-confirmed).
- Continue `package.json` `configurationDefaults`: `"chat.agent.thinkingStyle": "collapsedPreview"`, `"chat.agent.thinking.collapsedTools": "off"` (grep-confirmed).
- `chatThinkingContentPart.test.ts` covers CollapsedPreview/FixedScrolling streaming expansion.

## Acceptance
- During a running agent turn, tool invocation rows and thinking text are visible without expanding a dropdown first.
- Evaluating/Thinking still shows with elapsed time.
- After the turn completes, thinking can collapse again (CollapsedPreview behavior).
