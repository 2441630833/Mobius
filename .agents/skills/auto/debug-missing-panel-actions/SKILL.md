---
name: debug-missing-panel-actions
description: "Use when a panel or tree view shows an empty state or is missing action buttons (e.g., Commit button) despite underlying data being available"
auto-generated: true
generated-at: 2026-08-16T10:26:14.498Z
source-task: "got another issue, the git commit done button disappeared and even if the project workspace have the changes. it did not appear the button and the changed files at the right panel. help me analysis w…"
---
## When to use

A sidebar panel, tree view, or changes/history view:
- Shows a placeholder message ("X will appear here") even though data exists in the workspace
- Is missing expected action buttons (Commit, Refresh, etc.) in its toolbar or title area
- Appears stuck in a loading state

This commonly occurs in provider-driven architectures (e.g., VS Code's sessions/changes views) where multiple data sources contribute items and one is selected by default.

## Steps

1. **Locate the view and its view model.** Search for the empty-state placeholder string (grep the user-facing text) to find the view container, then trace to its view model / data provider.

2. **Identify all contributing items/changesets.** Find the factory function (e.g., `createChangesets()`) that builds the list of selectable items. Note each item's:
   - `isDefault` or equivalent default-selection flag
   - registered operations/actions (buttons are derived from these)
   - data source it reads from

3. **Check which item is default.** The most common root cause is that the default-selected item:
   - Has **no operations registered**, so no buttons render
   - Reads from a source that is **empty for the current session type** (e.g., local vs. cloud)
   while the item that *does* have the right operations and data is not default.

4. **Verify the data source is not filtering out expected items.** For git-based file lists:
   - `diff` against `HEAD` only returns **tracked, modified** files
   - **Untracked files** must be queried separately (e.g., `git status --porcelain` or a dedicated untracked query)
   - Merge tracked diff results with untracked file results before rendering

5. **Check for stuck loading flags.** If a flag like `isLoadingChanges` gates the file list, ensure it resolves to `false` as soon as data is available—not only after some slow or never-firing event.

6. **Apply the fix:**
   - Set the correct item as default based on session/workspace context (e.g., local sessions default to the uncommitted-changes item; cloud sessions default to branch changes)
   - Ensure the default item's operations include the expected button
   - Point the item's `changes`/data at the observable or provider that includes tracked **and** untracked files
   - Fix the loading-flag logic

7. **Rebuild and verify.** Run the project's compile step, check for error markers, then reload the window/extension host and confirm the panel shows files and action buttons.

## Pitfalls

- **Don't assume the first item in the list is the right default.** Order in the factory array may not match user intent for every session type.
- **An item with no `operations` array (or empty array) renders no buttons.** This is easy to overlook when the item looks otherwise correct.
- **Observables may already contain the right data** (e.g., `chat.changes` populated by a provider); reading from a stale or empty snapshot instead causes empty panels.
- **Untracked files are invisible to `diff HEAD`.** Always check whether your diff utility excludes them—this is a frequent source of "files missing" reports.
- **A loading flag that never flips** looks identical to an empty data source from the user's perspective; check both.
- After compiling a forked VS Code or extension, ensure you reload the window so the new build is actually loaded.

## Example

In a VS Code-based IDE, the Changes panel showed "Changed files and other session artifacts will appear here" with no Commit button, even though the workspace had modified and new files. Investigation found:
- `BranchChangesChangeset` was first and `isDefault = true` for all sessions, but it had **no operations** and read from `chat.changes` which was empty for local sessions.
- `UncommittedChangesChangeset` had the Commit operation and read from a git resolver, but `isDefault = false`.
- The git resolver used `diffBetweenWithStats2('HEAD')`, which omitted untracked files.

Fix: parameterized `isDefault` on the branch changeset (false for local sessions), set the uncommitted changeset as default for local sessions, merged untracked files into the result, and corrected the loading-flag early-return.
