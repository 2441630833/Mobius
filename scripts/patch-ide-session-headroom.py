"""Hot-patch the installed Mobius bundle: headroom-style compression of persisted chat sessions.

Why this exists
---------------
Chat sessions are persisted as an append-only mutation log
(%APPDATA%\\Mobius\\User\\workspaceStorage\\<ws>\\chatSessions\\<id>.jsonl, class
ObjectMutationLog / `H7t` in the bundle). Two properties made it balloon to ~20 MB:

1. Every response part is stored verbatim - full terminal output, file reads, diffs
   and thinking text from every tool call, forever. Nothing bounds a single value.
2. The log is compacted only after 1024 entries, never by size, so a long session
   keeps appending multi-MB `set` entries; on open the whole file is JSON.parsed and
   replayed on the renderer main thread -> startup freeze.

The LLM never sees most of that again (the agent prunes old turns to fit the
context window), so the UI pays the whole cost for nothing.

What it patches (4 anchor-verified edits, mirrored from the headroom submodule)
------------------------------------------------------------------------------
1. Injects `__mobiusHR` (scripts/headroom-persist.js): a JS port of headroom's
   LogCompressor (head/tail, errors +-3 lines context, first/last errors, deduped
   warnings, summary lines, stack frames, 100-line budget) and DenseLineElider,
   with a 16 KB hard cap per string. Strings <= 4 KB are never touched.
2. Wraps the response-part extractor of the session serializer so tool invocations,
   thinking, progress tasks and elicitations are compressed in the PERSISTED COPY
   only. Markdown answers, text edits, URIs and image data are left alone, and the
   live in-memory chat (what the model and UI use this session) is never mutated.
3. Adds a size trigger to log compaction: once a log has appended > 4 MB since its
   last snapshot, the next write is a compact `replace` snapshot.
4. Any existing log > 2 MB is rewritten as a compact snapshot on its first save after
   load, so old bloated sessions shrink themselves.

Usage
-----
    python scripts/patch-ide-session-headroom.py            # apply (skips if already applied)
    python scripts/patch-ide-session-headroom.py --check    # report status only
    python scripts/patch-ide-session-headroom.py --revert   # restore the backup taken before patching

Close Mobius first (or restart it afterwards). A source port belongs in
vscode/src/vs/workbench/contrib/chat/common/model/{objectMutationLog,chatSessionStore}.ts;
once the IDE is repackaged from that source, this script is no longer needed.
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.expandvars(
    r"%LOCALAPPDATA%\Programs\Mobius\resources\app\out\vs\workbench\workbench.desktop.main.js"
)
if len(sys.argv) > 1 and sys.argv[-1].endswith(".js") and os.path.exists(sys.argv[-1]):
    P = sys.argv[-1]  # explicit bundle path (testing)
BAK = P + ".bak-headroom-20261112"
MARK = b"__mobiusHR"


def payload() -> bytes:
    src = open(os.path.join(HERE, "headroom-persist.js"), encoding="utf-8").read()
    src = re.sub(r"(?m)^\s*//.*$", "", src)                      # drop whole-line comments
    src = re.sub(r"(?m)^if\(typeof module.*$", "", src)           # drop node export
    src = "\n".join(l for l in src.splitlines() if l.strip())
    return src.encode("utf-8")


EDITS = (
    (b"};var sVn=s=>{",
     None,  # filled in main(): "};" + payload + ";var sVn=s=>{"
     "inject-compressor"),
    (b'aVn=Ml(s=>s.kind==="markdownContent"?s.content:sVn(s),',
     b'aVn=Ml(s=>s.kind==="markdownContent"?s.content:__mobiusHR(sVn(s)),',
     "wrap-part-extractor"),
    (b"if(!this._previous||this._entryCount>this._compactAfterEntries){this._hasPendingWrite=!0,this._pendingPrevious=e,this._pendingEntryCount=1;",
     b"if(!this._previous||this._entryCount>this._compactAfterEntries||(this._zzBytes||0)>4194304){this._zzBytes=0,this._hasPendingWrite=!0,this._pendingPrevious=e,this._pendingEntryCount=1;",
     "size-compaction"),
    (b'for(let r of t)n+=TGi(r)+`\n`;return{op:"append",data:qe.fromString(n)}}',
     b'for(let r of t)n+=TGi(r)+`\n`;this._zzBytes=(this._zzBytes||0)+n.length;return{op:"append",data:qe.fromString(n)}}',
     "count-appended-bytes"),
    (b"return this._previous=e,this._entryCount=t,this._clearPending(),e}write(i){",
     b"return this._previous=e,this._entryCount=i.byteLength>2097152?1/0:t,this._zzBytes=0,this._clearPending(),e}write(i){",
     "compact-big-logs-on-load"),
)


def main() -> int:
    args = set(a for a in sys.argv[1:] if not a.endswith(".js"))
    if not os.path.exists(P):
        print("bundle not found:", P)
        return 1
    data = open(P, "rb").read()
    applied = MARK in data

    if "--check" in args:
        print("patched" if applied else "not patched", "-", P)
        print("backup:", BAK if os.path.exists(BAK) else "none")
        return 0 if applied else 1

    if "--revert" in args:
        if not os.path.exists(BAK):
            print("no backup to restore:", BAK)
            return 3
        shutil.copy2(BAK, P)
        print("restored", P, "from", BAK)
        return 0

    if applied:
        print("already patched (use --revert first to re-apply)")
        return 0

    if not os.path.exists(BAK):
        shutil.copy2(P, BAK)
        print("backup written:", BAK, os.path.getsize(BAK))

    before = len(data)
    for anchor, new, label in EDITS:
        if new is None:
            new = b"};" + payload() + b";var sVn=s=>{"
        count = data.count(anchor)
        if count != 1:
            print("anchor %s matched %d times (expected 1) - bundle layout changed, aborting" % (label, count))
            return 2
        data = data.replace(anchor, new)

    open(P, "wb").write(data)
    print("patched %d -> %d bytes (+%d)" % (before, len(data), len(data) - before))
    print("restart Mobius to load the patch")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
