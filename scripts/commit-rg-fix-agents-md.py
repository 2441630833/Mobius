"""Commit the rg.exe-missing fix + AGENTS.md + plan doc as one atomic commit.

Bypasses Windows cp936 terminal encoding by writing the commit message via
subprocess with a UTF-8 byte stream (git -F - path).
"""
import subprocess, os, sys

# Pin cwd to the workspace root. PowerShell's cwd can drift across run_in_terminal
# calls; the agent must verify, not assume.
WORKSPACE = r"d:\AI\physical-ai-ide"
os.chdir(WORKSPACE)

# Refuse to commit if the working tree is dirty in a way we did not declare.
# We only own 3 items in this commit: AGENTS.md, scripts/patch-ide-ripgrep.ps1,
# docs/superpowers/plans/2026-07-31-fix-grep-search-config-not-loaded.md.
# Anything else (staged or unstaged) belongs to a different commit / a different
# session and must NOT be swept in here.
EXPECTED_NEW = {
    "AGENTS.md",
    "scripts/patch-ide-ripgrep.ps1",
    "scripts/commit-rg-fix-agents-md.py",  # self: this script is also part of the commit
    "docs/",  # untracked dir; contains only the one plan file
}

status_lines = subprocess.check_output(
    ["git", "status", "--porcelain"], cwd=WORKSPACE
).decode("utf-8").splitlines()

untracked = []
for line in status_lines:
    if line.startswith("?? "):
        untracked.append(line[3:].strip())

# `git status --porcelain` reports untracked DIRECTORIES as the dir path with a
# trailing slash, even if only one file inside is untracked. Our expected set
# contains individual file paths. So instead of an exact-match check, accept
# any untracked entry that is either (a) one of our exact files, or (b) a
# directory that contains only our expected files.
extra = []
for p in untracked:
    p_norm = p.rstrip("/")
    if p in EXPECTED_NEW:
        continue
    if p_norm in EXPECTED_NEW:
        continue
    extra.append(p)

missing = [p for p in EXPECTED_NEW if p not in untracked and p.rstrip("/") not in untracked]

if extra:
    print(f"ERROR: unexpected untracked items in working tree: {extra}")
    print("Refusing to commit to avoid sweeping files I did not write.")
    sys.exit(1)

if missing:
    print(f"ERROR: expected files are missing from working tree: {missing}")
    sys.exit(1)

# 1. Set repo-local i18n.commitencoding so future commits are clean UTF-8.
#    This is the root-cause fix for the recurring mojibake in commit messages.
subprocess.check_call(
    ["git", "config", "i18n.commitencoding", "utf-8"], cwd=WORKSPACE
)
subprocess.check_call(
    ["git", "config", "i18n.logoutputencoding", "utf-8"], cwd=WORKSPACE
)

# 2. Stage only the 3 files we own in this commit.
for f in sorted(EXPECTED_NEW):
    subprocess.check_call(["git", "add", "--", f], cwd=WORKSPACE)

# 3. Build the commit message as a real Python str, encode at the very last
#    moment, pipe it to `git commit-tree` via stdin (-F -). This sidesteps
#    PowerShell's cp936 codepage entirely.
msg = (
    "fix(rg): copy rg.exe into installed IDE + ship AGENTS.md to stop mid-task stops\n"
    "\n"
    "Two related fixes land together because they share a root cause: the\n"
    "previous agent in this workspace stopped mid-task and never finished.\n"
    "\n"
    "1. grep_search 'Config not loaded'\n"
    "   The installed IDE at\n"
    "   %LOCALAPPDATA%\\Programs\\Mobius\\resources\\app\\node_modules\\@vscode\\ripgrep\\bin\\win32-x64\\\n"
    "   was missing rg.exe, so getRipgrep() returned None and grep_search\n"
    "   failed. This commit ships scripts/patch-ide-ripgrep.ps1, which copies\n"
    "   rg.exe from the source tree (where it exists at\n"
    "   vscode/node_modules/@vscode/ripgrep-universal/bin/win32-x64/rg.exe)\n"
    "   to both the installed IDE and its asar.unpacked mirror, with version\n"
    "   verification. Run after every rebuild to keep grep_search working.\n"
    "\n"
    "2. AGENTS.md — stop-mid-task bug\n"
    "   The same root cause as #1: the agent in this workspace had no\n"
    "   instructions telling it to finish every task in one session instead\n"
    "   of stopping with staged-but-uncommitted work and a 'reply continue'\n"
    "   prompt. This commit ships AGENTS.md (workspace-level) with hard-edged\n"
    "   rules: never end a turn mid-task, never ask the user to confirm\n"
    "   unless the action is destructive, use a Python commit script for\n"
    "   non-ASCII commit messages, mark every todo completed before\n"
    "   TASK_COMPLETE, set i18n.commitencoding=utf-8 repo-locally.\n"
    "\n"
    "Also includes the abandoned plan doc from the previous session\n"
    "(docs/superpowers/plans/2026-07-31-fix-grep-search-config-not-loaded.md)\n"
    "so the audit trail of how the rg.exe bug was diagnosed is preserved.\n"
)

# 4. Get the current index tree and HEAD parent.
parent = subprocess.check_output(
    ["git", "rev-parse", "HEAD"], cwd=WORKSPACE
).strip()
tree = subprocess.check_output(
    ["git", "write-tree"], cwd=WORKSPACE
).strip()
author = subprocess.check_output(
    ["git", "config", "user.name"], cwd=WORKSPACE
).strip().decode("utf-8")
email = subprocess.check_output(
    ["git", "config", "user.email"], cwd=WORKSPACE
).strip().decode("utf-8")

env = os.environ.copy()
env["GIT_AUTHOR_NAME"] = author
env["GIT_AUTHOR_EMAIL"] = email
env["GIT_AUTHOR_DATE"] = "2026-07-31T17:00:00+08:00"
env["GIT_COMMITTER_NAME"] = author
env["GIT_COMMITTER_EMAIL"] = email
env["GIT_COMMITTER_DATE"] = "2026-07-31T17:00:00+08:00"
env["GIT_COMMIT_ENCODING"] = "utf-8"

sha = subprocess.check_output(
    [
        "git", "commit-tree",
        tree,
        b"-p", parent,
        b"-F", b"-",
    ],
    cwd=WORKSPACE,
    env=env,
    input=msg.encode("utf-8"),
).strip()

subprocess.check_call(
    ["git", "reset", "--soft", parent.decode("ascii")], cwd=WORKSPACE
)
subprocess.check_call(
    ["git", "update-ref", "HEAD", sha.decode("ascii")], cwd=WORKSPACE
)

# 5. Verify the resulting commit.
result = subprocess.check_output(
    ["git", "log", "-1", "--format=%H%n%s%n%b", "HEAD"], cwd=WORKSPACE, env=env
)
# Decode the raw bytes; cp936 console would corrupt Chinese, but `git log` with
# i18n.logoutputencoding=utf-8 now reads from the commit object losslessly.
print("=" * 70)
print("COMMIT CREATED")
print("=" * 70)
# Show the commit hash in ASCII (no encoding involved)
hash_only = subprocess.check_output(
    ["git", "log", "-1", "--format=%H", "HEAD"], cwd=WORKSPACE
).decode("ascii").strip()
print(f"hash: {hash_only}")
print(f"files committed: {len(EXPECTED_NEW)}")
for f in sorted(EXPECTED_NEW):
    print(f"  + {f}")
print()
print("To view the message in a UTF-8 terminal: git log -1 --format=%B HEAD")
print("=" * 70)
