"""Hot-patch the installed Mobius bundle with the stuck-tool-loop circuit breaker.

Why this exists
---------------
The installed IDE runs the *bundled* workbench
(%LOCALAPPDATA%\\Programs\\Mobius\\resources\\app\\out\\vs\\workbench\\workbench.desktop.main.js),
not the per-module `vscode/out/**` dev build. A source fix therefore only reaches a
running install after `npm run package` (full client rebuild + Inno Setup).

This script mirrors the source change in
  vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts
into that bundle so an existing install stops looping without a full rebuild.

Once the IDE has been repackaged from the fixed source, this script is no longer
needed - it is a stop-gap, kept for auditability and for users on an older install.

What it patches (3 surgical, anchor-verified edits inside the agent turn loop)
-----------------------------------------------------------------------------
1. Declares the extra loop state (`zzForce`, `zzSig`, `zzSame`, `zzCtrl`, `zzTodo`).
2. Bounds `tool_choice='required'` to 6 consecutive turns with zero writes, so a
   model that only wants to *answer* is not deadlocked by the required-tool mode.
3. Inserts the stuck-loop circuit breaker: identical consecutive tool calls
   (excluding legitimately repeatable terminal/error tools) or repeated rewrites of
   an unchanged todo list disable tools and force the final answer.

Usage
-----
    python scripts/patch-ide-agent-stuckloop.py            # apply (skips if already applied)
    python scripts/patch-ide-agent-stuckloop.py --force     # restore pristine + re-apply
    python scripts/patch-ide-agent-stuckloop.py --revert    # restore pristine only

Always keeps a pristine backup next to the bundle. Restart Mobius afterwards.
"""
import os
import shutil
import sys

P = os.path.expandvars(
    r"%LOCALAPPDATA%\Programs\Mobius\resources\app\out\vs\workbench\workbench.desktop.main.js"
)
BAK = P + ".bak-stuckloop-20260917"
PRISTINE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "VSCode-win32-x64", "resources", "app", "out", "vs", "workbench", "workbench.desktop.main.js",
)

NL = chr(92) + "n"  # JS source escape for a newline - never a real newline inside the literal

ANCHOR_STATE = b",Ra=c?aNo():void 0,bm=new RQt;"
ANCHOR_REQUIRED = b'ms=!Gn&&(Wo||Le&&p&&ye.writeSuccess===0),vt="",ui=[],so=!1,pn=!1,Yr=!1,qd="";'
ANCHOR_BREAKER = b"isError:!je||ni}]}]}if(qe>hi&&zt<jNn){"


def _breaker() -> bytes:
    nudge = (
        "STOP \u2014 you are stuck in a tool-call loop. You called the same tool with the same "
        "arguments repeatedly and it returned the same result every time; nothing changed. "
        "Tools are now DISABLED, so calling any tool will fail." + NL +
        "Write the complete final answer to the user now, in the same language they used, using "
        "ONLY the tool results already in this conversation." + NL +
        "If the remaining work genuinely cannot be done without more tool calls, say exactly what "
        "is missing and what you already found \u2014 that is an acceptable answer." + NL +
        "FORBIDDEN: asking the user to send another message."
    )
    parts = [
        ';{if(ye.writeSuccess>0)zzForce=0;',
        'let _vv=["run_in_terminal","run_terminal_command","get_terminal_output","get_terminal_last_command",'
        '"send_to_terminal","kill_terminal","get_errors","get_problems","vscode_askQuestions","vscode_ask_questions"],',
        '_ug=ui.filter(_c=>_vv.indexOf(_c.name)===-1)'
        '.map(_c=>`${_c.name}:${JSON.stringify(_c.parameters??{})}`).sort().join("|");',
        'zzSame=_ug&&_ug===zzSig?zzSame+1:0,zzSig=_ug;',
        'let _co=ui.length>0&&ui.every(_c=>{let _n=bVo(_c.name)??_c.name;'
        'return _n==="manage_todo_list"||_n==="todo"||_n==="todos"}),',
        '_tj=_co?JSON.stringify(this._chatTodoListService.getTodos(i.sessionResource)):null;',
        'if(zzCtrl=_co&&_tj===zzTodo?zzCtrl+1:0,_tj!==null&&(zzTodo=_tj),zzSame>=2||_co&&zzCtrl>=2){',
        'let _tn=ui[0]?.name??"tools";',
        'this._logService.warn(`[Continue] Stuck tool loop detected (identical=${zzSame}, '
        'no-progress-control=${zzCtrl}, tool=${_tn}) \u2014 disabling tools and forcing the final answer`),',
        'e([{kind:"warning",content:new ue("检测到工具调用死循环（"+_tn+" '
        '被反复调用但没有产生任何进展），已停止工具并直接根据已有结果输出答案。")}]),',
        'gt=!0,me=[...me,{role:1,content:[{type:"text",value:"' + nudge + '"}]}];break}}',
    ]
    return "".join(parts).encode("utf-8")


EDITS = (
    (ANCHOR_STATE,
     b',Ra=c?aNo():void 0,bm=new RQt,zzForce=0,zzSig="",zzSame=0,zzCtrl=0,zzTodo="";',
     "state-vars"),
    (ANCHOR_REQUIRED,
     b'ms=!Gn&&(Wo||Le&&p&&ye.writeSuccess===0)&&zzForce<6,vt="",ui=[],so=!1,pn=!1,Yr=!1,qd="";ms&&zzForce++;',
     "bounded-required"),
    (ANCHOR_BREAKER,
     b"isError:!je||ni}]}]}" + _breaker() + b"if(qe>hi&&zt<jNn){",
     "breaker"),
)


def restore_from_pristine(dest: str) -> int:
    if not os.path.exists(PRISTINE):
        print("pristine bundle not found:", PRISTINE)
        return 3
    shutil.copy2(PRISTINE, dest)
    print("restored pristine:", dest, os.path.getsize(dest))
    return 0


def main() -> int:
    args = set(sys.argv[1:])

    if not os.path.exists(P):
        print("bundle not found:", P)
        return 1

    if "--revert" in args:
        rc = restore_from_pristine(P)
        if rc == 0 and not os.path.exists(BAK):
            shutil.copy2(PRISTINE, BAK)
        os.path.exists(PRISTINE) and os.path.exists(BAK) and print("backup kept:", BAK)
        return rc

    if "--force" in args:
        rc = restore_from_pristine(P)
        if rc != 0:
            return rc
        shutil.copy2(PRISTINE, BAK)
        print("backup written:", BAK, os.path.getsize(BAK))

    data = open(P, "rb").read()
    if b"Stuck tool loop detected" in data:
        print("already patched (pass --force to restore pristine and re-apply)")
        return 0

    if not os.path.exists(BAK):
        shutil.copy2(P, BAK)
        print("backup written:", BAK, os.path.getsize(BAK))

    before = len(data)
    for anchor, new, label in EDITS:
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
