# Mobius continuous background coding

Mobius can inspect a project periodically, infer useful coding tasks under written rules, and execute them without a new chat request. A detached Node.js service keeps running after the IDE closes. The default is two concurrent workers, at most six inferred tasks and 24 discovery passes per UTC day. Discovery checks every 15 minutes until the daily budget is exhausted. Healthy operation sends no notifications; a local panel lists reviewable results and blockers.

The upstream [dsh-superagent-prototype](https://github.com/deepseek-ai/dsh-superagent-prototype) is pinned at `6337fc823ce20251c8de8085948165c81aaa701e`. Mobius directly imports its unmodified `src/core` Engine, authorization gates, Tickets, Assignments and stage calculation. `scripts/superagent/core.mjs` implements its Repositories port using SQLite transactions. This is a local project Source and Mobius model Executor, not the upstream GitHub/Feishu deployment or its full DSH web application. The upstream MIT license is retained and included in packaged clients.

```mermaid
flowchart LR
  Clock[Periodic discovery] --> Read[Read project docs and code]
  Read --> Rules[Written rules + budgets + deduplication]
  Rules --> Engine[Upstream Super Agent Engine]
  Engine --> A[Worker in worktree A]
  Engine --> B[Worker in worktree B]
  A --> Check[Independent project verification]
  B --> Check
  Check --> Review[Local commits + attention panel]
```

## Start from Mobius

Click **Super Agent** in the status bar or the robot icon beside the chat input. The menu shows whether the service is running and provides Start/Resume, Pause, Stop, project rules and the results panel. Status refreshes every five seconds; an expired heartbeat is shown as unavailable, never as a running worker. Opening Mobius does not implicitly start background model calls.

The results panel shows tasks, review branches, blockers and discovered opportunities. It supports pause/resume, stop, acknowledging handled items and retrying blocked tasks. Control requests require the local panel's session token and same-origin loopback request. When the service is stopped, use Start/Resume in Mobius first.

Install Node.js 24 and Git. Open a trusted local repository and configure a Mobius OpenAI-compatible model. Run **Mobius: Start Autonomous Background Coding** from the command palette. The command uses `loadContinueModels`, including the active `.env` profile / existing Continue model configuration, and passes its first active configured model to the detached process through environment variables. It does not require another API key. Changing a chat model temporarily does not change the background model; stop and restart after changing the active profile.

The terminal prints the loopback panel URL and policy path. **Mobius: Background Coding Status and Panel** shows that URL and current status again. **Pause Background Coding** stops new work and lets running workers finish. **Stop Background Coding** cancels active workers and stops the host; branches and worktrees remain. **Observe Coding Opportunities Only** switches an existing service to read-only discovery. No popup is emitted on each scan.

`mobius.superagent.nodePath` can select a Node 24 executable; `mobius.superagent.runtimePath` can select a source checkout's `scripts/superagent/cli.mjs`. Packaged Windows, Linux and macOS clients stage the adapter and upstream core automatically. Node 24 and Git remain external prerequisites.

## Project policy and verification

### Chat intake

The Agent chat now routes clear complex coding requests to Super Agent automatically (`mobius.superagent.autoRoute`, enabled by default). Questions, explanations, small edits and uncertain requests remain in the current chat. `/background <task>` explicitly selects background execution. Specialized modes, attachments and hook-dependent work remain in chat until their context can be transferred faithfully.

Each chat owns one task at a time. `另外加上测试` / `also ...` appends requirements to that task; `暂停任务`, `恢复任务`, `取消任务`, `查看进度` (or pause/resume/cancel/status) operate it without creating another. Follow-ups arriving during verification continue in the same retained worktree. A new independent request while the chat already owns an unfinished task displays the existing owner; use another chat for independent parallel work.

The hidden bridge starts the background host on demand, using the selected Mobius model. Chat-only startup does not enable periodic discovery; the visible Start Autonomous Background Coding action enables it explicitly. The host stays alive after the short bridge process exits. Closing a chat does not cancel its task; use the task cancellation message or the background panel. Credentials travel through process environment and authenticated loopback transport, never task files. An existing host can accept a task using a different configured model.

Background intake requires a clean local Git checkout and configured verification command. Otherwise the response explains the reason and the current chat handles the request. The task captures the accepted commit, so subsequent branch movement cannot silently change its starting point. Results and blockers are appended to the originating response while that chat is loaded, including after reopening it; the panel always retains results. Transport uncertainty stops foreground execution and directs the user to query status rather than risk duplicate edits. Durable request IDs deduplicate retries and survive host restarts.

The intake classifier intentionally uses conservative, bilingual rules, not an extra model call. It does not promise to understand every paraphrase. Explicit controls and `/background` provide predictable overrides.

ECC preflight runs before intake and displays the detected languages/frameworks and recommended skills/agent profiles in chat. Recommendations do not count as adoption. Foreground tool observations show what was actually read or invoked and the final summary explicitly reports unused capabilities. Background workers receive a bounded catalog of up to three recommended skills and two agent profiles, with a `load_capability` tool to choose which to consult. Successful loads and short practical reasons are persisted and shown in the original chat as execution proceeds, followed by the final selection summary (including none). Loading an agent profile is reported as profile loading, never as spawning an agent. ECC supplies optional guidance; Super Agent owns scheduling, isolated execution and verification, so the two flows do not execute the same task twice.

State is private to the repository's Git common directory: `<git-common-dir>/mobius-superagent/`. It is outside the tracked project and shared by its worktrees. `config.json` contains written rules and budgets, never API credentials. The default rule permits concrete bugs, missing regression coverage and incomplete documented work, and excludes speculative features, deployment and publishing. Edit the policy to define the project's actual priorities.

CLI initialization starts in `observe`; the explicit Mobius **Start Autonomous Background Coding** command starts in `auto`. Automatic execution requires a verification command. Initialization detects the first available npm script in `test`, `check`, `compile` order when npm can be resolved. Inspect and replace this with the project's meaningful build/test gates, especially if `check` only checks prerequisites. For a non-npm project, initialize the policy and enter program/argument arrays before enabling auto:

```json
{
  "version": 1,
  "mode": "auto",
  "intervalSeconds": 900,
  "maxParallel": 2,
  "maxTasksPerDay": 6,
  "maxDiscoveriesPerDay": 24,
  "taskTimeoutSeconds": 1800,
  "rules": [{"id": "project-quality", "instruction": "Fix reproducible defects documented in docs/ and tests. Preserve the public API."}],
  "verification": [["python", "-m", "pytest"]]
}
```

Discovery has read/list tools only. Each worker has a fresh Git branch and directory based on the main checkout's committed HEAD; uncommitted user changes are not included. Workers can read/write files and run local programs. The supervisor runs the configured verification independently, checks the diff, then makes a local commit. It does not merge or push. Review `execution.branch`, `execution.commit` and `execution.worktree` in status; cherry-pick or merge only after review. Submodules/dependencies are not automatically materialized in a fresh worktree; workers may need to initialize/install them, and failures remain visible.

Git worktrees prevent workers editing the same checkout. They are **not an OS security sandbox**: program execution has the launching user's permissions. Use a restricted account/container for untrusted projects. Files and tool output may be sent to the configured model provider. API credentials are not intentionally stored in policy or task records; use normal secret management for the model environment.

## CLI and recovery

From this checkout, run `npm run superagent -- <command> --repo <project>`. Standalone CLI startup reads `AI_MODEL`, `AI_API_KEY`, `AI_BASE_URL` (or their `OPENAI_*` equivalents) from the launching environment. The IDE entry point supplies these automatically.

| Command | Effect |
| --- | --- |
| `init` | Create policy in observe mode and print its location |
| `start` | Start detached, retaining the current mode |
| `start --auto` | Enable autonomous execution and start |
| `run` | Run in foreground for an OS service manager |
| `status` | Show status, panel URL, tasks and review branches |
| `pause` / `observe` / `auto` | Change scheduling mode |
| `stop` | Cancel active work, drain and stop |
| `retry <ticket-id>` | Retry a blocked/failed task in its retained worktree |
| `acknowledge <attention-id>` | Remove a handled attention item |

SQLite persists tasks, decisions, verification results, deduplication keys and daily budgets. Duplicate service instances are refused. After a crash, a running assignment with an uncertain outcome becomes blocked, rather than blindly replaying a shell command. Inspect retained work and any orphaned external commands, then retry it. Pending tasks can resume; changed written rules block tasks accepted under the old policy. Observed proposals can be reassessed after auto mode is enabled.

The service can run continuously while the machine is awake and online. It does not install a Windows service, scheduled startup task or systemd unit; for restart across reboot, supervise `run` using the host's service manager and supply model credentials through that manager. It is not a promise of execution during sleep, shutdown or a model-provider outage. Failed/blocked tasks require inspection/retry; there is no automatic merge or unbounded self-retry loop.

## Verification

`npm run superagent:test` exercises the actual upstream Engine, SQLite rollback, task budgets, duplicate suppression, two parallel real Git worktrees, independent verification failures, cancellation, and an actual detached host against a mock model HTTP server. No paid model calls or external GitHub messages are made by the tests. A live model quality/long-duration soak test is separate from these deterministic checks.
