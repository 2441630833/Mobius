---
name: debug-missing-action-button-widget
description: "Use when an action/toolbar button is correctly declared in a model or operation list but does not render because the UI selects a different widget that ignores that source."
auto-generated: true
generated-at: 2026-08-16T10:52:05.873Z
source-task: "it works, correct logic, should only show the 本地会话默认选中 Uncommitted Changes, 也不让用户选择Uncommitted Changes or Branch Changes , this is corret , 但是现在问题是\r\n当工作区有未提交更改时，右侧 Changes 面板会直接显示文件列表但是不显示**Commit Ch…"
---
## When to use

Use this pattern when:
- A button/action is correctly declared in an operations/action model.
- The expected UI state exists, but the button is missing.
- The view has more than one possible toolbar/widget implementation.
- The widget-selection condition is based on context such as session type, mode, permission, or view kind.

## Steps

1. Locate the rendering code for the panel/toolbar that should contain the button.
2. Identify every widget/button-bar variant that can be selected.
3. Trace the selection condition and determine which variant is chosen for the failing state.
4. Compare how each variant obtains actions:
   - Some widgets read declarative operations/actions from the model.
   - Others only read contributions from a menu/registry and ignore the model.
5. Inspect the actual runtime data for the failing context:
   - Are operations present?
   - Do they have the expected scope?
   - Is the current context incorrectly excluded by a narrow condition?
6. Change the widget-selection condition to choose the action-aware widget whenever required actions are present, not only for a special mode/session type.
7. Re-run type checking/compile and validate the button appears in the previously failing state.

## Pitfalls

- Do not assume that declaring an operation is enough; verify that the selected widget actually reads that list.
- Avoid hardcoding selection to one session/mode; check for action capability or operation scope instead.
- Watch for operation scoping: an operation may exist but be filtered out because it is item-scoped, resource-scoped, or changeset-scoped.
- Menu/registry-based widgets may need separate menu contributions if they are intentionally model-agnostic.
- After changing selection logic, confirm both variants still work for their intended contexts.

## Example

A changes panel declared a commit operation on its uncommitted-changes changeset. The file list rendered correctly, but the commit button was absent for local sessions. Investigation showed two toolbar widgets: one operations-aware widget used only for a special session type, and another widget that read only toolbar menu contributions and ignored changeset operations. The fix was to select the operations-aware widget whenever the current changeset contained changeset-scoped operations, allowing the same button to render for local sessions as well.
