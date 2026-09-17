# 2026-09-17 · Replace String / Multi Replace 工具调用失败

## 症状

Mobius Agent 里两个编辑工具经常失败，工具行只显示 `Replace String failed` / `Multi Replace failed`，**看不到原因**。失败的后果是模型反复重读文件、来回追问「前面的编辑到底生效了没有」。

## 取证

工具挂起后能在 `%APPDATA%\Mobius\User\workspaceStorage\<hash>\chatSessions\*.jsonl` 里找到完整会话（含模型思考），对近两周会话做错误文本统计：

| 次数 | 错误 | 说明 |
| --- | --- | --- |
| 13 | `string not found in file` | 模型给的 old_string 过期/是它自己臆造的 |
| 2 | `old_string and new_string must be different` | **其中一行是 no-op，却整批失败** |
| 1 | `appears N times in the file` | 命中多处 |
| 1 | `Could not apply edit_existing_file ... deterministically` | diff 形式不被支持 |

模型自己的思考暴露了第二类问题（原文摘录）：

> 「The second edit was a no-op mistake (same old/new). Let me remove the `recent` line…」
>
> 「edits 0 and 1 may have been applied or not? … the tool likely uses transactional semantics…」

## 根因（工具侧，可修）

`continue/core/edit/searchAndReplace/` + `continue/extensions/vscode/src/agent/continueAgentPatchTools.ts`：

1. **一行 no-op 拖垮整批**。`validateMultiEdit()` 对每一行都调 `validateSingleEdit()`，而后者对 `old_string === new_string` 直接抛错 → 整个 `multi_edit` 被拒，其余正确的行也全部丢弃。模型只是"多写了一行没意义的替换"，代价却是整批失败。
2. **全有或全无，但报错从不说**。`executeMultiFindAndReplace()` 在内存里顺序应用，只有全部成功才写盘 → 第 2 行失败时文件其实**完全没动**。可是错误只说 `Edit at index 2: string not found`，没说「文件未改动」，也没说其它行有没有写入。模型的思考里明确在猜「0 和 1 到底应用了没有」。
3. **只报第一个失败行**。模型要修 3 处不匹配，就得「失败→重读→再提交」循环 3 次。
4. **UI 只显示 "failed"**。真正的原因在折叠的 `errorMessage` 里，标题行是空的，用户看到的就是截图里那句没有信息量的 `Replace String failed`。

## 目标

1. 一行 no-op 不再让整批失败（丢弃该行并如实回报）。
2. `multi_edit` 失败时**一次列出所有失败索引与原因**，并明确声明文字「文件未被改动」。
3. 编辑失败时把原因显示在工具行标题上。
4. 不改单行 `replace_string_in_file` 的严格校验（old===new 仍然报错，语义正确）。

## 非目标

- 不做「部分应用」（all-or-nothing 是更安全的事务语义，保留）。
- 不改 `findSearchMatch` 的匹配策略（09-11 的 CRLF 修复已生效，已核对已安装 `extension.js` 内含 `lineEndingNormalizedMatch`）。
- 不去修模型的 old_string 过期问题（那是模型行为，工具只能给出更好的报错）。

## 任务

1. `multiEditValidation.ts`：跳过 `old_string === new_string` 的行，返回 `skippedNoOps: number[]`；全部行都是 no-op 时抛 `FindAndReplaceIdenticalOldAndNewStrings`（保留原语义）。空 `old_string` 的「只有第一行可插入」检查改为按**存活行**位置判断。
2. `performReplace.ts`：新增 `simulateMultiFindAndReplace()` 先整批试算，收集所有 `{index, reason, message}`；`executeMultiFindAndReplace()` 有失败则抛聚合错误，文案一次列出全部失败行并声明「NO edits were written and the file is unchanged」。抛出的 `reason` 取第一个失败行（保持既有 reason 契约）。
3. `continueAgentPatchTools.ts`：`applyMultiEdit` 结果文案带上被跳过的 no-op 行序号；`patchFailureResult` 补一句「No changes were written — the file is unchanged」。
4. `continueChatAgent.ts`：新增 `formatToolFailureSuffix()`，把首个非空错误行拼进 `pastTenseMessage`。
5. 测试：`multiEdit.vitest.ts` 新增 4 个用例（丢弃 no-op 行、全 no-op 仍报错、聚合报错同时覆盖成功/失败索引、simulate 不修改入参）。

## 验收标准

- `cd continue/core && ./node_modules/.bin/vitest run edit/searchAndReplace` → 168 passed。
- `tsgo --project src/tsconfig.json --noEmit`（vscode）→ exit 0；改动的 4 个文件在 continue 扩展 `tsc -p ./ --noEmit` 下无新增错误。
- 已安装 Mobius 重建 `out/extension.js` 后热替换，重启即生效。

## 交付

- 源码：`continue/core/edit/searchAndReplace/{performReplace,multiEditValidation,multiEdit.vitest}.ts`、`continue/extensions/vscode/src/agent/continueAgentPatchTools.ts`、`vscode/src/vs/workbench/contrib/continue/browser/continueChatAgent.ts`。
- 部署：`node scripts/esbuild.js` 重建 `extension.js`，备份后覆盖已安装 Mobius 的同名文件。
