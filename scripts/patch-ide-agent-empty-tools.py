"""Hot-patch the installed Mobius so a session never loses its terminal tools.

Symptom
-------
Some Agent chats report that they only have `manage_todo_list` — no
`run_in_terminal`, no file editor. The model is not lying: it really was handed a
crippled tool list.

Root cause
----------
`ChatSelectedTools.entriesMap()` builds the per-chat enablement map like this:

    if (!currentMap && currentMode.kind === ChatModeKind.Agent) {
        const modeTools = currentMode.customTools?.read(r);
        if (modeTools) {
            currentMap = ToolEnablementStates.fromMap(
                toolsService.toToolAndToolSetEnablementMap(modeTools, lm));
        }
    }

`toToolAndToolSetEnablementMap([])` returns **every registered tool mapped to
`false`** (see languageModelToolsService tests: "Expected 0 tools to be
enabled"). So any agent mode file that declares

    ---
    name: Plan
    tools: []
    ---

turns every tool off for any chat bound to that mode, apart from the few tools
the agent harness injects itself. That is why the bug looks per-session: only
chats whose mode resolves to such a file are affected, and the UI no longer
shows a mode picker to explain why.

What this patches
-----------------
1. `out/vs/workbench/workbench.desktop.main.js`
   `c = mode.customTools?.read(r); c && (… fromMap(…))`
   -> `c = mode.customTools?.read(r); c && c.length > 0 && (… fromMap(…))`
   i.e. an empty allowlist means "no restriction", not "disable everything".

2. `out/vs/workbench/contrib/continue/mobius/agents/*.agent.md`
   Drops a `tools: []` line from any bundled agent definition, so the shipped
   Plan agent does not re-poison sessions after a restart.

Source-level equivalents (already applied) live in
  vscode/src/vs/workbench/contrib/chat/browser/widget/input/chatSelectedTools.ts
  vscode/src/vs/workbench/contrib/continue/mobius/agents/Plan.agent.md
Once the IDE is repackaged from that source this script is redundant.

Usage
-----
    python scripts/patch-ide-agent-empty-tools.py --dry-run
    python scripts/patch-ide-agent-empty-tools.py
    python scripts/patch-ide-agent-empty-tools.py --revert

Close Mobius before applying (the bundle is memory-mapped while it runs).
"""
from __future__ import annotations

import glob
import os
import re
import shutil
import sys
import time

STAMP = time.strftime("%Y%m%d-%H%M%S")

APP_ROOT = os.path.expandvars(r"%LOCALAPPDATA%\Programs\Mobius\resources\app")
BUNDLE = os.path.join(APP_ROOT, "out", "vs", "workbench", "workbench.desktop.main.js")
AGENTS_GLOB = os.path.join(
    APP_ROOT, "out", "vs", "workbench", "contrib", "continue", "mobius", "agents", "*.agent.md"
)
MARKER = b"customTools?.read("

# `let c=n.customTools?.read(e);c&&(` -> insert a non-empty guard.
GUARD = re.compile(rb"let (\w+)=(\w)\.customTools\?\.read\((\w+)\);\1&&\(")


def _backup(path: str) -> str:
    dst = "%s.bak-emptytools-%s" % (path, STAMP)
    shutil.copy2(path, dst)
    return dst


def patch_bundle(dry_run: bool) -> int:
    if not os.path.exists(BUNDLE):
        print("bundle not found:", BUNDLE)
        return 1

    with open(BUNDLE, "rb") as handle:
        data = handle.read()

    if b".customTools?.read(" in data and GUARD.search(data) is None:
        if re.search(rb"customTools\?\.read\(\w+\);\w+&&\w+\.length>0&&\(", data):
            print("bundle: already patched")
            return 0

    matches = list(GUARD.finditer(data))
    if len(matches) != 1:
        # Fall back to reporting any already-guarded form.
        if re.search(rb"customTools\?\.read\(\w+\);\w+&&\w+\.length>0&&\(", data):
            print("bundle: already patched")
            return 0
        print("bundle: anchor matched %d times (expected 1) - layout changed, aborting" % len(matches))
        return 2

    before = len(data)
    patched = GUARD.sub(
        lambda m: b"let %s=%s.customTools?.read(%s);%s&&%s.length>0&&("
        % (m.group(1), m.group(2), m.group(3), m.group(1), m.group(1)),
        data,
        count=1,
    )
    print("bundle: guard inserted (+%d bytes)" % (len(patched) - before))
    if dry_run:
        return 0
    try:
        _backup(BUNDLE)
        with open(BUNDLE, "wb") as handle:
            handle.write(patched)
    except OSError as exc:
        print("bundle: cannot write (is Mobius still running?):", exc)
        return 3
    return 0


def patch_agents(dry_run: bool) -> int:
    touched = 0
    for path in glob.glob(AGENTS_GLOB):
        with open(path, "r", encoding="utf-8") as handle:
            text = handle.read()
        new_text, count = re.subn(r"(?m)^tools:\s*\[\]\s*\r?\n", "", text)
        if not count:
            continue
        print("agent: %s drops 'tools: []'" % os.path.basename(path))
        if dry_run:
            touched += 1
            continue
        try:
            _backup(path)
            with open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(new_text)
            touched += 1
        except OSError as exc:
            print("agent: cannot write %s: %s" % (path, exc))
    return touched


def revert() -> int:
    restored = 0
    for pattern in (
        os.path.join(APP_ROOT, "**", "*.bak-emptytools-*"),
    ):
        for path in glob.glob(pattern, recursive=True):
            target = path.split(".bak-emptytools-")[0]
            shutil.copy2(path, target)
            os.remove(path)
            restored += 1
            print("restored", target)
    print("reverted %d file(s)" % restored)
    return 0


def main() -> int:
    args = set(sys.argv[1:])
    if "--revert" in args:
        return revert()

    dry_run = "--dry-run" in args
    print("Mobius empty-tool-allowlist hot patch%s" % (" (dry run)" if dry_run else ""))

    rc = patch_bundle(dry_run)
    agents = patch_agents(dry_run)
    print("agents patched: %d" % agents)
    if rc == 0:
        print("restart Mobius for the change to take effect")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())