# Fix Grep Search failed (invalid regex / unescaped literals)

## Root cause

Continue's `grep_search` always passes the query to ripgrep as a regex (`-e`).
`prepareQueryForRipgrep` was supposed to escape literal-looking / invalid patterns
(`looksLikeLiteralSearch` + `escapeLiteralForRegex` already exist) but never
called them. Queries like `so{` (unclosed quantifier) make rg exit code 2.

Session evidence (`~/.continue/sessions/cd439…`): 203× `Process exited with code 2`
with `Original query: so{`. Tip text already claimed "automatically escaped" but
that was never implemented.

`rg.exe` itself is present in the Continue extension and Mobius install — this is
not the older missing-binary issue.

## Goal

- Escape invalid / literal-looking queries before ripgrep so Grep Search succeeds.
- On exit code 2, retry once with a fully escaped literal query.
- Keep intentional regex alternation (`foo|bar`) working.

## Non-goals

- Re-shipping Copilot / getRipgrep IDE shim (already present).
- Committing unrelated dirty worktree files.
- Full `npm run compile` of VS Code (Continue unit tests + local rg checks suffice).

## Tasks

1. [x] Wire `prepareQueryForRipgrep` to escape when RegExp fails to compile, or when `looksLikeLiteralSearch` and the query has no `|` alternation.
2. [x] In `grepSearchImpl`, on exit code 2, retry once with `escapeLiteralForRegex(rawQuery)`.
3. [x] Update `regexValidator.vitest.ts` expectations; add `so{` / alternation cases.
4. [x] Run vitest for regexValidator (45/45 passed); esbuild Continue; copy `extension.js` into Mobius + VSCode-win32-x64.

## Acceptance criteria

- `prepareQueryForRipgrep("so{").query === "so\\{"`
- `prepareQueryForRipgrep("sofil|solaser").query` unchanged (regex OR)
- `prepareQueryForRipgrep("console.log()").query` escaped
- Vitest passes
- Local rg with escaped query returns matches (exit 0)
