# 2026-09-17 · Mobius Agent 无限工具调用循环（manage_todo_list 刷屏）

## 症状

部分请求（不是全部）进入 Agent 模式后，界面反复出现：

```
Finished with 1 step          <- chatThinkingContentPart 的思考气泡
  ● 我陷入了无限循环……我必须输出最终答案，不带任何工具调用。
manage_todo_list done
```

模型自己在思考里明确说「我要停止调用工具、直接输出最终答案」，但仍**每一轮都发出一个工具调用**，直到用户手动停止。循环长度随 turn budget 决定（源码当前 `RUNAWAY_TOOL_TURN_GUARD = 100000`，等于不会自然结束）。

## 根因

主循环在 `vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts` 的 `for (let turn = 0; turn < turnBudget; turn++)`。

### 1. `tool_choice='required'` 死锁（主因）

```ts
const requireNativeTools = !forceTool && (
    forceRequiredTools
    || (untilDoneIntent && codeChangeIntent && toolStats.writeSuccess === 0)
);
```

`requireNativeTools === true` 时 `_streamOnce` 传的是 `tool_choice: 'required'`。

- `untilDoneIntent && codeChangeIntent && writeSuccess === 0` 在**每一轮**都为真，只要「判定为改代码的任务」一直没写文件。
- 典型触发：用户问的是「为什么/排查/某个 cell 用的什么参数」，意图分类器仍判成 `codeChangeIntent`；模型认为这是**回答问题**、不需要改文件，于是 `writeSuccess` 永远是 0。
- `tool_choice: 'required'` 从协议层**禁止**纯文本回复 —— 模型无法输出最终答案，只能不断挑一个最"便宜"的工具调用。`manage_todo_list`（无副作用、参数简单、还符合系统提示里「VERY frequently」的要求）成了默认选择。
- 这与截图完全吻合：思考里在说「我要输出答案」，动作上却永远是工具调用。

### 2. 工具执行路径没有任何"无进展"断路器

`!toolUses.length` 的分支里有大量基于**文本信号**的 nudge（`asksToContinueNextTurn` / `looksLikeRemainingWork` / `looksLikeIncompleteHandoff` …），但一旦模型发出工具调用，就走进「执行工具 → continue」路径，那里只检查：

- 搜索失败次数（`MAX_SEARCH_FAILURE_NUDGES`）
- dead-end 工具失败次数（`MAX_DEAD_END_TOOL_NUDGES`）
- `stallWithTools`（**同样要求文本信号**）

空文本 + 成功返回的 no-op 工具 = 三个检查全部不命中 → 无限循环。`_trackToolOutcome` 也只统计写文件，`manage_todo_list` 完全不进统计。

### 3. turn budget 事实上无上限

`RUNAWAY_TOOL_TURN_GUARD = 100000`（提交 `2d5fcc9cd8d` 从 500 抬到 100000，为了"别中途打断真实任务"）。意图可以理解，但它让上面两个缺陷没有任何兜底。

## 目标

1. 让「模型只想回答、却被 `tool_choice='required'` 卡住」的请求能自然收敛到最终答案。
2. 让「同一个工具 + 同一参数」连续重复、以及「只改写未变化的 todo 列表」这类零进展循环在 3 轮内终止。
3. 不削弱正常编码任务的执行能力（长跑、多次编辑、终端重试不受影响）。

## 非目标

- 不调低 `RUNAWAY_TOOL_TURN_GUARD`（保留"不中途打断真实任务"的既有约定）。
- 不改 todo 工具本身的 schema / 提示词。
- 不改 Continue GUI 的渲染。

## 任务

1. 常量：`MAX_IDENTICAL_TOOL_REPEATS = 2`、`MAX_NO_PROGRESS_CONTROL_TURNS = 2`、`MAX_FORCED_TOOL_TURNS_NO_WRITE = 6`；新增 `STUCK_TOOL_LOOP_NUDGE` 并登记进 `NUDGE_ECHO_SIGNATURES` / `INJECTED_NUDGES`（否则会被当成"回声"误剥）。
2. `requireNativeTools` 增加 `forcedToolTurns < MAX_FORCED_TOOL_TURNS_NO_WRITE` 上限；写文件成功后计数器归零（允许后续继续强制编辑）。
3. 工具执行 for 循环之后插入断路器：
   - 计算本轮工具签名 `name:<sorted-key JSON args>`（排除 `run_in_terminal` / `get_terminal_output` / `get_errors` 等可合法重复的"易变"工具），与上一轮相同则 `identicalToolRepeats++`。
   - 本轮全是 `manage_todo_list` 且 todo 内容与上一轮完全一致则 `noProgressControlTurns++`。
   - 任一超阈值 → 记日志 + UI warning + `needsFinalAnswer = true` + 注入 `STUCK_TOOL_LOOP_NUDGE` + `break`。
   - `break` 后由既有 `_forceFinalAnswer`（`tool_choice:'none'`）保证一定产出可见回答。
4. 新增 `stableToolParameters()`（按键排序的 JSON）辅助函数，避免参数键序不同导致签名判定失效。

## 验收标准

- `manage_todo_list` 连续 3 轮同参数调用 → 第 3 轮后停止工具、输出最终答案。
- 连续 3 轮只改写未变化的 todo 列表 → 同上。
- 「只想回答」的被判为改代码的请求：最多 6 轮强制工具后放开 `tool_choice`，模型可以给出答案。
- 终端重试（同一命令连跑 2 次）不会误判。
- `npm run typecheck-client` 无新增错误。

## 交付

- 源码：`vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts`（vscode 子模块提交）。
- 已安装 IDE：`%LOCALAPPDATA%\Programs\Mobius\resources\app\out\vs\workbench\workbench.desktop.main.js` 热补丁（同一逻辑，先备份）。
