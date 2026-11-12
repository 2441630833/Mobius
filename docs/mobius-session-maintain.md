# Mobius 会话自动化维护

> 解决的问题：会话越长、越多，Mobius 启动时要把所有 `*.jsonl` 解析一遍建索引，
> 还要把 `state.vscdb`（会话索引 + 编辑记录）整块读进内存。
> 单会话 7 MB、会话数 260+、`state.vscdb` 157 MB 时，进程能爬到 5.7 GB 然后卡死。

这套工具把"体检 → 归档瘦身 → 日志轮转 → 数据库压缩"自动化，并且默认**只在超阈值时才动手**。

---

## 1. 文件组成

| 文件 | 作用 |
| --- | --- |
| `tools/mobius-auto-maintain.ps1` | 核心维护脚本，`Check` / `Clean` / `Auto` 三个模式 |
| `tools/Install-MobiusAutoMaintain.ps1` | 注册 Windows 计划任务（`-Install` / `-Status` / `-Uninstall`） |
| `tools/mobius-体检.cmd` | 双击体检（只读） |
| `tools/mobius-清理演练.cmd` | 双击演练（`-Mode Clean -DryRun`，不删任何文件） |
| `tools/mobius-一键清理.cmd` | 双击真清理（二次确认） |
| `tools/mobius-开启自动化.cmd` | 双击注册计划任务并立刻体检一次 |
| `scripts/hotpatch-session-maintain.ps1` | 热补丁：部署 / 校验 / 卸载 / 打包 |

---

## 2. 阈值（与《Mobius 会话清理指南》一致）

| 指标 | 该处理了 |
| --- | --- |
| 会话文件数 | `> 250` 个 |
| 会话合计大小 | `> 500 MB` |
| `state.vscdb` | `> 150 MB` |
| 单进程内存 | `> 2 GB`（立刻保存并重启） |
| 最大单会话 | `> 8 MB`（长对话建议另开新会话） |

结论分三档：

- **健康**：全部在阈值内，什么都不做。
- **留意**：命中 1~2 项，建议本周内跑一次 `-Mode Clean`。
- **风险**：命中 3 项以上，或单进程内存超 2 GB —— 立刻保存工作、重启 Mobius，再清理。

退出码：`0`=健康 `1`=留意 `2`=风险 `3`=已执行清理 `4`=出错。

---

## 3. 日常用法

```powershell
# 只体检（永远不动文件）
powershell -ExecutionPolicy Bypass -File .\tools\mobius-auto-maintain.ps1 -Mode Check

# 演练：打印将要归档的清单，不删不改
powershell -ExecutionPolicy Bypass -File .\tools\mobius-auto-maintain.ps1 -Mode Clean -DryRun

# 真清理（建议先完全退出 Mobius，这样 state.vscdb 才能压缩）
powershell -ExecutionPolicy Bypass -File .\tools\mobius-auto-maintain.ps1 -Mode Clean

# 自定义阈值 / 归档目录
powershell -ExecutionPolicy Bypass -File .\tools\mobius-auto-maintain.ps1 -Mode Auto `
    -MaxSessions 200 -MaxStateMB 120 -ArchiveRoot D:\MobiusArchive
```

`-Mode Auto` = 先体检，命中阈值才执行清理。计划任务用它。

---

## 4. 清理策略与安全保证

1. **保留集**：最新 `-KeepMinSessions 120` 个会话永不动；最近 `-ProtectRecent 3` 个再单独加保护（正在用的对话即使巨大也不归档）。
2. **归档条件**（命中任一）：会话数超 `-MaxSessions`；早于 `-KeepDays 45`；单文件超 `-MaxSingleSessionMB 8`。
3. **先归档后删除**：写入 `%USERPROFILE%\MobiusArchive\sessions-<时间戳>.zip`，
   **回读校验 zip 条目数**，一致才删原件；同时落 `.manifest.json`（原路径 / 大小 / 修改时间）。
4. **日志轮转**：`*.log` 超过 `-MaxLogMB 40` 就打包到 `logs-<时间戳>.zip` 后删除。
5. **数据库压缩**：`state.vscdb` 超过 `-MaxStateMB 150` 时执行 `VACUUM INTO`（优先 `sqlite3.exe`，没有就用 Python 内置 `sqlite3`），
   成功后原件留一份 `.bak`。**Mobius 正在运行时会自动跳过**（除非 `-Force`）。
6. **归档自轮转**：`MobiusArchive` 里超过 `-ArchiveKeepDays 120` 天的 zip / json 自动删除。
7. 所有动作写入 `%USERPROFILE%\MobiusArchive\maintain.log`，每次运行生成
   `reports\report-<时间戳>.json` 并更新 `last-report.json`。

> 还原：把 `MobiusArchive\sessions-*.zip` 解压回 `%APPDATA%\Mobius\User\workspaceStorage\<id>\chatSessions\` 即可；
> 名字冲突时 zip 内会带 `_1` 后缀，用 manifest 里的 `path` 字段对应原名。

---

## 5. 计划任务（真正的"自动化"）

```powershell
# 注册：每天 12:30 体检、登录后 3 分钟体检、每周日 13:00 深度清理
powershell -ExecutionPolicy Bypass -File .\tools\Install-MobiusAutoMaintain.ps1 -Install -RunNow

