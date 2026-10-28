# Agent tool response recovery

## Root cause
The OpenAI-compatible streaming parser ignores complete message content, and the final-answer fallback displays arbitrarily cut raw tool output as a summary. Grep output has bounded context.

## Goal
Preserve provider final messages, retry empty answers with useful bounded evidence, and report failure honestly without presenting truncated code as a generated answer.

## Non-goals
Remove context limits or change existing unrelated submodule work.

## Tasks
1. [x] Handle complete streamed message content without duplicating streamed deltas and test it.
2. [x] Improve final-answer recovery and failure reporting; keep search truncation explicit.
3. [x] Run focused tests and workspace compile, commit intended changes.

## Acceptance criteria
Complete-message and delta providers yield one answer; empty responses receive a recovery attempt and never masquerade raw excerpts as a summary; verification outcomes are recorded.

## Verification
Focused stream tests passed. The root compile entry failed because Windows PowerShell could not find Get-FileHash. Direct VS Code compile-client completed successfully with zero source and type-check errors. Existing unrelated submodule changes are preserved.
