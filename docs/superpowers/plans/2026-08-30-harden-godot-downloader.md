# Harden Godot downloader (avoid truncated Invoke-WebRequest)

## Root cause

`scripts/setup-godot.ps1 -Install` used `Invoke-WebRequest` alone. On this machine
it wrote a ~3.6 MB truncated zip; Expand-Archive / install then failed or left
Game mode without a working engine. A reliable re-download produced a full
`godot.exe` (~156 MB, 4.4.1.stable.official).

## Goal

- Prefer `curl.exe -L --fail --retry` (same pattern as `setup-mingw.ps1`).
- Reject undersized downloads before extract.
- Require a minimum `godot.exe` size after extract.
- Sync the fixed script into the live Mobius install.

## Non-goals

- Changing Godot version pin.
- Re-downloading when a valid `godot.exe` already exists.

## Tasks

1. [x] Rewrite download path in `setup-godot.ps1`.
2. [x] Copy fixed script into install + `resources/mobius-godot`.
3. [x] Syntax-check the script.

## Acceptance criteria

- Script uses curl first; IWR only as fallback.
- Zip under ~20 MB is deleted and treated as failure.
- `godot.exe` under ~40 MB is rejected.
