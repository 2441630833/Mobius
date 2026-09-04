---
name: optimize-tool-detection-probes
description: "Use when a capability or tool-detection command is slow because it runs independent subprocess probes serially, repeats expensive checks, or wastes attempts on incompatible interpreters."
auto-generated: true
generated-at: 2026-09-02T03:42:31.220Z
source-task: "continue"
---
## When to use

Use this for CLIs, MCP servers, setup scripts, or environment detectors that:
- Run many external commands or version probes.
- Have long per-probe timeouts or depend on slow external daemons.
- Must preserve their existing output schema, exit behavior, or caller contract.
- Resolve an interpreter by trying multiple runtimes, some of which are known incompatible.

## Steps

1. **Establish a baseline**
   - Run the detector and measure wall-clock time.
   - Run the relevant unit tests, self-tests, and contract checks.
   - Identify the slowest probes and whether they are independent.

2. **Map probe dependencies**
   - Treat probes as independent unless one consumes another's result.
   - Keep expensive shared prerequisites separate so they can be executed once and reused.
   - Preserve the original result order for deterministic output.

3. **Parallelize independent probes**
   - Use a bounded thread pool for subprocess-based probes.
   - Run each probe with its existing timeout and error handling.
   - Capture failures as probe results rather than letting one failure cancel the whole detection report.
   - If a dependent probe needs a shared result, run that prerequisite first and pass its result into the dependent probe.

4. **Eliminate duplicate expensive checks**
   - If multiple probes query the same daemon or runtime, perform that query once.
   - Pass the shared result to dependent logic instead of repeating the slow subprocess call.

5. **Gate interpreter candidates cheaply**
   - Reject incompatible runtime versions before attempting expensive imports or startup.
   - Prefer combining the version check and capability check in one spawn.
   - Do not change the spawn argv shape if multiple launchers or fallback paths rely on it.

6. **Reassemble and verify**
   - Rebuild the report in the original order.
   - Keep the same JSON/object schema, exit codes, and user-visible behavior.
   - Re-run tests, self-tests, and the timing command.
   - Compare output before and after to catch contract regressions.

## Pitfalls

- Do not parallelize probes that share mutable state or depend on each other's side effects.
- Parallel execution can interleave logs; restore deterministic ordering before returning results.
- A thread pool does not replace subprocess timeouts: hung commands must still be terminated.
- Do not swallow exceptions from individual probes; convert them into the same failure representation used before.
- Avoid "clever" argv changes in interpreter resolution unless every caller is updated; launcher contracts often accept both string and array forms.
- A version gate that adds another process spawn can make the ladder slower; fold it into the existing probe.
- External daemons may be slow or unavailable; their failure should not block unrelated probes.

## Example

A detector originally ran a dozen environment probes serially, with each probe able to wait on a long timeout. It also queried the same container daemon twice and tried an old interpreter shim before failing on syntax or import checks.

The optimized version:
- Runs independent probes concurrently in a thread pool.
- Runs the shared container-daemon probe once and passes its result to the dependent image probe.
- Rejects interpreters below the required version during the same spawn that tests import capability.
- Reassembles results in the original cheapest-first order.
- Leaves the report shape and launcher contract unchanged.

Verification consists of the existing test suite, the detector self-test, and a before/after wall-clock measurement of the detection command.
