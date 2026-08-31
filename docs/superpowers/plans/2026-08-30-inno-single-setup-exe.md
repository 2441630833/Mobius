# Single MobiusSetup.exe (no disk-spanning .bin)

## Root cause

`vscode/build/win32/code.iss` sets `DiskSpanning=yes`. Inno 6 still defaults
`DiskSliceSize` to ~2.1 GB, so even a 1.4 GB payload becomes
`MobiusSetup.exe` (stub) + `MobiusSetup-1.bin`.

Current user-setup is ~1.44 GB total, under Inno 6.4's ~4 GB single-exe cap
(spanning is only required above ~4.2 GB compressed).

## Goal

One `MobiusSetup.exe` with the compressed payload inside. No `.bin` slices.

## Non-goals

- Re-staging GLM-OCR / chip / the client tree
- Commit unless the user asks

## Tasks

1. [x] Set `DiskSpanning=no` in `code.iss` with a size-cap comment.
2. [x] Adjust `scripts/package.ps1` complete summary so it does not imply bins.
3. [x] Re-run `vscode-win32-x64-user-setup` if `VSCode-win32-x64` is still staged.

## Acceptance criteria

- Next Inno compile emits only `MobiusSetup.exe` (plus `product.json` in the
  setup dir). No `MobiusSetup-*.bin`.
- Payload stays under ~4 GB compressed; if it grows past that, spanning must
  be turned back on.
