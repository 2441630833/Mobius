---
name: fix-blocked-pip-git-installs
description: "Use when a pip install from a git+https source fails in CI (git clone 502 / DNS failure / host blocked) or a package reinstalls on every run despite already being installed, especially on restricted networks (e.g. behind the GFW)."
auto-generated: true
generated-at: 2026-09-04T10:25:21.390Z
source-task: "```\r\n============================================================\r\n  Install FGN PhysicsNeMo env inside groot-gui (conda env fgn, isolated from groot/miniworld)\r\n=====================================…"
---
# Fixing blocked git+https pip installs and perpetual-reinstall loops

## When to use
- An install script/notebook fails on `pip install git+https://github.com/...` with `git clone` errors: HTTP 502 from a mirror, `Could not resolve host`, timeout/connection reset, or host unreachable.
- A package that is already installed (`Requirement already satisfied: ...`) gets reinstalled on *every* run, and the reinstall path is what fails.
- You are on a restricted network (China mainland hosts, air-gapped CI, corporate proxy) where github.com is unreliable but mirrors exist.
- An assertion/import check for a library class or API always fails, even on freshly installed versions.

## Steps

1. **Separate the two independent failure modes before touching network config.**
   - Mode A: the install is being *triggered* when it should not be (the "already satisfied?" check is wrong — e.g. it probes for a class/API that does not exist in any version).
   - Mode B: the install is genuinely needed but every source URL is unreachable.
   - Fix Mode A first: a wrong probe causes a perpetual reinstall loop that *looks like* a network problem but would fail even with perfect network.

2. **Derive the real API surface from authoritative sources — never guess names.**
   - For HuggingFace pipelines, fetch the model repo's `model_index.json`; its `_class_name` / component fields name the exact pipeline and transformer classes.
   - For an installed package: run `pip show <pkg>` in the target env and `python -c "import <pkg>; print(<pkg>.__version__, <pkg>.__file__)"`, then `grep`/inspect the package dir for the symbol.
   - For a remote repo without a full clone: `git ls-remote --heads <url>` to test reachability, then a shallow/sparse clone and `git ls-tree -r --name-only HEAD` + `git grep -n '<Symbol>' HEAD -- <path>` / `git show HEAD:<path>` to confirm the symbol exists in that branch/version.

3. **Make the satisfaction check feature-based and tolerant.**
   - Probe for *any* of the valid class names (e.g. try a tuple of candidate symbols via `getattr(diffusers, name, None)`) and cache the resolved one in a variable instead of hardcoding one name.
   - If the feature is present, skip installation entirely — do not touch the network at all.

4. **Probe mirror reachability cheaply *before* editing install scripts.**
   - `git ls-remote --heads <mirror-url>` (check exit code) for git sources; a plain HTTP GET for raw/wheel endpoints.
   - Record the exact failure per mirror: 502 (upstream dead), DNS failure (domain dead), timeout/reset (blocked). Mirrors rot — a mirror that worked months ago may be dead now, so re-probe at fix time.
   - Commonly reachable from China: `gitee.com/mirrors/<repo>` (verify the needed branch/files exist — mirrors can lag upstream), `gitclone.com/github.com/...`, `ghfast.top/` / `gh-proxy.com/` prefix proxies; for wheels, the Tsinghua PyPI mirror (`pypi.tuna.tsinghua.edu.cn/simple/<pkg>/`).

5. **Build an ordered, fault-tolerant source chain in the installer.**
   - Put verified-reachable mirrors first; wrap each attempt so failure emits a WARN and continues to the next source; after all git sources fail, fall back to the already-installed package if it passes the feature check (rather than hard-failing).
   - Apply the *same* check logic and *same* source chain everywhere the install is triggered (installer script AND notebook self-healing cells) so they cannot drift.

6. **Patch notebooks programmatically, not with text replacement.**
   - `.ipynb` is JSON: load with `python -c`/a small script using the `json` module, walk `nb['cells']`, and edit each cell's `source` (a list of line strings). Raw string replacement on notebook JSON corrupts escaping.
   - After editing, validate: `json.load` succeeds, `len(cells)` is sane, and grep for zero residual occurrences of the old symbol/URL.

7. **Verify and ship.**
   - Shell script: bracket/quote balance, grep that the new mirror is in the chain and the old broken probe is gone.
   - Re-run the probe logic mentally: installed package with the feature → skip path; missing feature → first mirror is the verified-reachable one.

## Pitfalls
- **A nonexistent class name in an assertion is the classic hidden root cause**: the check fails forever, so reinstall runs forever, so a network failure becomes the visible symptom. Always confirm the symbol exists in the actual package/model before blaming the network.
- Do not hardcode a mirror because it "used to work": 502s and dead DNS records are common. Probe every mirror at fix time and prefer gitee mirrors (which are hosted, not pass-through proxies).
- A pip line showing `Requirement already satisfied: <pkg>` after several failed mirror attempts means an *earlier* source in the chain already succeeded — read the whole log top to bottom.
- Gitee mirrors may lag upstream `main`; after cloning, confirm the specific file/symbol you need exists in the mirrored branch (`git ls-tree`/`git grep`).
- When downloading HF metadata via PowerShell, set `ServerCertificateValidationCallback` and `Proxy=$null` or TLS/cert errors can masquerade as network blocks.
- Branch names may not match the informal task name (e.g. work on `feature/foo-reproduce` rather than `foo`); check `git branch --show-current` in the worktree before pushing.

## Example
A CI stage installing `diffusers` from git failed: github.com was blocked, `gitclone.com` returned 502, and a proxy mirror had dead DNS. Investigation showed the *real* root cause: the notebook asserted `from diffusers import Cosmos3PolicyPipeline`, a class that exists in no diffusers version — the model's `model_index.json` declared `Cosmos3OmniDiffusersPipeline` + `Cosmos3OmniTransformer`. The false-negative check forced a diffusers reinstall on every run, which is what hit the blocked network. Fix: (1) probe for any of the real Omni class names at runtime and skip install when present; (2) probe mirrors with `git ls-remote` — gitee.com/mirrors/diffusers was reachable and contained the cosmos pipelines — and insert it first in the fallback source chain in both the installer script and the notebook; (3) patch the notebook via a Python `json` script; (4) validate JSON, symbol residuals (0), and shell syntax, then commit and push.
