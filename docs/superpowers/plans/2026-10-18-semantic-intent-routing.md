# Semantic Intent Router for Mobius Agent Modes

## Root cause

Mobius previously relied on static regex keyword matching (`hasPptIntent`, `hasGameDevIntent`, `hasChipDesignIntent`) in `inferMobiusModeFromPrompt`. This causes:
1. **Low recall on paraphrased requests:** Natural variations (e.g. "准备明天给投资人的商业路演材料", "帮我做个季度总结胶片", "给角色加个跳跃重力效果", "查看环形振荡器的仿真输出") fail to match the rigid regex and fall back to general coding.
2. **False positives from technical overlap:** Development requests dealing with pptx file libraries (e.g. "用python写一个pptx解析脚本") or discussing engine architectures ("对比FPGA与ASIC", "Godot源码解析") get misrouted to PPT or Chip or Game mode instead of the general coding Agent.
3. **No semantic confidence scoring:** Binary regex cannot differentiate between strong intent and weak/incidental mentions.

## Research on GitHub Open-Source Projects

We surveyed key open-source projects addressing LLM intent and model routing:
1. **`aurelio-labs/semantic-router`**: The industry benchmark for super-fast, deterministic semantic routing without LLM overhead.
   - Core mechanism: Defines routes as collections of canonical "utterances" (exemplars) embedded in vector space. Matches incoming user prompts against route utterance vectors using cosine similarity with calibrated dynamic thresholds.
2. **`vllm-project/semantic-router` (formerly `redhat-et/semantic_router`)**: High-performance Mixture-of-Models routing layer with rule-based guardrails, fast embedding classification, and task categorization.
3. **`lm-sys/RouteLLM`**: Multi-tier routing strategies (matrix factorization, thresholding, and embedding classifiers) trained on preference datasets.

## Goal

Inspired by `aurelio-labs/semantic-router`, implement a native TypeScript hybrid Semantic Intent Router for Mobius:
- **Tier 1 (Slash Command Override):** `/ppt`, `/game`, `/chip`, `/agent` override with 100% confidence.
- **Tier 2 (Negative Context Guardrails):** Detect non-mode technical coding queries (e.g., library implementation, file parsers, theory discussions) and retain general Agent mode.
- **Tier 3 (Semantic Utterance Vector Matching):** Built-in bilingual (ZH/EN) exemplar vectors per route (`ppt`, `game`, `chip`, `agent`) using Mobius's in-process local embedder (`embedTextLocal`) and cosine similarity.
- **Tier 4 (Lexical Signal Boost):** Weighted lexical token coverage combined with semantic similarity for robust hybrid ranking.
- **Tier 5 (Calibrated Threshold & Confidence):** Threshold-gated decision making (default $\ge 0.52$ cosine similarity or composite score) ensuring high accuracy and zero false triggers.

## Non-goals

- Adding external Python dependencies or calling remote embedding APIs (everything runs in-process with zero network latency).
- Changing user-visible modes in the UI picker (remains the single default Agent mode).
- Breaking existing slash commands or file edit workflows.

## Tasks

1. [x] Create plan document `docs/superpowers/plans/2026-10-18-semantic-intent-routing.md`.
2. [x] Implement `vscode/src/vs/workbench/contrib/continue/browser/continueSemanticRouter.ts`:
   - Curated anchor utterances for `ppt`, `game`, `chip`, and `agent`.
   - In-process precomputed/cached exemplar vectors via `embedTextLocal`.
   - Negative intent guardrails for code/library vs task queries.
   - Hybrid semantic + lexical scorer with confidence calculation.
3. [x] Integrate semantic router into `inferMobiusModeFromPrompt` in `continueMobiusModeRouting.ts`.
4. [x] Wire semantic router diagnostics/logging in `continueChatAgent.ts` so auto-routed modes report confidence and reason.
5. [x] Update and expand unit tests in `vscode/src/vs/workbench/contrib/continue/test/browser/continueMobiusModeRouting.test.ts`:
   - Paraphrased presentation requests with zero literal "ppt" keywords.
   - Paraphrased game physics and platformer requests.
   - Paraphrased RTL / FPGA testbench requests.
   - Negative guardrails (pptx parser script, CSS animation -> Agent).
   - Slash command overrides.
6. [x] Verify compilation with `typecheck-client`, transpile, and run test suite.
7. [x] Clean git commit in `vscode` and parent repository.

## Acceptance criteria

- Natural language prompts without explicit keywords (e.g. "帮我准备周会汇报材料", "做个方案给领导演示", "总结项目进展做成胶片") reliably route to PPT mode.
- Technical coding queries touching file formats (e.g. "写一个解析pptx的python库") stay in general Agent mode.
- Routing executes synchronously in <5ms with zero external API calls.
- All unit tests and typechecks pass with 0 errors.
