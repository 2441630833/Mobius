# Agent subtitle missing in session mode selector (follow-up)

## Root cause

Game/Chip already get `getMobiusModePickerDetailLine`. Agent is the only row with a
keybinding (`Ctrl+Shift+I` in `.description`). The list row uses `overflow: hidden`
and wrap depended on `:has(.detail:not([style*="display: none"]))`, which does not
reliably wrap the subtitle onto a second line next to the keybinding.

## Goal

Agent shows a second-line subtitle in both the chat and Agents-window mode pickers,
same as Game and Chip.

## Non-goals

- Changing Game/Chip copy
- Changing the builtin Agent hover string used outside the picker

## Tasks

1. [x] Toggle `has-detail` on action-list rows when `item.detail` is set.
2. [x] CSS wrap on `.has-detail`; hide unused KeybindingLabel; overflow visible.
3. [x] Pass `detailItemHeight` from the sessions mode picker.
4. [x] Disable Mobius `showItemKeybindings` so Agent layout matches Game/Chip.

## Acceptance criteria

- Picker list: Agent / Game / Chip each have a visible subtitle.
- Agent subtitle: `General coding · no auto Godot`.
