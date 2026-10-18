# 10 篇前沿递归自我改进（RSI）论文全景剖析与技术映射

> 本文系统梳理并对齐近期 10 篇关键 RSI / Agent Harness 自主演化前沿论文的核心理论、架构机制及对 Mobius 系统的实战启示。

---

## 目录
- [一、方向一：让 Agent 改写自身代码与演化流程](#一方向一让-agent-改写自身代码与演化流程)
  - [1. AIDE²: Recursive Self-Improvement of AI Research Agents](#1-aide-recursive-self-improvement-of-ai-research-agents)
  - [2. Meta^n: Recursive Self-Improvement through Emergent Depth](#2-metan-recursive-self-improvement-through-emergent-depth)
  - [3. Harness²: Recursive Agent Harnessing for an Open World](#3-harness-recursive-agent-harnessing-for-an-open-world)
- [二、方向二：防止 Harness 演化过拟合与漂移](#二方向二防止-harness-演化过拟合与漂移)
  - [4. RRSI: Regularized Recursive Self-Improvement of Agent Harnesses](#4-rrsi-regularized-recursive-self-improvement-of-agent-harnesses)
  - [5. ModularRSI: Modular and Generalizable Recursive Harness Self-Improvement](#5-modularrsi-modular-and-generalizable-recursive-harness-self-improvement)
  - [6. Mendel Gödel Machine: Recursive Self-Improving Coding Agents via Comparative Evolution](#6-mendel-gödel-machine-recursive-self-improving-coding-agents-via-comparative-evolution)
  - [7. SO-RSI: Second-Order Problem Solving for Recursive Self-Improvement in Formal Verification](#7-so-rsi-second-order-problem-solving-for-recursive-self-improvement-in-formal-verification)
- [三、方向三：在长期运行中持续演化与成本优化](#三方向三在长期运行中持续演化与成本优化)
  - [8. Ouroboros: A Self-Developing Frontier Coding Agent with Reviewed Core Evolution](#8-ouroboros-a-self-developing-frontier-coding-agent-with-reviewed-core-evolution)
  - [9. Recuris: Recursive Experiential-Working Memory Evolution for Long-Horizon Agent Harnesses](#9-recuris-recursive-experiential-working-memory-evolution-for-long-horizon-agent-harnesses)
  - [10. RHI: Recursive Harness Self-Improvement](#10-rhi-recursive-harness-self-improvement)
- [四、10 篇论文对 Mobius RSI 的综合矩阵与落地启示](#四10-篇论文对-mobius-rsi-的综合矩阵与落地启示)

---

## 一、方向一：让 Agent 改写自身代码与演化流程

### 1. AIDE²: Recursive Self-Improvement of AI Research Agents
- **作者与机构**: Dhruv Srikanth, Bingchen Zhao, Dixing Xu, Yuxiang Wu, Zhengyao Jiang (Weco AI)
- **论文标识**: arXiv:2609.26457
- **核心机制**:
  - **双层嵌套优化结构（Two-tier Nested Optimization）**:
    - **内循环（Inner Loop）**: 自主研发 Agent 执行代码构建、算法调优与基准验证。
    - **外循环（Outer Loop）**: Meta-System 针对内循环 Agent 的执行框架（Harness Code）进行自主代码改写与策略演进。
  - **关键实验数据**: 连续 8 天无人类干预的自动化演化（100 轮外循环迭代），成功演化出 7 次突破性架构升级（如创新的搜索策略、动态上下文压缩缓存等）。
  - **泛化表现**: 在未见过的泛化测试集（包括极端物理天气预测、机器学习工程基准）上，性能逼平甚至超越人类工程师历经 2 年精细调优的工业级研发 Agent。
  - **作弊率与对齐效应**: 在没有显式设置作弊惩罚目标的情况下，Agent 在外循环演化中自主构建了 Prompt 级与代码级的防御围栏，Reward Hacking 概率随演化代际显著下降。

### 2. Meta^n: Recursive Self-Improvement through Emergent Depth
- **作者与机构**: Zae Myung Kim, Young-Jun Lee, Seungyeon Jwa, Dongyeop Kang (明尼苏达大学、首尔国立大学)
- **论文标识**: arXiv:2608.24735
- **核心机制**:
  - **突破“稳定性-深度困境（Stability-Depth Dilemma）”**: 传统自改写 Agent 深度通常被硬性限制在 2 层以内，否则因元操作漂移迅速崩溃。Meta^n 采用**固定元操作符 $\Omega$（Universal Meta-Operator）**，只在不断累积扩展的输入（代码 + 执行 Trace）上递归。
  - **自发涌现的分层架构（Emergent Depth & Roles）**: 深度由收敛状态动态决定，自发在不同层级涌现出专门角色：
    - Layer 1: 任务路由器（Task Router）
    - Layer 2: 通用纠错与恢复器（Generic Remediator）
    - Layer 3: 架构规划器（Code Architect）
  - **消融归因**: 约 72% 的性能收益来源于层间动态上下文传递，15% 来源于生成的通用可调用代码库。
  - **ARC-AGI-2 唯一突破**: 在专为抵御死记硬背而设计的抽象推理基准 ARC-AGI-2 上，成为所有受测自改进 Agent 中**唯一取得 >0 分（达到 0.33）的架构**。

### 3. Harness²: Recursive Agent Harnessing for an Open World
- **作者与机构**: Ruiyao Xu, Yanfei Chen, Zhongying CuiZhu, Bhavana Dalvi Mishra, Yifei Ming, Han Yu, Rujun Han, Chen-Yu Lee, Tomas Pfister (Google Cloud AI Research)
- **论文标识**: arXiv:2610.14224 / 代码库: google-research/harness2
- **核心机制**:
  - **解决“开放世界无标准答案”痛点**: 现实场景下 Agent 执行新任务没有预先准备好的 Ground-truth 验证器。
  - **双层递归体系（Two-Level Recursion）**:
    - **任务级递归（Task-Level）**: 采用对比式的 **Propose–Probe–Compose（提议-探针探测-合成）** 范式，无需真实标签即可基于一致性与扰动分析动态调优当前任务 Harness。
    - **治理级递归（Harnessing-Level）**: 将跨任务沉淀的经验模式提取为全局改进准则，持续升级演化底座。
  - **覆盖 8 大可演化组件**: 系统 Prompt、Guardrails 护栏、Memory 记忆、Tool Guidance 工具指引、Subagents 子代理编排、Skills 技能集、Scripts 自动化脚本、Plugins 插件扩展。

---

## 二、方向二：防止 Harness 演化过拟合与漂移

### 4. RRSI: Regularized Recursive Self-Improvement of Agent Harnesses
- **作者与机构**: Peng Xia, Rujun Han, Zifeng Wang, Yanfei Chen 等 (Google Cloud AI Research, 斯坦福大学等)
- **论文标识**: arXiv:2609.24972
- **核心机制**:
  - **揭露“演化集膨胀与分布外崩溃”**: 无约束的 Harness 演化极易过拟合训练任务（在演化集上不断刷高指标，但在未见过的真实 OOD 任务上崩盘）。
  - **提议正则化（Proposal Regularization）**: 引入时间退火编辑预算（Annealed Edit Budget），严格限制单次迭代注入的代码与规则规模；结合温度调度促使 Agent 探索多样化改进路径。
  - **选择正则化（Selection Regularization）**:
    - **Critic 审查器**: 拦截对特定用例特征的“硬编码作弊”与泄露式规则。
    - **Pruner 剪枝器**: 定期清除非活跃、冗余、计算开销过大或边际贡献微弱的旧规则，防止 Harness 臃肿。

### 5. ModularRSI: Modular and Generalizable Recursive Harness Self-Improvement
- **论文标识**: arXiv:2609.25597
- **核心机制**:
  - **解决单轨迹噪声与单体耦合**: 将庞大繁杂的 Agent Harness 彻底解耦为 5 个功能独立的演化模块：
    1. **Agent Loop（代理主循环）**: 状态机转换、重试退避与多轮对话逻辑。
    2. **Tool Use（工具调度）**: 工具 Schema、调用前置约束与参数格式化。
    3. **Observation Management（观察管理）**: 工具输出过滤、截断压缩与结构化提取。
    4. **Context Management（上下文管理）**: 历史窗口修剪、长程跨轮摘要与 Token 预算分配。
    5. **Task Completion Detection（完成检测）**: 任务终结判定、自我校验与交付门禁。
  - **对比式聚合分析（Contrastive Aggregated Analysis）**: 不依赖单次偶然失败，而是在多个基准不相交（Benchmark-Disjoint）任务中对比成败轨迹，定位共性系统性缺陷。
  - **跨模型迁移力**: 演化出的模块化 Harness 在 SWE-bench Verified 与 TerminalBench 2.0 上可直接无缝迁移到其他异构开源/闭源基座模型上并保持高胜率。

### 6. Mendel Gödel Machine: Recursive Self-Improving Coding Agents via Comparative Evolution
- **论文标识**: arXiv:2608.14457
- **核心机制**:
  - **超越达尔文单系克隆（Darwinian Clonal Mutation）**: 传统的自改写系统（如 DGM）仅根据最近一次失败轨迹进行局部单点修补，忽略了历史档案中的比较信息。
  - **孟德尔比较演化遗传学（Mendelian Comparative Genetics）**:
    - **反应规范突变（Reaction-Norm Mutation）**: 同时输入某个 Agent 在多个异构任务上的综合执行谱系，推演普适性更强的改写策略。
    - **跨谱系杂交（Cross-Lineage Hybridization）**: 允许不同演化分支（Lineages）之间共享各自在独立任务中发现的“优势基因”（如特定工具编排、鲁棒性补丁）。
  - **收敛效率**: 理论证明并在 SWE-bench / Polyglot 验证，杂交演化相比单系克隆不仅收敛速度提高 3~5 倍，且显著减少陷入局部极值的概率。

### 7. SO-RSI: Second-Order Problem Solving for Recursive Self-Improvement in Formal Verification
- **作者与机构**: Yuxuan Jiang, Aditya Vempaty, Ashish Jagmohan
- **论文标识**: arXiv:2610.05701
- **核心机制**:
  - **一阶表面调优 vs 二阶根因归因**: 一阶优化器仅追逐表面报错信息频繁修改 Prompt/代码，导致改了 A 坏了 B、产生振荡式互斥修改（Opposing Edits）。
  - **结构化异常被动监听**: 实时监听 3 大警报指标：
    - **Recurrence（复发率）**: 相同类型错误反复出现。
    - **Opposing Edits（互斥修改）**: 第 N 轮加入的规则在第 N+1 轮被反向删除。
    - **Expectation Mismatches（预期落差）**: 评估结果与提议器假设严重偏离。
  - **因果探针与探究记忆（Diagnostic Probing & Inquiry Memory）**: 一旦触发警报，暂停修改，启动轻量级因果探针探究底层根因，并将因果事实持久化到 Inquiry Memory，杜绝重复踩坑。

---

## 三、方向三：在长期运行中持续演化与成本优化

### 8. Ouroboros: A Self-Developing Frontier Coding Agent with Reviewed Core Evolution
- **作者与机构**: Ouroboros Team
- **论文标识**: arXiv:2608.08311
- **核心机制**:
  - **双重演化驱动模式**:
    - **自由递归演化（Recursive Free Evolution）**: 自我改进作为独立后台任务定期调度运行。
    - **经验驱动核心演化（Experience-Driven Core Evolution）**: 在日常生产交互、真实 Coding 报错中捕获摩擦点，驱动系统架构的迭代升级。
  - **多模型代码审查门禁（Multi-Model Reviewed Commit）**: 任何自改进补丁必须经过异构多模型裁判组（Reviewer Jury）的自动化代码审查与形式化门禁，才能 Commit 到主分支生效。
  - **161 天不间断实证（"Hope" 部署）**: 跨 Discord、Telegram、Web 等 7 大渠道稳定连续运行 161 天，自主合并超 1,000 次系统架构改进提交，证实了长周期自演化的可行性。

### 9. Recuris: Recursive Experiential-Working Memory Evolution for Long-Horizon Agent Harnesses
- **作者与机构**: NUS, 斯坦福大学, 牛津大学, 普林斯顿大学
- **论文标识**: arXiv:2608.24876 / 代码库: Gen-Verse/Recuris
- **核心机制**:
  - **双层记忆解耦（Decoupled Memory Architecture）**:
    - **Working Memory（工作记忆）**: 跟踪当前长任务的动态执行状态、中间变量与目标堆栈。
    - **Skill / Experiential Memory（技能与经验记忆）**: 存储跨会话可复用的工具策略、领域规则与避坑手册。
  - **故障精准定位（Failure Localization Engine）**: 当长链路任务执行受阻时，将故障精准归因到特定的技能或记忆项，而非模糊地重写全局 System Prompt。
  - **定界受控打补丁（Bounded Patching）**: Meta-Agent 仅对目标技能项执行原子修补，并由确定性验收门禁防止灾难性遗忘。

### 10. RHI: Recursive Harness Self-Improvement
- **作者与机构**: Hyunin Lee, Jinglue Xu, Jeffrey Seely, Donghyun Lee, Matei Zaharia, Yujin Tang (Sakana AI, UC Berkeley)
- **论文标识**: arXiv:2607.15524
- **核心机制**:
  - **改 Harness 的 ROI 远高于增加推理预算**: 传统认知倾向于通过加长思考链路（Inference-time Compute）提升能力，但 RHI 证明：通过对 Harness 进行数轮迭代升级，低推理成本模型即可超越高推理预算的基线。
  - **成本暴降 60%**: 在金融量化、机器人与计算医药等 30 项 ML 任务中，经过 RHI 优化的轻量 Agent 在超越高算力模型表现的同时，总推理 Token 消耗降低多达 60%。
  - **配对历史反馈（Pairwise Revision History Feedback）**: 将历史版本演进轨迹作为对比上下文输入，极大优化了跨 Agent 信息流与上下文吞吐质量。

---

## 四、10 篇论文对 Mobius RSI 的综合矩阵与落地启示

| 论文 | 核心思想 | 针对的问题 | Mobius RSI 改进对应落地项 |
| :--- | :--- | :--- | :--- |
| **AIDE²** | 双层嵌套优化 + 自主安全防御 | 内外循环耦合；出现作弊 | 设立独立 Outer Meta-Harness Loop，建立对抗性作弊检测 |
| **Meta^n** | 固定元操作 $\Omega$ + 累积输入涌现分层 | 递归深度>2时系统崩溃 | 固化不可变元提议模板，建立分层动态路由与架构师角色 |
| **Harness²** | Propose-Probe-Compose 开放世界演化 | 缺乏真实标签与验证器时无法演化 | 引入无监督探针与一致性探针，支持真实用户轨迹闭环 |
| **RRSI** | 退火预算 + Critic 审查 + Pruner 剪枝 | 演化集过拟合；规则无限膨胀 | 增加单轮变更 Token/规则上限，引入死规则自动修剪器 |
| **ModularRSI** | Harness 拆解为 5 大独立模块演化 | 单体 Prompt 牵一发而动全身；噪声干扰 | 将 `playbook.md` 拆分为 Agent Loop、Tool Use 等 5 模块 |
| **Mendel** | 反应规范多任务突变 + 跨谱系杂交 | 单轨迹单用例演化容易陷入局部最优 | 汇集多用例同时诊断，实现优秀 Candidate 的“染色体杂交” |
| **SO-RSI** | 二阶因果探究 + 互斥修改监测 | 头痛医头脚痛医脚；修改来回振荡 | 引入反复振荡警报，先下发 Diagnostic Probe 再提议修改 |
| **Ouroboros**| 自由演化+经验演化双轨；多模型审查 | 离线测试与在线生产脱节；演化不可控 | 引入自由定时演化与实时 Trace 驱动双轨，配置评审陪审团 |
| **Recuris** | 工作记忆与技能经验记忆解耦演化 | 长周期任务记忆混乱；修改伤及无辜 | 解耦 Working Memory 与 Skill Library，实行局部原子 Patch |
| **RHI** | 优化上下文流比加算力更省钱更强 | 盲目堆叠大模型或长思考链导致成本激增 | 记录版本间 Pairwise 差异分析，提升信息流密度，降本 60% |