# 再加一个每 30 分钟的看门狗（只体检，用于观察内存爬升）
powershell -ExecutionPolicy Bypass -File .\tools\Install-MobiusAutoMaintain.ps1 -Install -Watchdog

# 查看状态 + 最近一次报告
powershell -ExecutionPolicy Bypass -File .\tools\Install-MobiusAutoMaintain.ps1 -Status

# 全部卸载
powershell -ExecutionPolicy Bypass -File .\tools\Install-MobiusAutoMaintain.ps1 -Uninstall
```

| 任务名 | 触发 | 参数 |
| --- | --- | --- |
| `MobiusAutoMaintain-Daily` | 每天 12:30 | `-Mode Auto -Quiet` |
| `MobiusAutoMaintain-Logon` | 登录后 3 分钟 | `-Mode Auto -Quiet` |
| `MobiusAutoMaintain-Weekly` | 每周日 13:00 | `-Mode Clean -IncludeHistory -Quiet` |
| `MobiusAutoMaintain-Watchdog` | 每 30 分钟（可选） | `-Mode Check -Quiet` |

全部以当前用户身份运行，不需要管理员权限；窗口隐藏，结果看 `maintain.log`。

---

## 6. 热补丁

把工具部署进**已安装的 Mobius**（`%LOCALAPPDATA%\Programs\Mobius\resources\app\mobius-maintain\`），
这样升级应用后重跑一次即可，也可以打包分发给别的机器。

```powershell
# 部署（覆盖旧版本）；要顺带注册计划任务就加 -RegisterTasks
powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-session-maintain.ps1 -Apply -RegisterTasks

# 校验：文件是否齐全、SHA256 是否与清单一致、任务是否在册（只读）
powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-session-maintain.ps1 -Verif

# 卸载（目录 + 计划任务；归档目录保留）
powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-session-maintain.ps1 -Uninstall

# 打包分发包
powershell -ExecutionPolicy Bypass -File .\scripts\hotpatch-session-maintain.ps1 -MakeDist
```

产物：

- 部署清单：`<install>\mobius-maintain\HOTPATCH.json`（版本 / 时间 / 每个文件的 SHA256）
- 分发包：`dist\mobius-maintain-hotpatch-v<版本>.zip`
  - 解压后双击 `install.cmd` = `-Apply -RegisterTasks`
  - 双击 `verify.cmd` = `-Verif`
  - `CHECKSUMS.json` 可离线核对文件完整性

热补丁只新增目录与计划任务，**不改动** Mobius 的 JS bundle，因此与应用升级互不冲突；
不需要时 `-Uninstall` 即可完全回退。

---

## 7. 排查

| 现象 | 处理 |
| --- | --- |
| `找不到 Mobius 数据目录` | 用 `-DataRoot "C:\Users\<你>\AppData\Roaming\Mobius\User"` 指定 |
| 会话文件数明显偏少 | 会话按 workspace 分目录，脚本已合并统计所有 `chatSessions`；若换了名字，用 `-DataRoot` 指向真实目录 |
| `state.vscdb 压缩跳过` | 先完全退出 Mobius（托盘里也要退），再跑 `-Mode Clean` |
| `未找到 sqlite3.exe / python` | 装 Python 或把 `sqlite3.exe` 放到 PATH，其余清理动作不受影响 |
| 中文显示乱码 | 脚本必须保存为 **UTF-8 with BOM**（PowerShell 5.1 按 ANSI 读无 BOM 文件会乱码并报语法错） |
| 计划任务没跑 | `Get-ScheduledTaskInfo -TaskName MobiusAutoMaintain-Daily` 看上次结果；`maintain.log` 看详情 |

---

## 8. 为什么这样就能不卡

- 启动时解析的会话数量被钉在上限附近（默认最多 250 个、保留最新 120 个），索引耗时不再随历史线性膨胀。
- `state.vscdb` 定期 `VACUUM`，避免"删了数据但文件不缩"导致每次启动都整块读入大文件。
- 超大会话被识别并提示"另开新会话"，避免单个 7 MB 会话反复进入索引热点。
- 日志不再无限增长到 2 秒写 5 MB 把界面锁死。

> 另外建议把 `Log Level: Window` 从 `error` 改成 `off`（`Ctrl+,` 搜 `log level`），
> 出问题时不占 IO，还有时间保存并重启。