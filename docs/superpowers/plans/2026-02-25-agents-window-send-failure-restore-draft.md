# Agents 窗口发送失败时自动恢复 draft session

> 范围：VS Code Agents 窗口（sessions window）的新会话 composer。
> 现象：用户在新会话输入框写好 prompt、挂好附件，点 Send；若
> `sendNewChatRequest` 因网络/模型/权限等原因抛错，输入框被清空、
> 附件被清空、draft 持久化状态也被清空——用户必须重打一遍。

## 根本原因（Root Cause）

发送链路涉及两个文件，失败时各自的清理不对称：

### 1. `newChatInput.ts` — `NewChatInputWidget._send()`

路径：`vscode/src/vs/sessions/contrib/chat/browser/newChatInput.ts`

```
_send():
  读 query / attachments
  _history.append(draft)        // ← 草稿进历史
  _clearDraftState()            // ← 立即清空 storage 持久化 + _draftState
  _sending = true; editor 只读
  try {
    await options.sendRequest(...)   // ← 抛错进入 catch
    _contextAttachments.clear()      // 成功才执行
    editor.setValue('')              // 成功才执行
  } catch (e) {
    logService.error(...)            // ← 只打日志，不恢复
  }
  _sending = false; editor 可写
```

问题：
- `_clearDraftState()` 在 `await` **之前**就把 storage 里的 draft 清空了，
  导致窗口重载也找不回内容。
- 成功路径清空 editor/附件，失败路径却**没有把它们还原**——编辑器仍
  保留着旧文本（因为成功路径的 `setValue('')` 没执行），但
  `_contextAttachments` 状态、`_draftState`、history overlay 已被改动。
- 失败后用户看到的是：文本还在但发送按钮可能状态错乱、附件丢失、
  storage draft 为空。

### 2. `newChatWidget.ts` — `NewChatWidget._send()`

路径：`vscode/src/vs/sessions/contrib/chat/browser/newChatWidget.ts`

```
_send():
  session = this._session.get()
  try {
    await sessionsManagementService.sendNewChatRequest(session, ...)
  } catch (e) {
    logService.error(...)
    // 重新建一个 draft session，让 composer 不卡死
    if (folderUri && !background) this._createNewSession(folderUri)
  }
```

这里已经做了"重建 draft session"（恢复 `canSendRequest`），但**没有
把 query/attachments 传回给 input widget**。重建 session 会让
`NewChatInputWidget` 的 `session` observable 变化，但 widget 内部的
编辑器内容和附件模型并未被重新填充。

### 3. `sessionsManagementService.sendNewChatRequest()`

路径：`vscode/src/vs/sessions/services/sessions/browser/sessionsManagementService.ts`

前台发送：
```
this._newSession.set(undefined, undefined)   // 先摘掉 pending 指针
await provider.createNewChat(...)
await provider.sendRequest(...)              // ← 抛错后 pending 指针已丢
```

失败时 `_newSession` 已经被置空，但 provider 侧的 draft session 是否
被释放取决于 provider 实现。`newChatWidget._send` 的 catch 调
`_createNewSession` 重建，旧的失败 session 由 provider 自行清理。
**这一层不需要改逻辑**，但它解释了为什么 widget 层必须重建 session。

## 目标（Goal）

- 发送失败时，composer 的**文本**和**附件**原样保留在输入框。
- 发送失败时，**draft 持久化状态**（storage `sessions.draftState`）不被
  提前清空，保证窗口重载/崩溃后仍可恢复。
- 发送失败时，**draft session** 被重建（现有逻辑保留），且重建后
  input widget 的内容不闪烁、不丢失。
- 成功路径行为不变：清空编辑器、清空附件、清空 storage draft。
- 后台发送（background / Alt+Enter）行为不变：fire-and-forget，不在
  此修复范围（它本来就立即 reseed 一个空 draft）。

## 非目标（Non-goals）

- 不重试发送（无自动重试、无指数退避）。
- 不改动已有会话内 follow-up 消息的发送（那走 `ChatWidget.acceptInput`，
  不是 new-session composer）。
- 不改动 agent host delegation（`agentHostDelegation.ts`）。
- 不改动 `sessionsManagementService` 的事件/清理逻辑。
- 不引入新的 storage key。

## 涉及文件

| 文件 | 改动类型 | 说明 |
|---|---|---|
| `vscode/src/vs/sessions/contrib/chat/browser/newChatInput.ts` | 修改 | `_send()` 调整草稿清理时机；catch 中恢复附件；新增 `restoreDraft()` 公开方法 |
| `vscode/src/vs/sessions/contrib/chat/browser/newChatWidget.ts` | 修改 | `_send()` catch 中在重建 session 后调用 input 的恢复方法 |
| `vscode/src/vs/sessions/services/sessions/test/browser/sessionsManagementService.test.ts`（可选参考） | 不改 | 参考现有测试风格 |
| 新增 `vscode/src/vs/sessions/contrib/chat/test/browser/newChatInputDraftRestore.test.ts` | 新增 | 单元测试 |

