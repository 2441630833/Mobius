---
name: disable-vscode-extension-activation
description: "Use when a bundled or built-in VS Code extension must no longer load, activate, or be force-enabled by default."
auto-generated: true
generated-at: 2026-08-16T10:11:43.081Z
source-task: "continue"
---
## When to use

Use this pattern when removing default activation of a bundled VS Code extension from a fork or distribution, especially when the extension is still present in the build but should be disabled or ignored unless explicitly enabled.

## Steps

1. Identify the exact extension ID, including publisher, such as `publisher.extension-name`.
2. Search the product/build configuration for allowlists or exemption lists that force the extension to load in session, remote, or startup windows. Remove the ID from those lists.
3. Search the workbench contribution code for global extension enablement or disablement lists. If the goal is to actively disable the extension by default, add its ID to the appropriate disabled-extension set.
4. Search for code that eagerly activates or warms up the extension:
   - direct extension activation calls
   - commands that mount or enable the extension
   - readiness promises, timeouts, or tool-harvesting code
   - constants containing the extension ID or related command IDs
5. Remove the startup call path first, then delete only the supporting functions, constants, and imports that become unused. Keep utilities still referenced by other code.
6. Search for stale comments or documentation claiming the extension is required, and update them to match the new behavior.
7. Run type/error checking on all edited files and search again for the extension ID to catch remaining references.

## Pitfalls

- Removing an ID from an allowlist is not the same as disabling the extension. Verify whether a separate disablement list is required.
- If code depends on commands or language-model tools contributed by the extension, disabling it may break those integrations; replace them with built-in alternatives or remove the dependent code.
- Do not remove shared helpers or imports if they are still used by other wait loops, actions, or services.
- Extension activation can be triggered indirectly through welcome content, commands, proposed-api exemptions, or session restoration, so search broadly rather than only in one contribution file.
- A startup activation error toast may persist until the extension is disabled instead of merely failing to activate.

## Example

To stop a bundled chat extension from activating by default:

1. Remove its ID from the product configuration's session-window allowed-extensions list.
2. Add the ID to the workbench's disabled built-in extension set.
3. Delete the background warmup call and the helper functions that ensured the extension was enabled or waited for its tools.
4. Remove unused service imports and update any comments that said the extension was needed for agent tools.
5. Run diagnostics and grep for the extension ID to confirm no force-activation path remains.
