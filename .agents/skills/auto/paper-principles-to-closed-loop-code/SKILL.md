---
name: paper-principles-to-closed-loop-code
description: "Use when translating research-paper or architecture principles into a production implementation whose claims must be enforced by tests, measurements, and end-to-end tooling."
auto-generated: true
generated-at: 2026-09-02T05:50:32.916Z
source-task: "continue"
---
## When to use

- A paper, design doc, or architecture principle must become working code, not just notes.
- Performance or capability claims need to stay aligned with the real protocol, hardware, or schema.
- A new model or tool spans multiple layers such as server, CLI, launcher, fallback, client types, documentation, and agent instructions.
- The team needs a closed-loop definition of done: code is tested, measured, wired, documented, and type-checked.

## Steps

1. **Extract transferable principles**
   - Reduce the source material to a small set of principles.
   - For each principle, write:
     - The invariant or claim it implies.
     - The code artifact that enforces it.
     - The test or measurement that proves it.

2. **Capture a green baseline**
   - Record the current test count, self-test result, typecheck result, and error count before changing code.
   - Use this baseline to distinguish pre-existing failures from new ones.

3. **Make the spec the single source of truth**
   - Derive sizes, offsets, frame lengths, and bounds from the authoritative encoder/schema/configuration.
   - Avoid hard-coded paper numbers that can silently drift.
   - Add contract tests that fail immediately if the protocol or device parameters change.

4. **Implement models as upper bounds, not as truth**
   - Model non-overlapping stages explicitly; do not hide latency across stages.
   - Derive byte counts from the same encoding path used by production code.
   - Keep device-specific bounds tied to actual device parameters, such as clock, baud rate, or log2 lane count.

5. **Calibrate with measurements**
   - Instrument real operations with both predicted and measured values.
   - Return fields such as `model_ms`, `measured_minus_model_ms`, and `model_tokens_per_s`.
   - Make host-side overhead visible separately from accelerator or device time.

6. **Wire the capability through every layer**
   - Server/tool interface: expose the new operation.
   - CLI: provide a command for manual and scripted use.
   - Launcher: declare the tool as required or supported.
   - Fallback: provide a no-hardware, dependency-light implementation so CI and offline development can validate wiring.
   - Client: update schemas, type definitions, tool sets, and dispatch switches.
   - Docs: update tool tables, workflows, and performance-model sections.
   - Agent instructions: add the workflow step and a measurable definition of done.

7. **Use evidence-gated completion rules**
   - Throughput and performance claims must cite measured output.
   - The model may predict an upper bound, but "done" requires a measurement or an explicitly skipped/no-hardware test.

8. **Run the full verification gate**
   - Targeted unit tests.
   - Protocol or contract tests.
   - MCP/tool self-tests.
   - Typecheck or compiler no-emit check.
   - Editor/diagnostic error scan.
   - Compare results against the baseline.

## Pitfalls

- **Hard-coding paper numbers:** derive values from the protocol encoder or configuration so spec drift causes test failure.
- **Overlapping unrelated stages:** only overlap work that the architecture actually allows; sum serial stages honestly.
- **Implementing only the server tool:** missing CLI, launcher, fallback, client schema, docs, or agent dispatch causes invisible integration breakage.
- **Treating the model as measurement:** the model is an upper bound; real data calibrates and exposes host overhead.
- **Letting documentation lead:** docs and agent prompts should describe tested behavior, not aspirational behavior.
- **Requiring hardware for wiring tests:** keep a pure-stdlib or mock fallback so CI can validate the full tool path.
- **Adding tests without a baseline:** a baseline makes it clear whether the change improved or regressed the system.

## Example

Principle: *A roofline performance model gives an upper bound; real measurements calibrate the truth.*

Implementation pattern:

1. Create a performance model that calculates serial stage time, such as:
   - transmit time,
   - streaming/device time,
   - receive time.
2. Derive all byte counts from the protocol encoder.
3. Add tests that lock frame length and device-bound behavior.
4. Instrument sampling operations to return:
   - `model_ms`,
   - `measured_minus_model_ms`,
   - `model_tokens_per_s`.
5. Expose a `bound` tool/command for querying the roofline.
6. Register it in the server, CLI, launcher, fallback implementation, client schema, and dispatch code.
7. Document the performance model and update the agent workflow to require measured throughput claims.
8. Run unit tests, self-test, typecheck, and diagnostics; finish only when all gates are green.
