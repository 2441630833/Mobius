# 本机更新 Mobius 到最新发布（无需 github.com）

> 背景：这台机器直连 `github.com:443` 会超时（`git push` 直接失败），
> 但 `api.github.com` 是通的。所以更新流程完全走 GitHub REST API：
> `api.github.com` → 302 → `objects.githubusercontent.com`，实测可下 900 MB 级安装包。

---

## 1. 一条命令

```powershell
cd E:\MobiusCode\Mobius
powershell -ExecutionPolicy Bypass -File .\scripts\update-mobius-local.ps1
```

或者双击 `tools\mobius-更新到最新版.cmd`（会先检查 Mobius 是否已退出）。

脚本做的事：

1. `GET /repos/2441630833/Mobius/releases/latest` 解析目标版本；
2. 下载 **增量补丁**（`Mobius-Patch-*-win32-x64.zip`，约 33 MB），
   没有补丁或应用失败则回退 **官方安装器**（`MobiusSetup.exe`，约 930 MB）；
3. 用发布里的 `SHA256SUMS.txt` 校验，不一致直接中止；
4. 调用 `scripts/apply-delta.ps1` 应用补丁（带备份与失败回滚）；
5. 重新部署会话维护热补丁（`scripts/hotpatch-session-maintain.ps1 -Apply -RegisterTasks`）；
6. 打印更新前后的版本。

## 2. 常用参数

```powershell
# 只看会下载什么，不下载不安装
.\scripts\update-mobius-local.ps1 -DryRun

# 指定版本 + 强制用增量补丁（失败就报错，不回退安装器）
.\scripts\update-mobius-local.ps1 -Tag v1.0.23 -Mode patch

# 直接重装官方安装器（补丁坏了、或想彻底覆盖时）
.\scripts\update-mobius-local.ps1 -Mode setup

# 自定义安装目录（装在别处时）
.\scripts\update-mobius-local.ps1 -InstallDir 'D:\Apps\Mobius'
```

| 参数 | 说明 |
| --- | --- |
| `-Tag` | 目标发布标签，留空 = latest |
| `-Mode` | `auto`（默认）/ `patch` / `setup` |
| `-Force` | Mobius 还在跑也继续（不推荐） |
| `-DryRun` | 只解析与打印 |
| `-SkipHotpatch` | 更新后不重装维护热补丁 |

## 3. 前置条件

- **Mobius 必须完全退出**（含托盘），否则文件被占用，补丁会失败。
  检查：`Get-Process Mobius`
- 首次运行需要能读到一个 GitHub token：优先 `GH_TOKEN` / `GITHUB_TOKEN` 环境变量，
  否则自动从 Git Credential Manager 存的 `git:https://github.com` 凭据里取。
  已验证该凭据有 `push`/`admin` 权限，足够读发布与前程。

## 4. 触发一次新的云端编译

`git push` 走不通时，用 workflow_dispatch 一样能编译：

```powershell
# 触发 build-windows.yml（main 分支，x64/user，并发布到 v1.0.23）
.\scripts\mobius-actions.ps1 -Action Dispatch -Workflow build-windows.yml -Ref main -ReleaseTag v1.0.23

# 看步骤级进度
.\scripts\mobius-actions.ps1 -Action RunInfo -RunId 43171546845

# 等它跑完并列出产物
.\scripts\mobius-actions.ps1 -Action Wait -Workflow build-windows.yml -RunId 43171546845

# 下载某次 run 的产物到 dist\actions-<id>\
.\scripts\mobius-actions.ps1 -Action Download -RunId 43171546845
```

| Action | 作用 |
| --- | --- |
| `Auth` | 验证 token、仓库权限、可见工作流 |
| `Status` | 某工作流最近 5 次运行 |
| `RunInfo` | 单次运行的 job / step 级进度 |
| `Dispatch` | 触发 `workflow_dispatch` |
| `Wait` | 轮询到结束，列出产物，失败时指出是哪个 step |
| `Download` | 下载 run 产物并解压 |
| `Releases` | 列出发布与资产 |
| `DownloadRelease` | 按 tag 下载资产并校验 SHA256 |

## 5. 为什么 `git push` 会失败

```
fatal: unable to access 'https://github.com/2441630833/Mobius/': Failed to connect to github.com:443
curl https://github.com  -> 000 (超时)
curl https://api.github.com -> 200 (0.4s)
```

`github.com` 与 `api.github.com` / `objects.githubusercontent.com` 在当前网络下可达性不同。
所以：**代码同步用 API，编译用 workflow_dispatch，下载用 release asset API**，
整条链路不需要 `github.com` 直连，也不需要 `gh` CLI（本机没装）。

本地已提交但未推送的提交，等 `git push` 恢复后再推，或用
`gh api repos/{owner}/{repo}/contents/{path}` 走 API 写回；不要为了推送去改历史。