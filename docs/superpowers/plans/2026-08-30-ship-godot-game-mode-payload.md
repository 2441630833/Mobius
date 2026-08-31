# Ship Godot Game mode payload in installed Mobius

## Root cause

Game mode calls `resolveGodotPaths()` which walks upward from the workspace folder and from `appRoot` looking for `scripts/godot-mcp-server.js`. The Mobius installer ships `resources/mobius-chip` but never stages Godot scripts or `game-dev/`, so installed IDE users always hit:

> Cannot locate Mobius Godot tooling (scripts/godot-mcp-server.js)

## Goal

- Installed Mobius resolves Godot tooling without opening the git checkout as workspace.
- `bootstrapGameModeGodotLivePreview` can run detect → init → editor + game preview.
- Future `npm run package` includes the payload automatically.

## Non-goals

- Shipping Godot engine binaries (still via `npm run godot:setup`).
- Committing `.godot/` import cache.

## Tasks

1. [x] Add `scripts/stage-godot.ps1` — copy scripts + `game-dev/` into client tree and `resources/mobius-godot/`.
2. [x] Wire staging into `scripts/package.ps1`.
3. [x] Teach `resolveGodotPaths` to probe `resources/mobius-godot` from `appRoot`.
4. [x] Add `scripts/patch-ide-godot.ps1` for live installs without full rebuild.
5. [x] Run patch on `%LOCALAPPDATA%\Programs\Mobius` and verify script exists.

## Acceptance criteria

- `%LOCALAPPDATA%\Programs\Mobius\scripts\godot-mcp-server.js` exists after patch/stage.
- `%LOCALAPPDATA%\Programs\Mobius\resources\mobius-godot\scripts\godot-mcp-server.js` exists.
- `resolveGodotPaths` finds payload when `appRoot` is `...\Mobius\resources\app` and workspace is unrelated.
- `npm run typecheck-client` clean for touched TS.
