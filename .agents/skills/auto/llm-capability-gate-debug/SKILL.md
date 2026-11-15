---
name: llm-capability-gate-debug
description: "Use when a feature the model/provider actually supports (image input, tools, streaming) is silently disabled by a client-side capability check, routing the request into a degraded fallback path."
auto-generated: true
generated-at: 2026-11-13T06:22:39.216Z
source-task: "你能看到这个图片吗\r\n\r\n[]()\r\n\r\nECC preflight — detected stack: python.\r\n\r\nAutomatic routing — suggested skills: none; ECC agent profiles: none.\r\n\r\nImage request cancelled. Enable local OCR or select a multimod…"
---
## When to use

- A user says "the model can do X, why does the client refuse/route around it?" (e.g. "vision works, but the request is cancelled and OCR is suggested").
- An error message like `request cancelled`, `select a multimodal model`, `enable local OCR`, `capability unsupported` appears even though the endpoint demonstrably accepts the payload.
- A config/declaration written by a gateway or model catalog (`capabilities: [...]`, `supports_*` flags, feature lists) is being interpreted as authoritative.

Do not use for genuine server-side 4xx rejections — that is a provider problem, not a gating bug.

## Steps

1. **Find the user-visible string first.** Grep the exact error text (`Image request cancelled`, `Enable local OCR`) to locate the sink of the decision. That gives you the *last* layer in the chain.
2. **Walk the chain backwards, one layer at a time.** Typical four layers:
   - Config/model catalog ingestion (`capabilities: [image_input]` → `uploadImage` flag).
   - Capability resolution / normalization (`resolveModelVision()`-style helper that maps family + declared tokens → boolean).
   - UI enablement (attachment button, paste handler) gated on that boolean.
   - Request assembly / send path that branches on the same boolean and falls back to OCR, text extraction, or cancellation.
   Document each layer as *file:line → predicate → consequence* before touching code.
3. **Audit the predicate for allowlist-vs-denylist confusion.** The common root cause: a declared capability list is treated as exhaustive, so "list lacks `image` token ⇒ text-only". Such lists are usually **client hints**, not endpoint contracts. Verify by checking whether the same model returns token usage for the feature (e.g. `image_tokens: N` in usage) — that proves the server accepted it.
4. **Fix at the resolution layer, not the four call sites.** Flip the default for *unknown* cases to permissive (let the server arbitrate) and keep only explicit negative signals (per-model `imageInput: false`, `text_only` token, an env escape hatch such as `STRICT_<FEATURE>=1`). Prefer one narrow change over patching every consumer.
5. **Update the unit tests to encode the new semantics.** Convert the old expectation (`[tool_use] → false`) to the new one (`[tool_use] → true`) and *keep* the test that explicit deny tokens still return false — the regression guard is the deny path, not the allow path.
6. **Verify cheaply:** typecheck the client target, then run the editor's diagnostics on every edited file; require 0 errors before proceeding.
7. **Ship through every artifact layer that exists** (source repo → submodule/superproject pointer → installed bundle). If a local hotpatch script exists, run its `-Verify` mode and confirm both the patched pattern and the absence of the old one in the *installed* `*.js` under `%LOCALAPPDATA%\Programs\<app>\resources\app\...`. Then commit, push, and check the CI run status via the provider API if `gh` is unavailable.

## Pitfalls

- **Fixing the UI layer only.** The same predicate usually gates the attach button *and* the send path; patching one leaves the other.
- **Whitelisting the current model family by name.** Hardcoding `deepseek`, `ali`, `volcano` etc. is the same bug in a new coat. Fix the default, not the table.
- **Trusting the installed bundle without re-reading it.** Build outputs are minified and may already contain an older hotpatch; always `IndexOf`/regex the exact new snippet *and* the removed one.
- **Forgetting the submodule pointer.** In a superproject + submodule layout, the parent repo must be committed and pushed too, or the CI build silently uses stale code.
- **Skipping the type check** because "it's a one-line boolean change". Optional-chained capability objects and union types break easily.

## Example

Symptom: multimodal model returns `image_tokens: 186` from the API, yet the client cancels every image and offers local OCR.

Trace: model catalog parses `capabilities: [tool_use]` → `uploadImage: undefined` → `resolveModelVision()` returns `false` because "declared list without an image token means text-only" → attach button disabled, send path takes the OCR branch → cancel message.

Fix: in `resolveModelVision()`, delete the "non-image capability list ⇒ deny" rule; default unknown families to *accepts images*, keep `imageInput: false` and `STRICT_VISION=1` as the only deny paths. Update the vision test from `[tool_use] → false` to `[tool_use] → true`, keep `text_only → false`. Typecheck (exit 0), diagnostics clean, hotpatch the installed `workbench.desktop.main.js`, verify both the new and removed snippets, commit submodule + parent, push, watch CI.
