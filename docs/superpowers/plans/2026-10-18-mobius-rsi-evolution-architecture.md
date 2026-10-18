# Mobius RSI 架构升级全景方案（基于前沿 10 篇论文）

## Root cause

当前 Mobius 的 RSI 系统（`rsi-test` 核心模块）存在以下结构性技术瓶颈：
1. **单体 Playbook 耦合严重**：将所有规则、边界界定、样例硬塞在单一 `playbook.md` 中，缺乏模块化隔离，导致“改了场景 A、冲跨场景 B”的负向迁移（ModularRSI 与 Recuris 所警示的单体复杂性）。
2. **一阶症状追逐（Symptom-Chasing）**：现有的 `proposer.ts` 仅对最近批次的失败案例做简单频次统计，便直接生成修改，极易导致规则在版本间来回振荡、互斥修改（Opposing Edits），无法定位根本因果（SO-RSI 揭示的核心痛点）。
3. **缺乏正则化与剪枝机制**：演化过程中只增不减，缺乏 Token 退火预算与死规则剪枝器（Pruner），演化代际增加后会导致 Prompt 臃肿与过拟合崩溃（RRSI 揭示的过拟合风险）。
4. **单系克隆变异，缺乏比较遗传**：候选版本独立生成，没有汇总多任务反应谱系，也无法将不同分支的优势基因杂交（Mendel Gödel Machine 揭示的收敛迟缓）。
5. **高度依赖人工标注测试集**：目前验证强依赖预置的 `acceptance.jsonl`，无法在没有标准答案的开放生产场景中自主演化（Harness² 与 Ouroboros 解决的问题）。

## Goal

基于近 3 个月 10 篇顶会/arXiv 突破性论文（AIDE²、Meta^n、Harness²、RRSI、ModularRSI、Mendel Gödel Machine、SO-RSI、Ouroboros、Recuris、RHI），为 Mobius 建立一套**工业级、抗过拟合、自适应长程演化的现代 Agent Harness 自主递归改进体系（Mobius RSI 2.0）**。

## Non-goals

- 不修改底层大语言模型权重（严格遵循 Harness 演化范式，通过优化提示词、记忆、流程、工具指引与上下文调度实现能力跃迁）。
- 不破坏现有 `rsi-test` 的 Next.js 前端数据通道（保持既有 Dashboard、Chat、Traces、Batch 页面兼容，所有新数据结构通过平滑兼容层接入）。
- 不触碰无关模块（严格保护 `hermes-agent`、`vendor`、`vscode` 等子模块既有提交）。

## Tasks

1. [x] **理论与文献全景梳理**：系统化提炼 10 篇论文核心思想、量化指标与对 Mobius 的映射关系，输出研究综合文档 `docs/research/2026-10-18-rsi-10-papers-synthesis.md`。
2. [x] **Harness 5 模块化与双层记忆建模（ModularRSI + Recuris）**：
   - 在 `rsi-test/lib/harness-schema.ts` 中实现 Agent Loop、Tool Use、Observation Management、Context Management、Task Completion Detection 五大模块定义。
   - 实现 Working Memory 与 Skill Memory 解耦，支持技能的独立原子补丁与故障归因。
3. [x] **二阶因果诊断引擎（SO-RSI + Meta^n）**：
   - 在 `rsi-test/lib/second-order-diagnostic.ts` 中构建异常检测器，监听复发（Recurrence）、互斥修改（Opposing Edits）、预期落差（Expectation Mismatches）。
   - 实现轻量因果探针（Diagnostic Probing）与持久化探究记忆（Inquiry Memory），从根源杜绝版本振荡。
4. [x] **演化正则化器与修剪门禁（RRSI + AIDE²）**：
   - 在 `rsi-test/lib/regularizer.ts` 中实现提议预算时间退火（Annealed Edit Budget）与多样性调度。
   - 实现 Critic（阻断用例级作弊与泄露）与 Pruner（自动扫描并清除冗余/无用/高成本规则）。
5. [x] **多轨迹比较演化与开放探针接口（MGM + Harness² + RHI）**：
   - 在 `rsi-test/lib/comparative-evaluator.ts` 中实现反应规范突变（Reaction-Norm Mutation）与跨谱系杂交（Cross-Lineage Hybridization）。
   - 构建 Propose–Probe–Compose 探针机制，支持无标签真实交互的自主对比演化，以及 Pairwise 历史版本对比。
6. [x] **核心类型与执行流平滑整合**：
   - 升级 `rsi-test/lib/types.ts`，导出全量现代化 RSI 2.0 类型定义，并提供与原有单一 Playbook 的双向转换适配器。
7. [x] **代码静态检查与验证**：
   - 使用 Node/TypeScript 编译器及针对性测试运行验证，确保无编译错误与类型回归。
8. [x] **提交与归档**：
   - 遵循 AGENTS.md 规范，进行 UTF-8 干净提交，不留无用临时文件。

## Verification results

- **文献检索与理论映射**：准确对齐 10 篇前沿论文（AIDE²、Meta^n、Harness²、RRSI、ModularRSI、Mendel Gödel Machine、SO-RSI、Ouroboros、Recuris、RHI），输出详尽综述文档 `docs/research/2026-10-18-rsi-10-papers-synthesis.md`。
- **模块化 Harness 与双层记忆**：构建 `rsi-test/lib/harness-schema.ts`，实现 5 大独立模块（AgentLoop, ToolUse, ObservationMgmt, ContextMgmt, TaskCompletion）与 Working/Skill 双层记忆，支持向后兼容编译为单一 Playbook。
- **二阶因果诊断引擎**：构建 `rsi-test/lib/second-order-diagnostic.ts`，实现复发（Recurrence）、互斥修改（Opposing Edits）与预期落差监测，支持轻量因果探针与持久化 Inquiry Memory。
- **正则化与剪枝**：构建 `rsi-test/lib/regularizer.ts`，实现时间退火编辑预算、防止用例死记硬背与 Reward Hacking 的 Critic 审查器，以及定期清扫死规则的 Pruner。
- **比较演化与开放探针**：构建 `rsi-test/lib/comparative-evaluator.ts`，实现反应规范突变（Reaction-Norm Profile）、跨谱系杂交（Cross-Lineage Hybridization）、无标签扰动一致性探针，以及 Pairwise Token ROI 效益核算。
- **静态类型与功能自测**：通过 TypeScript 编译器无错编译，自测套件 4/4 全部通过，并已在 `rsi-test` 干净提交（commit: `febd0e1`）。
