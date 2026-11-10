"""Hot-patch an installed Mobius that lost its file/terminal tools in some chats.

Symptom this repairs
--------------------
Some Agent sessions report they have *no* terminal tool, no file editor, nothing
but `manage_todo_list`. The model is telling the truth: the workbench really did
hand it a crippled tool list.

Why it happens
--------------
Tool enablement is a persisted user/profile state:

  * `chat/selectedTools`  (PROFILE / MACHINE memento in state.vscdb) -> global map
  * per-session / per-mode snapshots stored next to the chat session JSON

`ChatSelectedTools.entriesMap()` reads `map.get(tool.id) !== false` for loose
tools but, for tools that live inside a *tool set*, it computes

    toolSetEnabled || currentMap.tools.get(tool.id) === true

So a single stored `false` on the tool set that wraps the file/terminal tools
turns off every tool inside it at once — while `manage_todo_list`, which is not
in that set, stays enabled. That is exactly the "only manage_todo_list" state.

Once such a `false` lands in the profile memento it is inherited by every chat
whose in-memory state has not been overridden, which is why the bug looks
random and only shows up in *some* sessions.

What this script does
---------------------
Rewrites every persisted enablement snapshot so nothing is explicitly disabled:

  1. `state.vscdb` -> key `chat/selectedTools`: `false` -> `true`
  2. `**/chatSessions/*.json`: `false` -> `true`, `disabledTools` / `disabledToolSets` -> `[]`

`true` is written rather than deleting the key on purpose: the request path
treats a *missing* id as "not enabled" in some code paths, so keeping an explicit
`true` is the safe repair. Nothing else in the files is touched.

A `false` entry is only ever produced by the tool picker, so re-enabling is
recoverable: just untick what you do not want again.

Source-level fix (already applied)
---------------------------------
`vscode/src/vs/workbench/contrib/chat/browser/widget/input/chatSelectedTools.ts`
now self-heals any session with fewer than `MIN_ENABLED_TOOLS` enabled entries.
This script only exists because the installed IDE runs a prebuilt bundle that
predates that fix.

Usage
-----
    python scripts/hotpatch-agent-missing-tools.py --dry-run   # report only
    python scripts/hotpatch-agent-missing-tools.py             # apply
    python scripts/hotpatch-agent-missing-tools.py --revert    # restore backups

Close Mobius first: the SQLite database is locked while the IDE is running.
Backups are written next to each file with a timestamp suffix.
"""
from __future__ import annotations

import glob
import json
import os
import shutil
import sqlite3
import sys
import time

STAMP = time.strftime("%Y%m%d-%H%M%S")
STORE_KEY = "chat/selectedTools"

DB_CANDIDATES = (
    os.path.expandvars(r"%APPDATA%\Mobius\User\globalStorage\state.vscdb"),
    os.path.expandvars(r"%APPDATA%\Mobius\User\globalStorage\state.vscdb"),
)

SESSION_GLOBS = (
    os.path.expandvars(r"%APPDATA%\Mobius\User\workspaceStorage\*\chatSessions\*.json"),
    os.path.expandvars(r"%APPDATA%\Mobius\User\globalStorage\chatSessions\*.json"),
)

MAP_KEYS = ("toolEntries", "toolSetEntries")
DICT_KEYS = ("selectedTools", "toolEnablement")
LIST_KEYS = ("disabledTools", "disabledToolSets")


class Stats:
    def __init__(self) -> None:
        self.sessions = 0
        self.tools = 0
        self.sets = 0


def _backup(path: str) -> str:
    dst = "%s.bak-missing-tools-%s" % (path, STAMP)
    shutil.copy2(path, dst)
    return dst


def _revive_pairs(entries):
    """`[[id, false], ...]` -> `[[id, true], ...]`, counting how many flipped."""
    flipped = 0
    out = []
    for entry in entries:
        if isinstance(entry, (list, tuple)) and len(entry) == 2 and entry[1] is False:
            out.append([entry[0], True])
            flipped += 1
        else:
            out.append(entry)
    return out, flipped


def _repair(node, stats: Stats) -> int:
    """Walk a decoded JSON value and re-enable everything. Returns change count."""
    changed = 0
    if isinstance(node, dict):
        for key in MAP_KEYS:
            if isinstance(node.get(key), list):
                node[key], flipped = _revive_pairs(node[key])
                changed += flipped
                if key == "toolEntries":
                    stats.tools += flipped
                else:
                    stats.sets += flipped
        for key in DICT_KEYS:
            value = node.get(key)
            if isinstance(value, dict):
                for tool_id, enabled in list(value.items()):
                    if enabled is False:
                        value[tool_id] = True
                        changed += 1
                        stats.tools += 1
        for key in LIST_KEYS:
            if isinstance(node.get(key), list) and node[key]:
                changed += len(node[key])
                stats.tools += len(node[key])
                node[key] = []
        for value in node.values():
            changed += _repair(value, stats)
    elif isinstance(node, list):
        for value in node:
            changed += _repair(value, stats)
    return changed


