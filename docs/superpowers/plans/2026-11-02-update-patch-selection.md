# Windows update patch selection

## Root cause
The installer falls back to any patch asset when no source version matches,
downloading a known incompatible patch before falling back to the installer.

## Goal
Select only a patch whose source tag, destination tag and architecture match.

## Non-goals
Patch chaining, release publishing and changes to installed applications.
Preserve existing unrelated changes in hermes-agent, vendor/fastmcp,
vendor/litex, vendor/litex-boards, vendor/mcp-python-sdk and vendor/openFPGALoader.

## Tasks
1. [x] Replace permissive selection in scripts/install-win.ps1 with exact matching.
2. [x] Verify PowerShell syntax and regression scenarios using extracted selection code.
3. [x] Review and commit only the installer and this plan.

## Acceptance criteria
An installed v1.0.19 must not select a v1.0.20-to-v1.0.21 patch.
An exact source/destination/architecture match must still be selected.
Unknown tags, wrong destinations, wrong architectures and generic filenames
must not select a patch. Preserve manifest validation before patch application.
Use PowerShell parser and Get-Command -Syntax for this standalone script;
get_errors and manage_todo_list are unavailable in this session.

## Verification results
PowerShell parser and Get-Command -Syntax passed. Seven regression cases
passed using the actual selection AST: mismatched base, exact match, wrong
destination, wrong architecture, unknown base, generic filename and tag prefix
collision. Manifest validation remains unchanged.
The default npm run compile failed because Windows PowerShell could not resolve
Get-FileHash. Retrying the same scripts/compile-vscode.ps1 entrypoint with
pwsh -NoProfile -File completed successfully (exit 0), including client and
built-in extensions with zero errors. Full verification took approximately
six minutes. git diff --check passed. No live download or installation was run.
