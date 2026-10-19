# Cross-platform tool calling

## Root cause
Read-file accepts only a subset of provider argument aliases and resolves file
URIs as workspace-relative paths. Relative paths without a cwd can fall through
to process/application paths. SSE chunks are decoded independently, corrupting
split UTF-8 characters. Research requires a selected default model even when the
requested chat model exists, and strictly parses entire prose-wrapped JSON.
Screenshots prove invalid arguments and directory-as-file requests; they do not
prove every ARM tool is unavailable.

## Goal
Normalize file arguments and URI resolution consistently across Linux ARM/x64,
macOS and Windows. Preserve UTF-8 streams. Make research use the configured
requested model without requiring a separate default, and accept JSON wrapped
in prose while retaining schema validation. Add cross-platform regression checks.

## Non-goals
Do not fabricate paths, hide real tool errors, bypass permissions or promise
external services always succeed. Preserve initial unrelated submodules, xterm
changes, tmp-repro files and 2026-10-15-agent-terminal-cursor.md.

## Tasks
1. [ ] Normalize tool paths/arguments and protect local file reads.
2. [ ] Repair research startup and structured-response parsing; preserve SSE UTF-8.
3. [ ] Run typechecks and targeted regressions, add OS matrix checks, commit/push.

## Acceptance criteria
Valid POSIX/macOS/Windows/remote URI paths survive normalization. Missing args
cannot resolve to the application directory. Directory reads provide corrective
feedback. Research supports a requested model with no default selection and
prose-wrapped valid JSON. Cancellation and invalid plans still fail correctly.

## Verification
get_errors/manage_todo_list unavailable; use typecheck-client, Continue typecheck
where available, targeted tests and this checklist. Actual OS results must be
distinguished from simulated path coverage and pending CI runs.
