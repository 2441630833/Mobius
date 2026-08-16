---
name: sync-docs-with-git-remotes
description: "Use when repository documentation may contain stale or incorrect remote or submodule URLs."
auto-generated: true
generated-at: 2026-08-16T10:56:22.389Z
source-task: "rebase的submoudle 的url 还不对，更新一下"
---
## When to use
- Documentation lists Git remote URLs, submodule URLs, or expected `git remote -v` output.
- A repository or submodule has been migrated between hosting platforms.
- Someone reports that rebase, setup, or troubleshooting instructions point to the wrong URL.

## Steps
1. **Collect the source of truth from Git, not from the docs.**
   - Run `git submodule status`.
   - Read `.gitmodules`.
   - Run `git remote -v` in the root repository.
   - For each submodule or nested repository, run `git -C <path> remote -v`.
2. **Build a comparison table** with repository name, remote role (`origin`, `upstream`, etc.), actual URL, and documented URL.
3. **Search the documentation** for each hostname, organization, and repository name that may be stale.
4. **Update all current-state references**, including:
   - Remote/submodule tables.
   - Expected command output.
   - Setup or rebase commands containing clone URLs.
   - Prose that asserts where a repository is currently hosted.
5. **Preserve conceptual distinctions:**
   - Keep `origin` and `upstream` separate.
   - Do not rewrite hypothetical migration instructions that intentionally use placeholders such as `<org>`.
6. **Verify by re-searching** for the old URL and reviewing the diff.

## Pitfalls
- Do not assume `.gitmodules` is enough: a submodule's locally configured remote may have been changed manually.
- Do not replace every occurrence of an old URL blindly; some may describe historical context or optional migration plans.
- Be careful with forks: the fork URL may change while the upstream URL remains unchanged.
- Hostname-only search can miss cases where only the organization or repository name changed.

## Example
If documentation says a submodule uses `https://gitee.example/org/repo.git`, but `.gitmodules` and `git -C submodule remote -v` show `https://gitcode.example/org/repo.git`, update:
- The submodule table.
- The expected `origin` line in command output.
- Any prose stating that the submodule remains on the old host.

Leave a future migration section with a placeholder like `https://github.example/<org>/repo.git` unchanged unless it claims to describe the current configuration.
