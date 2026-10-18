# Mobius RSI 2.0 核心引擎接入与实施计划

## Root cause

上一阶段已完成 10 篇论文全景分析与 4 大理论引擎的代码研发（`harness-schema.ts`、`second-order-diagnostic.ts`、`regularizer.ts`、`comparative-evaluator.ts`），但既有系统运行层（`proposer.ts`、`gate.ts`、API 路由 `run/route.ts` 与 `approve/route.ts`）仍停留在 1.0 的一阶单体模式，未将二阶异常诊断、正则化 Critic 审查、退火预算、MGM 跨谱系杂交与 RHI Pairwise 效益核算全链路串联。

## Goal

将 10 篇论文核心能力完整接入 Mobius RSI 执行管线：
1. **升级 `proposer.ts`**：引入二阶异常监听（复发与互斥修改检测）、退火预算调度、Critic 防作弊/防泄露过滤、以及 MGM 跨谱系候选杂交。
2. **升级 `gate.ts`**：将原有 5 项静态门禁扩展为 7 项综合门禁（新增 Critic 安全审查、正则化 Token 预算检查、RHI 效益核算）。
3. **升级 `run/route.ts` 与 `approve/route.ts`**：在 SSE 流程中输出二阶诊断发现、Critic 评分与 Pairwise 效益，并在晋升时执行 Pruner 剪枝。
4. **端到端自测与闭环验证**：构造模拟执行数据，验证全流程联动正常。

## Non-goals

- 不修改现有 Next.js 前端页面的基础组件接口契约（通过保持原有字段兼容并丰富 `data` 载荷实现无缝接入）。
- 不破坏本地已存在的 Playbook 版本与已有的测试数据集。
- 不触碰无关的 VS Code 或第三方依赖模块。

## Tasks

1. [x] **升级 `rsi-test/lib/proposer.ts`**：
   - 接入 `SecondOrderDiagnosticEngine`（异常检测、因果探针生成与注入）。
   - 接入 `RegularizerEngine`（时间退火预算、Critic 预审过滤）。
   - 接入 `ComparativeEvaluator`（MGM 跨谱系杂交候选生成）。
2. [x] **升级 `rsi-test/lib/gate.ts`**：
   - 扩充 `GateCheck`，引入 Critic 审查检验与正则化 Token 预算检验。
   - 接入 `ComparativeEvaluator.computePairwiseDiff`，生成 RHI 帕累托效益分析。
3. [x] **升级 `rsi-test/app/api/loop/run/route.ts` 与 `approve/route.ts`**：
   - 在 SSE 流中实时推送二阶因果异常、Critic 审查得分与 MGM 杂交事件。
   - 在版本晋升（approve）时自动触发 Pruner 剪枝。
4. [x] **端到端静态检查与逻辑测试**：
   - 执行 TypeScript 类型编译检查，确保零错误。
   - 编写并运行端到端管线验证脚本，验证新诊断、Critic、MGM 杂交与门禁联动正确。
5. [x] **提交与归档**：
   - 遵循 AGENTS.md 规范，在 `rsi-test` 与根目录分别完成干净提交。

## Verification results

- **Proposer 全面升级**：`proposer.ts` 接入 `SecondOrderDiagnosticEngine` 实时监听复发与互斥编辑异常，将因果事实注入 Meta 诊断 Prompt；接入 `RegularizerEngine` 依演化代际动态退火规则与 Token 增量预算；接入 `ComparativeEvaluator` 实现 MGM 跨谱系杂交候选生成，并在输出前由 Critic 严格阻断测试集照搬与 Reward Hacking。
- **Gate 门禁扩展至 7 项**：`gate.ts` 在原有 5 项基础（无回归、准确率不下降、无解析错误、净收益正向、无品类崩溃）上新增两项核心防御——`critic_safety_review`（安全防作弊审查）与 `token_budget_regularized`（Token 膨胀抑制）。
- **SSE 流与晋升闭环**：`app/api/loop/run/route.ts` 在流式推送中实时输出二阶异常、Critic 评分与 RHI 帕累托效益；`app/api/loop/approve/route.ts` 在人工审批晋升新 Champion 时自动调度 Pruner 剪枝死规则与重复项。
- **端到端逻辑验证**：5 大管线阶段测试全部通过（二阶异常检测、Critic 审查、MGM 谱系重组、7 门禁校验、晋升剪枝），通过 TypeScript 编译器验证。
- **多仓提交**：`rsi-test` 子系统干净提交（commit: `4a907ce`），根工程文档已规范纳入追踪。
