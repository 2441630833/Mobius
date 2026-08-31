# Ship Godot engine binary with Game mode payload

## Root cause

After packaging `scripts/godot-mcp-server.js` + `game-dev/`, Game mode still fails
`godot_detect` because the installed tree has no `tools/godot/godot.exe`. The
repo already has Godot 4.4.1 under `tools/godot/`; staging never copied it.
A failed on-IDE download left only a truncated `.zip` under
`resources/mobius-godot/tools/godot/`.

## Goal

- Live install finds `godot.exe` via `MOBIUS_ROOT/tools/godot/` (install root
  and/or `resources/mobius-godot`).
- `stage-godot.ps1` / `patch-ide-godot.ps1` copy the engine when present.
- Future `npm run package` includes it when `tools/godot/godot.exe` exists.

## Non-goals

- Forcing a download during every package (optional; use existing binary).
- Shipping console-only builds as the primary exe.

## Tasks

1. [x] Extend `stage-godot.ps1` to robocopy `tools/godot` (require `godot.exe`, skip zips).
2. [x] Extend `patch-ide-godot.ps1` the same way; clean truncated zip residue.
3. [x] Patch live Mobius + staged client; verify `--detect` finds the binary.
4. [x] Note in package summary when Godot engine was staged.

## Acceptance criteria

- `%LOCALAPPDATA%\Programs\Mobius\tools\godot\godot.exe` exists.
- `%LOCALAPPDATA%\Programs\Mobius\resources\mobius-godot\tools\godot\godot.exe` exists.
- `node .../godot-mcp-server.js --detect` with `MOBIUS_ROOT` set to either root reports Godot found.
