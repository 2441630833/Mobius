# 为什么有些会话"没有终端工具"（已修复）

## 现象

同一个 Mobius，有的会话里 Agent 明确说：**我能调用的工具只有 `manage_todo_list`**，
没有 `run_in_terminal`、没有读写文件的工具。于是它只能让你"自己跑一下命令再贴给我"。

模型没有说谎 —— 工作台真的只给了它这一个工具。

## 根因

工具开关是一个**按模式（mode）持久化**的状态，读取逻辑在
`vscode/src/vs/workbench/contrib/chat/browser/widget/input/chatSelectedTools.ts`：

```ts
if (!currentMap && currentMode.kind === ChatModeKind.Agent) {
    const modeTools = currentMode.customTools?.read(r);
    if (modeTools) {
        currentMap = ToolEnablementStates.fromMap(
            this._toolsService.toToolAndToolSetEnablementMap(modeTools, lm));
    }
}
```

而 `toToolAndToolSetEnablementMap([])` 的语义是 **"所有已注册工具 + 工具集全部 = false"**
（`languageModelToolsService.test.ts` 里写着 *Expected 0 tools to be enabled*）。

所以只要某个 agent 模式文件写了空清单：

```markdown
---
name: Plan
description: Generate an implementation plan without making edits.
tools: []
---
```

绑到这个模式的会话，**整张工具表就被清空了**，只剩 agent harness 自己注入的那几个
控制类工具（`manage_todo_list`）。表现就是"这个会话没有终端可用"。

这也解释了为什么是"**有的**会话"：

- 工具开关以 `mode.id` 为 key（`_sessionStates`），只在内存里，重启即失效；
- 但模式文件是磁盘上的，`tools: []` 每次都会重新生效；
- UI 早就不显示模式列表了，所以你没法看出"这个会话其实是 Plan 模式"，
  于是它看起来就像随机坏掉。

本仓库的 `.github/agents/Plan.agent.md` 正是 `tools: []`。
`Game/Chip/PPT` 没有写 `tools:`，所以它们没事 —— 只有 Plan 模式中招。

## 修复

### 1. 语义修复（根治）

`chatSelectedTools.ts`：空清单 = "没有限制"，不是"全部禁用"。

```ts
if (modeTools && modeTools.length > 0) { ... }
```

### 2. 兜底自愈

同一文件里增加 `MIN_ENABLED_TOOLS = 4`：任何会话如果算出来可用工具少于 4 个，
就当作状态损坏，整体重新启用（用户可以再手动关掉不想要的）。

### 3. 模式文件

- `.github/agents/Plan.agent.md`
- `vscode/src/vs/workbench/contrib/continue/mobius/agents/Plan.agent.md`

去掉 `tools: []`，改为在正文里用自然语言约束"优先只读工具"。

### 4. 顺带删除 Godot 智能体

`Game`（Godot）模式已下线：

- `continueMobiusBundledAgents.ts` 的 `MOBIUS_BUNDLED_AGENT_NAMES` 从
  `['Game', 'Chip', 'PPT']` 改为 `['Chip', 'PPT']`；
- 工作区与安装目录里的 `Game.agent.md` 改名为 `Game.agent.md.disabled`，
  这样还原历史会话时不会再命中 Game 模式、也不会再自动拉起 Godot 预览。

## 热补丁（无需重新打包）

安装版跑的是
`%LOCALAPPDATA%\Programs\Mobius\resources\app\out\vs\workbench\workbench.desktop.main.js`，
不会自动带上源码修复，所以提供两个脚本：

```powershell
# 1) 会话"只剩 manage_todo_list"的病灶：空 allowlist 语义 + 内置 Plan 模式文件
python scripts\patch-ide-agent-empty-tools.py --dry-run
python scripts\patch-ide-agent-empty-tools.py
python scripts\patch-ide-agent-empty-tools.py --revert   # 回滚

# 2) 排查工具开关的脏状态（当前未发现脏数据，留作诊断）
python scripts\hotpatch-agent-missing-tools.py --inspect
python scripts\hotpatch-agent-missing-tools.py --dry-run
```

脚本做的改动只有两处，且都会先备份：

| 目标 | 改动 |
| --- | --- |
| bundle | `c = mode.customTools?.read(r); c && (` → `c && c.length > 0 && (` （+12 字节） |
| `agents/*.agent.md` | 删掉 `tools: []` 这一行 |

改完**重启 Mobius**（或 `Developer: Reload Window`）生效。

## 验证

### 运行时数据路径（source → served）

渲染进程入口是 `out/vs/code/electron-browser/workbench/workbench.js`，它 `await import()`：

```js
let r;
h.env.VSCODE_DEV && globalThis._VSCODE_USE_RELATIVE_IMPORTS
  ? r = "../../../workbench/workbench.desktop.main.js"
  : r = new URL("vs/workbench/workbench.desktop.main.js", t).href; // t = `${appRoot}/out/`
let a = await import(r);
```

`resources/` 下没有 `app.asar`（只有 `app/` 目录），`resources/app/package.json` 的 `main`
是 `./out/main.js` —— 所以 `out/vs/workbench/workbench.desktop.main.js` 就是真正被加载的
那份代码，不存在"改了没生效的影子副本"。

实测：

- `out/vs/workbench/` 下只有 **1** 个 js：`workbench.desktop.main.js`，18039396 字节；
- 新写法 `customTools?.read(x);x&&x.length>0&&(` 命中 **1** 次，旧写法命中 **0** 次。

即 **served content == 修补后的源码语义**。窗口重载会重新 `import()` 该文件，补丁立即生效。

### 工具表消费端（确认根因唯一）

`vscode/src/vs/workbench/api/common/extHostChatAgents2.ts`：

```ts
for (const tool of this._tools.getTools(extension)) {
    if (typeof tools[tool.name] === 'boolean') {
        result.set(tool, tools[tool.name]);
    }
}
```

只有被 `userSelectedTools` **显式标为 true** 的工具才进 map；值为 `false` 或**键不存在**
都等于不可用。而 `entriesMap` 会为每个已注册工具写入布尔值，永远不可能返回空对象 ——
所以"整张表全 false"只有一条路径：**模式的 allowlist 为空**。

### 编译

`package.json` 的 `typecheck-client` 用的是 **tsgo**（`@typescript/native-preview`），不是
`tsc`；`npx tsc` 在 4GB 堆 OOM 是工具选错。

```
npx --no-install tsgo -p src/tsconfig.json --noEmit --skipLibCheck
EXIT=0  error-lines=0
```

两个改动的 `.ts` 文件 `get_errors` 同样为 0。

## 还留下的（未做）

- `entriesMap` 之外，`entriesScope` 仍会把 `customTools` 为空数组的模式判成
  `ToolsScope.Agent_ReadOnly`，只影响工具选择器的写回范围，不影响可用工具。
- 若以后还想要"真正的只读 Plan 模式"，应显式列出只读工具，而不是写 `tools: []`。