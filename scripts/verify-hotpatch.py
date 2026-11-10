"""Verify that the Mobius hot patches are live in the *installed* app.

Read-only. Safe to run while Mobius is open (the SQLite database is opened
with ``mode=ro`` and only SELECTs are issued).

Checks
------
1. terminal-steering patch   -> ``/*mobius:steering-off*/`` marker present
2. empty-tool-allowlist patch-> ``customTools?.read(x);y&&y.length>0&&(`` guard
3. shipped agent definitions -> no ``tools: []`` left in bundle agents
4. persisted enablement      -> no ``false`` entries in ``chat/selectedTools``
5. per-session snapshots     -> no ``disabledTools`` / ``disabledToolSets``

Usage::

    python scripts/verify-hotpatch.py
"""
from __future__ import annotations

import glob
import json
import os
import re
import sqlite3
import sys

APP_ROOT = os.path.expandvars(r"%LOCALAPPDATA%\Programs\Mobius\resources\app")
BUNDLES = [
    os.path.join(APP_ROOT, "out", "vs", "workbench", "workbench.desktop.main.js"),
    os.path.join(APP_ROOT, "out", "vs", "sessions", "sessions.desktop.main.js"),
]
AGENTS_GLOB = os.path.join(
    APP_ROOT, "out", "vs", "workbench", "contrib", "continue", "mobius", "agents", "*.agent.md"
)
DB = os.path.expandvars(r"%APPDATA%\Mobius\User\globalStorage\state.vscdb")
STORE_KEY = "chat/selectedTools"
SESSION_GLOBS = (
    os.path.expandvars(r"%APPDATA%\Mobius\User\workspaceStorage\*\chatSessions\*.json"),
    os.path.expandvars(r"%APPDATA%\Mobius\User\globalStorage\chatSessions\*.json"),
)

STEERING_MARKER = "/*mobius:steering-off*/"
GUARD_RE = re.compile(r"customTools\?\.read\(\w+\);\w+&&\w+\.length>0&&\(")

results: list[tuple[str, str, str]] = []


def add(status: str, item: str, detail: str) -> None:
    results.append((status, item, detail))


def check_bundles() -> None:
    for path in BUNDLES:
        name = os.path.join(os.path.basename(os.path.dirname(path)), os.path.basename(path))
        if not os.path.exists(path):
            add("SKIP", "steering patch: " + name, "bundle not present")
            continue
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            text = handle.read()
        add(
            "OK" if STEERING_MARKER in text else "FAIL",
            "steering patch: " + name,
            "%d marker(s)" % text.count(STEERING_MARKER),
        )
        if "workbench.desktop.main.js" in path:
            guarded = len(GUARD_RE.findall(text))
            raw = len(re.findall(r"customTools\?\.read\(\w+\);\w+&&\(", text))
            add(
                "OK" if guarded >= 1 else "FAIL",
                "empty-tool-allowlist guard",
                "guarded=%d raw(unguarded)=%d" % (guarded, raw),
            )


def check_agents() -> None:
    files = glob.glob(AGENTS_GLOB)
    if not files:
        add("SKIP", "bundle agents:", "no *.agent.md in installed app")
        return
    bad = []
    for path in files:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            if re.search(r"(?m)^tools:\s*\[\]\s*$", handle.read()):
                bad.append(os.path.basename(path))
    add(
        "OK" if not bad else "FAIL",
        "bundle agents without 'tools: []'",
        "%d file(s)%s" % (len(files), "" if not bad else "; still poisoned: " + ", ".join(bad)),
    )


def check_store() -> None:
    if not os.path.exists(DB):
        add("SKIP", "chat/selectedTools", "database not found")
        return
    try:
        con = sqlite3.connect("file:%s?mode=ro" % DB.replace("\\", "/"), uri=True)
    except sqlite3.Error as exc:
        add("SKIP", "chat/selectedTools", "cannot open read-only: %s" % exc)
        return
    try:
        row = con.execute("SELECT value FROM ItemTable WHERE key = ?", (STORE_KEY,)).fetchone()
    except sqlite3.Error as exc:
        add("SKIP", "chat/selectedTools", "query failed: %s" % exc)
        return
    finally:
        con.close()

    if not row:
        add("OK", "chat/selectedTools", "no stored map (nothing disabled)")
        return
    raw = row[0]
    text = raw.decode("utf-8", "replace") if isinstance(raw, bytes) else raw
    try:
        data = json.loads(text.lstrip("\x00"))
    except ValueError:
        add("SKIP", "chat/selectedTools", "value is not JSON")
        return

    disabled = 0

    def walk(node) -> None:
        nonlocal disabled
        if isinstance(node, dict):
            for key, value in node.items():
                if isinstance(value, list) and key in ("toolEntries", "toolSetEntries"):
                    disabled += sum(
                        1
                        for entry in value
                        if isinstance(entry, list) and len(entry) == 2 and entry[1] is False
                    )
                elif isinstance(value, dict) and key in ("selectedTools", "toolEnablement"):
                    disabled += sum(1 for v in value.values() if v is False)
                walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    walk(data)
    add(
        "OK" if disabled == 0 else "FAIL",
        "chat/selectedTools",
        "%d explicitly disabled entr(ies)" % disabled,
    )


def check_sessions() -> None:
    files = sorted({p for pattern in SESSION_GLOBS for p in glob.glob(os.path.expandvars(pattern))})
    if not files:
        add("SKIP", "chatSessions snapshots", "none on disk")
        return
    offenders = []
    for path in files:
        try:
            with open(path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            continue
        found = []

        def walk(node) -> None:
            if isinstance(node, dict):
                for key, value in node.items():
                    if key in ("disabledTools", "disabledToolSets") and value:
                        found.append("%s(%d)" % (key, len(value)))
                    if isinstance(value, list) and key in ("toolEntries", "toolSetEntries"):
                        n = sum(
                            1
                            for e in value
                            if isinstance(e, list) and len(e) == 2 and e[1] is False
                        )
                        if n:
                            found.append("%s(%d false)" % (key, n))
                    walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)

        walk(data)
        if found:
            offenders.append("%s: %s" % (os.path.basename(path), ", ".join(found)))
    add(
        "OK" if not offenders else "FAIL",
        "chatSessions snapshots",
        "%d file(s)%s" % (len(files), "" if not offenders else "; " + "; ".join(offenders[:5])),
    )


def main() -> int:
    print("Mobius hot-patch verification")
    print("app root:", APP_ROOT)
    print("")
    check_bundles()
    check_agents()
    check_store()
    check_sessions()

    width = max(len(item) for _, item, _ in results)
    for status, item, detail in results:
        print("  [%-4s] %-*s  %s" % (status, width, item, detail))

    failed = sum(1 for status, _, _ in results if status == "FAIL")
    print("")
    print("%d check(s), %d failure(s)" % (len(results), failed))
    if failed:
        print("FAILED: at least one patch is not live in the installed app.")
        print("Remedy: fully quit Mobius, re-run the failing patch script, start Mobius again.")
    else:
        print("All checks passed - the patches are live in the installed app.")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())