## 实现步骤

### Step 1：调整 `_clearDraftState()` 的调用时机

文件：`newChatInput.ts`

**当前**：在 `await sendRequest` 之前调用 `_clearDraftState()`。

**改为**：把 `_clearDraftState()` 从 await 前移到 **`try` 块内、
`await` 成功之后**，和 `_contextAttachments.clear()` /
`editor.setValue('')` 放在一起。

理由：storage draft 是"崩溃恢复"的安全网。只有当请求**真正被 provider
接受**（await 成功返回）时才丢弃它。await 抛错时 storage 里的 draft
完好无损，重载窗口即可恢复。

注意点：
- `_history.append()` 仍在发送前执行（历史记录的是"用户尝试发送的内容"，
  即使失败也应有记录，可用 ↑ 召回）。
- `_draftState` 内存字段在发送前是否清空需谨慎：`_updateDraftState()`
  在编辑器 `onDidChangeModelContent` 时会重建它。失败后编辑器文本仍在，
  下一次输入会重建。但为了 catch 中能访问到原始附件，应在发送前
  **用局部变量快照** `query` 和 `attachments`（已经有了），不依赖
  `_draftState`。

### Step 2：在 catch 中恢复附件

文件：`newChatInput.ts`，`_send()` 的 catch 块

当前 catch 只 log。改为：

```ts
catch (e) {
  this.logService.error('Failed to send request:', e);
  // 恢复附件：发送前已从 _contextAttachments 读出快照，
  // 但 widget 内部附件模型可能已被其他流程改动，重新 set 回去。
  if (attachedContext?.length) {
    this._contextAttachments.setAttachments(attachedContext);
  }
  // 编辑器文本不需要手动恢复——成功路径的 setValue('') 在 try 内，
  // 失败时不会执行，文本天然保留。
}
```

附件恢复用 `NewChatContextAttachments.setAttachments()`（已存在，
`_restoreState()` 也用它）。传入的是发送前快照 `attachedContext`，
其元素类型是 `IChatRequestVariableEntry`，可直接传给 `setAttachments`
（`_restoreState` 里走的是 `.fromExport()`，因为从 storage 读出来是
plain object；这里是内存快照，不需要 fromExport）。

### Step 3：暴露 `restoreDraft` 供 widget 调用

文件：`newChatInput.ts`

`NewChatWidget._send()` 的 catch 会在失败后调 `_createNewSession()`，
这会让 `NewChatInputWidget` 的 `session` observable 切换到新的 draft
session。session 切换本身不清空编辑器（没有 observer 做这件事），
但为了语义清晰、并防御未来 session 切换逻辑变动，新增一个公开方法：

```ts
/**
 * 在发送失败后由外部（NewChatWidget）调用，确保输入框内容和附件
 * 仍处于可编辑状态。当前实现下编辑器文本天然保留，此方法主要用于
 * 防御性恢复 + 重新聚焦输入框。
 */
restoreFailedDraft(query: string, attachments: IChatRequestVariableEntry[] | undefined): void {
  // 文本：若编辑器已被外部清空（防御），用快照恢复
  const model = this._editor?.getModel();
  if (model && model.getValue() === '' && query) {
    model.setValue(query);
  }
  if (attachments?.length) {
    this._contextAttachments.setAttachments(attachments);
  }
  // 确保 draft 持久化状态反映当前编辑器内容
  this._updateDraftState();
  this.saveState();
  this._editor?.focus();
}
```

### Step 4：在 `NewChatWidget._send()` 的 catch 中串联恢复

文件：`newChatWidget.ts`，`_send()` 方法

当前 catch：
```ts
} catch (e) {
  this.logService.error('Failed to send request:', e);
  const folderUri = this._workspacePicker.selectedFolderUri;
  if (folderUri && !background) {
    this._createNewSession(folderUri);
  }
}
```

改为：
```ts
} catch (e) {
  this.logService.error('Failed to send request:', e);
  const folderUri = this._workspacePicker.selectedFolderUri;
  if (folderUri && !background) {
    this._createNewSession(folderUri);
  }
  // 重建 session 后恢复输入内容。_send 已持有 query/attachedContext 快照。
  this._newChatInput.restoreFailedDraft(query, attachedContext);
}
```

注意：`query` 和 `attachedContext` 是 `_send` 的参数，直接可用。
`_createNewSession` 是同步的（内部 `sessionsService.openNewSession`），
先重建再恢复，顺序保证 `canSendRequest` 在恢复前已重新变 true。

### Step 5：处理后台发送（background）的边界