def patch_database(path: str, dry_run: bool, stats: Stats) -> int:
    if not os.path.exists(path):
        return 0
    if os.path.getsize(path) == 0:
        return 0
    try:
        con = sqlite3.connect("file:%s?mode=rw" % path.replace("\\", "/"), uri=True)
    except sqlite3.Error as exc:
        print("  cannot open (is Mobius still running?): %s" % exc)
        return 0
    try:
        row = con.execute("SELECT value FROM ItemTable WHERE key = ?", (STORE_KEY,)).fetchone()
        if not row:
            print("  no %r entry" % STORE_KEY)
            return 0
        raw = row[0]
        prefix = ""
        text = raw
        if isinstance(raw, bytes):
            text = raw.decode("utf-8", "replace")
        # Some memento values are stored with a leading NUL sentinel; keep it.
        stripped = text.lstrip("\x00")
        prefix = text[: len(text) - len(stripped)]
        try:
            data = json.loads(stripped)
        except ValueError:
            print("  value is not JSON, leaving untouched")
            return 0
        before = (stats.tools, stats.sets)
        changed = _repair(data, stats)
        if not changed:
            print("  nothing disabled, already healthy")
            return 0
        print("  %s: re-enabling %d entr(ies)" % (STORE_KEY, changed))
        if dry_run:
            stats.tools, stats.sets = before
            return changed
        _backup(path)
        payload = prefix + json.dumps(data, separators=(",", ":"))
        con.execute("UPDATE ItemTable SET value = ? WHERE key = ?", (payload, STORE_KEY))
        con.commit()
        return changed
    finally:
        con.close()


def patch_session_file(path: str, dry_run: bool, stats: Stats) -> int:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, ValueError):
        return 0
    before = (stats.tools, stats.sets)
    changed = _repair(data, stats)
    if not changed:
        return 0
    if dry_run:
        stats.tools, stats.sets = before
        return changed
    _backup(path)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(data, handle, separators=(",", ":"), ensure_ascii=False)
    return changed


def revert() -> int:
    restored = 0
    for pattern in ("%APPDATA%\\Mobius\\User\\**\\*.bak-missing-tools-*",):
        for path in glob.glob(os.path.expandvars(pattern), recursive=True):
            target = path.split(".bak-missing-tools-")[0]
            shutil.copy2(path, target)
            os.remove(path)
            restored += 1
            print("restored", target)
    print("reverted %d file(s)" % restored)
    return 0


def inspect() -> int:
    """Print every persisted tool-enablement field so the real culprit is visible."""
    for path in DB_CANDIDATES:
        if not os.path.exists(path):
            continue
        print("database:", path)
        try:
            con = sqlite3.connect("file:%s?mode=rw" % path.replace("\\", "/"), uri=True)
        except sqlite3.Error as exc:
            print("  cannot open:", exc)
            continue
        try:
            rows = con.execute(
                "SELECT key, length(value) FROM ItemTable "
                "WHERE key LIKE '%tool%' OR key LIKE '%chat%' ORDER BY key"
            ).fetchall()
            print("  %d matching key(s)" % len(rows))
            for key, size in rows:
                print("    %s  (%s bytes)" % (key, size))
            row = con.execute("SELECT value FROM ItemTable WHERE key = ?", (STORE_KEY,)).fetchone()
            if row:
                blob = row[0]
                text = blob.decode("utf-8", "replace") if isinstance(blob, bytes) else blob
                print("  %s = %s" % (STORE_KEY, text[:2000]))
        finally:
            con.close()

    for pattern in SESSION_GLOBS:
        for path in glob.glob(os.path.expandvars(pattern)):
            print("session:", path)
            try:
                with open(path, "r", encoding="utf-8") as handle:
                    data = json.load(handle)
            except (OSError, ValueError) as exc:
                print("  unreadable:", exc)
                continue
            found = []

            def walk(node, trail: str) -> None:
                if isinstance(node, dict):
                    for k, v in node.items():
                        if k in MAP_KEYS + DICT_KEYS + LIST_KEYS:
                            found.append(("%s/%s" % (trail, k), v))
                        walk(v, "%s/%s" % (trail, k))
                elif isinstance(node, list):
                    for i, v in enumerate(node):
                        walk(v, "%s[%d]" % (trail, i))

            walk(data, "")
            if not found:
                print("  no tool enablement fields")
            for where, value in found:
                print("  %s = %s" % (where, json.dumps(value)[:1200]))
    return 0


def main() -> int:
    args = set(sys.argv[1:])
    if "--revert" in args:
        return revert()

    if "--inspect" in args:
        return inspect()

    dry_run = "--dry-run" in args
    stats = Stats()
    print("Mobius tool-enablement hot patch%s" % (" (dry run)" if dry_run else ""))

    total = 0
    seen = set()
    for path in DB_CANDIDATES:
        if path in seen or not os.path.exists(path):
            continue
        seen.add(path)
        print("database: %s" % path)
        total += patch_database(path, dry_run, stats)

    for pattern in SESSION_GLOBS:
        for path in glob.glob(os.path.expandvars(pattern)):
            if path in seen:
                continue
            seen.add(path)
            changed = patch_session_file(path, dry_run, stats)
            if changed:
                stats.sessions += 1
                total += changed
                print("session: %s (%d entr(ies))" % (os.path.basename(path), changed))

    if not total:
        print("no disabled tool state found - nothing to repair")
    else:
        print(
            "%s %d entr(ies) across %d session file(s) (%d tool, %d set)"
            % ("would re-enable" if dry_run else "re-enabled",
               total, stats.sessions, stats.tools, stats.sets)
        )
        print("restart Mobius for the change to take effect")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())