# Fix Manage Todo List Infinite Loop and Circuit Breaker

## Root cause
When running local/open-weight models (such as Qwen on Linux ARM), the agent triggers:
`⚠️ 检测到工具调用死循环 (manage_todo_list 被反复调用但没有产生任何进展)，已停止工具并直接根据已有结果输出答案。`
This occurs due to three compounding causes:
1. `manageTodoListTool.ts` strictly requires `args.todoList` to be an array with property name `todoList`. When models emit common variations (`todos`, `items`, `tasks`, `todo_list`, `list`, JSON-stringified payloads, string IDs, or single objects), `handleWriteOperation` rejects the invocation with `Error: todoList is required for write operation`.
2. `manageTodoListTool.ts` attaches discouraging warnings in model-facing output (`Warning: Small todo list (<3 items)...`, `Warning: Did you mean to update so many todos...`), which mislead models into retrying `manage_todo_list`.
3. In `continueChatAgent.ts`, `MAX_IDENTICAL_TOOL_REPEATS = 2` and `MAX_NO_PROGRESS_CONTROL_TURNS = 2` are hyper-aggressive. `manage_todo_list` is not in `VOLATILE_TOOL_NAMES`, and when `controlOnlyTurn` encounters 2 consecutive turns without todos state change, it executes a hard `break;` which completely terminates the user's task instead of letting the agent proceed with execution.

## Goal
1. Normalize and coerce all parameter variations for `manage_todo_list` in both `manageTodoListTool.ts` and `continueCopilotToolsBridge.ts`.
2. Remove confusing warnings from the model-facing text response in `handleWriteOperation`.
3. Relax circuit breaker thresholds (`MAX_IDENTICAL_TOOL_REPEATS = 5`, `MAX_NO_PROGRESS_CONTROL_TURNS = 5`), add `manage_todo_list` variants to `VOLATILE_TOOL_NAMES`, and convert the todo control-only loop trigger into a non-destructive nudge to proceed with the actual task execution rather than aborting.
4. Verify compilation and tests.

## Non-goals
- Do not remove the circuit breaker for truly stuck non-volatile tools (e.g. repeated identical file reads).
- Do not alter the underlying `IChatTodoListService` storage or schema.

## Tasks
1. [x] Update `vscode/src/vs/workbench/contrib/chat/common/tools/builtinTools/manageTodoListTool.ts`:
   - Implement `normalizeTodoListArgs` supporting `todos`, `todo_list`, `items`, `tasks`, `list`, `plan`, `steps`, JSON strings, string IDs, and relaxed status mappings.
   - Use `normalizeTodoListArgs` in `invoke` and `prepareToolInvocation`.
   - Clean up model-facing text payload in `handleWriteOperation`.
2. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueCopilotToolsBridge.ts`:
   - Normalize arguments when invoking `manage_todo_list`.
   - Recognize `todo`, `todos`, `manageTodoList` in `resolveToolIdForModelName`.
3. [x] Update `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts`:
   - Increase `MAX_IDENTICAL_TOOL_REPEATS` to 5 and `MAX_NO_PROGRESS_CONTROL_TURNS` to 5.
   - Add `manage_todo_list`, `todo`, `todos`, `manageTodoList` to `VOLATILE_TOOL_NAMES`.
   - Update `isManageTodoListTool` to handle casing/hyphens.
   - Instead of `break;` on `controlOnlyTurn && noProgressControlTurns >= MAX_NO_PROGRESS_CONTROL_TURNS`, nudge the model to execute the task with tools and `continue`.
   - Add `TODO_LOOP_CONTINUE_NUDGE` and register in `NUDGE_ECHO_SIGNATURES`.
4. [x] Verify compilation and tests with TypeScript.
5. [x] Commit atomically and push tag if needed.

## Acceptance criteria
- Any model calling `manage_todo_list` with `todos`, `todoList`, `tasks`, or stringified JSON succeeds.
- No false "调用死循环" warning dialog interrupts normal agent execution.
- If a model calls `manage_todo_list` without todos changes, it is steered to work on the task instead of crashing out.
- Clean TypeScript compilation.