background 发送是 fire-and-forget，`newChatWidget._send` 中 await 立即
resolve（management service 不等待 provider），所以不会进 catch。
provider 侧失败由 `sessionsManagementService._sendNewChatRequestInBackground`
的 `.catch` 处理（dispose 掉孤立 session）。

**background 发送后 composer 已被 reseed 成空 draft**，用户已经继续
写下一条消息，不应恢复旧内容。因此 Step 4 的恢复仅在
`!background` 分支有效——这已由现有 `if (folderUri && !background)`
判断保证。`restoreFailedDraft` 也只在该分支后调用。

无需额外改动。

### Step 6：单元测试

新增文件：
`vscode/src/vs/sessions/contrib/chat/test/browser/newChatInputDraftRestore.test.ts`

测试用例（用 `workbenchTestServices` + instantiation service，参考
`newChatInput` 相关测试风格；若无现成测试则用最小 mock）：

1. **发送失败后编辑器文本保留**
   - 设置 editor 内容为 "build a rocket"，调 `_send()`
   - mock `sendRequest` reject
   - assert：editor.getValue() === "build a rocket"

2. **发送失败后附件保留**
   - 添加一个 file attachment
   - mock `sendRequest` reject
   - assert：`_contextAttachments.attachments.length === 1`

3. **发送失败后 storage draft 未被清空**
   - 触发 `saveState()` 写入 storage
   - 调 `_send()`，mock reject
   - assert：`storageService.get('sessions.draftState')` 仍包含原文本

4. **发送成功后行为不变**
   - mock `sendRequest` resolve
   - assert：editor 为空、附件清空、storage draft 清空

5. **`restoreFailedDraft` 防御性恢复**
   - 手动清空 editor
   - 调 `restoreFailedDraft("hello", [])`
   - assert：editor.getValue() === "hello"

### Step 7：手动验收

1. 断网或用一个会抛错的 provider（可临时让 `sendRequest` throw）。
2. Agents 窗口新会话输入 "test draft restore"，挂一个文件附件。
3. 点 Send。
4. 验证：
   - 输入框仍显示 "test draft restore"，文件附件 pill 仍在。
   - 发送按钮恢复可点击（不卡在 loading）。
   - DevTools Console 有 error 日志但无未处理 Promise rejection。
   - 重新加载窗口（workbench.action.reloadWindow）后输入内容仍在。
5. 恢复网络后点 Send，消息正常发送，输入框清空。
6. 验证 Alt+Enter（background）行为不变：后台发送后 composer 立即清空
   并 reseed，失败不弹回旧内容。

## 验收标准（Acceptance Criteria）

- [ ] 前台发送失败时，输入框文本原样保留。
- [ ] 前台发送失败时，已添加的附件（file/image 等 pill）原样保留。
- [ ] 前台发送失败时，storage 中 `sessions.draftState` 仍包含失败时的
      文本和附件，reload window 后可恢复。
- [ ] 前台发送失败时，发送按钮 loading 状态复位、可再次点击。
- [ ] 前台发送失败时，draft session 被重建（现有行为不回归），
      `canSendRequest` 恢复 true。
- [ ] 前台发送成功时，输入框/附件/storage 全部清空（行为不回归）。
- [ ] 后台发送（Alt+Enter）行为不回归：成功后 composer 清空并 reseed，
      后台失败不影响当前 composer。
- [ ] 新增单元测试全部通过。
- [ ] `npm run compile`（或 `scripts/compile-vscode.ps1`）通过，无
      Error marker。
- [ ] 历史记录（↑ 键）仍可召回本次失败的输入（`_history.append` 不回归）。

## 风险与注意事项

1. **附件对象身份**：`setAttachments` 会替换整个附件数组。发送前快照
   `attachedContext` 是通过 `[...this._contextAttachments.attachments]`
   复制的（在 `_send` 中），元素引用相同。恢复时复用这些引用是安全的，
   因为发送流程不会 mutate 附件对象本身。

2. **slash command 路径**：`_send` 中若 `tryExecuteSlashCommand` 命中，
   会 `setValue('')` 并 return，不进入 sendRequest——这条路径不受影响，
   也不涉及失败恢复。

3. **`_sending` 重入**：失败后 `_sending` 被复位为 false，用户可立即
   重发。恢复逻辑不应把 `_sending` 留成 true。

4. **storage 写入时机**：当前 `saveState()` 由外部（`NewChatWidget.saveState`
   /视图生命周期）调用。Step 3 在 `restoreFailedDraft` 中显式调
   `saveState()`，确保恢复后立即落盘，不依赖下次 blur 或卸载。

5. **编码**：本注释/文案均为英文代码注释，无中文 commit message 编码
   风险；若 commit message 含中文，走 AGENTS.md Appendix A 的
   Python `commit-tree` 路径。
