# Bound Continue terminal waits

## Root cause
Screenshot shows parallel research fallback, followed by terminal waiting.
Continue's terminal bridge omits the native tool timeout. Native sync defaults to
unlimited waiting, and sync shell detection disables heuristic fallbacks. Missing
shell completion events can therefore strand the agent. Architecture-specific
failure is not established without logs from the Ubuntu ARM machine.

## Goal
Bound native terminal waiting, preserving running processes and terminal IDs.
Prevent fallback from rerunning a cancelled command.
Ensure Linux builds rebuild node-pty for their Electron ABI and architecture,
and reject packages whose actual runtime cannot exchange input/output with a shell.

## Non-goals
Do not change PPT generation or claim a Linux ARM runtime reproduction. Preserve
initial hermes-agent/vendor revisions, vscode terminal xterm changes and tmp-repro
files, and the untracked 2026-10-15-agent-terminal-cursor.md plan.

## Tasks
1. [x] Add bounded native waits and cancellation guards with regression tests.
   Forward waitForCompletion to the Continue fallback as well.
2. [x] Rebuild node-pty after dependency installation, including cached builds.
   Run scripts/verify-linux-terminal.cjs with the packaged Electron executable
   before packaging; require target architecture, real shell I/O and exit in 15s.
3. [x] Typecheck client, run targeted tests and commit submodule plus parent.

## Acceptance criteria
Sync/async calls pass finite native timeouts; native timeout output is preserved;
cancellation never starts fallback; ordinary registered-tool failures retain fallback.
Packaging must fail if node-pty is missing, has the wrong architecture/ABI, cannot
launch /bin/sh, or fails to return shell output and exit successfully.

## Validation
get_errors/manage_todo_list unavailable. Use typecheck-client per vscode/AGENTS.md
and the native unit test runner. Do not run real install or shell commands in tests.

Results: typecheck-client passed; native Node unit runner passed all five new
behavioral tests plus its unexpected-errors check (six passing). Bash syntax
checks passed for both modified build scripts; Node syntax check passed for the
package smoke test. Linux native smoke test cannot run on this Windows x64 host
(no installed WSL distribution); it runs on the native ubuntu-24.04-arm CI runner
through package-linux.sh. Do not claim an ARM package has passed until CI does.

Commit messages: fix(terminal): bound Continue waits and preserve cancellation;
fix(linux): rebuild and verify packaged terminal native dependency.
