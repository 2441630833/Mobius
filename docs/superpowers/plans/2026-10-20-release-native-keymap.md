# Release native-keymap compatibility

## Root cause
v1.0.10 CI run 39356689136 fails when rebuilding native-keymap 3.3.9 against Electron 42.3.0 headers: node.h pulls in V8 types missing from the supplied headers. keymapping.cc uses only Node-API, and its own keymapping.h already includes node_api.h. The unnecessary node.h dependency triggers the failure.

## Goal
Remove that unnecessary V8 header dependency during native dependency preparation and complete v1.0.10 packaging and Release publication.

## Non-goals
Do not suppress native build failures or change the dependency's runtime functionality. Preserve unrelated submodule changes.

## Tasks
1. [x] Add an idempotent Node-API header patch and invoke before Linux/macOS/Windows native rebuild.
2. [x] Verify syntax, idempotence, and preservation of unrelated source; commit changes.
3. [x] Rebuild the unpublished v1.0.10 tag from the corrected source, verify all platform build results and release assets.

## Acceptance criteria
Native keymap compilation succeeds in Linux CI. Actual platform installers are uploaded to a non-draft latest Release. The tag and build source commit match.

## Verification
Node --check for helper, bash -n for shell scripts, PowerShell parser for PS1, isolated patch fixtures (first patch, repeated patch, changed header fail-closed). Real native compilation is validated by CI because this host is Windows. No get_errors/manage_todo_list tools available. Preexisting hermes-agent and vendor submodule changes are excluded.
