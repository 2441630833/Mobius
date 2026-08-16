# Upstream Rebase Guide

Mobius 使用 **submodule + 独立 fork** 的方式维护 `vscode` 与 `continue`，与 Cursor 团队的做法一致。上游同步在子模块内完成 `git rebase`，主仓库只记录子模块指针。另含只读参考子模块 `hermes-agent`（上游 [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent)），用于对照 agent 逻辑，一般不在其上做 Mobius 自定义分支。

## 恢复已完成

仓库已从「扁平目录」恢复为可正常 rebase 上游的结构：

| 子模块 | 原始 submodule 基点 | 自定义分支 | 自定义提交 |
|--------|----------------------|------------|------------|
| `vscode` | `43e100f3` | `mobius-custom` | `65c11ac1c4d` |
| `continue` | `d0a3c0b6` | `mobius-custom` | `c91cbb114` |

主仓库 submodule 恢复提交：`09caf313`

两个子模块均已验证可与上游找到共同祖先（`git merge-base` 正常）。

## 当前结构

```
Mobius/                       ← 主仓库（产品层）
├── .gitmodules
├── vscode/                   ← submodule @ mobius-custom
├── continue/                 ← submodule @ mobius-custom
├── hermes-agent/             ← submodule @ main（只读参考）
└── continue_backup_build/    ← 旧构建缓存（.gitignore，可删）
```

## 远程仓库

| 仓库 | URL | 分支 |
|------|-----|------|
| 主仓库 | https://github.com/2441630833/Mobius.git | `main` |
| VS Code fork | https://github.com/2441630833/Mobius-vscode.git | `mobius-custom` |
| Continue fork | https://github.com/2441630833/Mobius-continue.git | `mobius-custom` |
| Hermes Agent（参考） | https://github.com/NousResearch/hermes-agent.git | `main` |

克隆（含子模块）：

```powershell
git clone --recursive https://github.com/2441630833/Mobius.git
cd Mobius
```

若已克隆主仓库、子模块为空：

```powershell
git submodule update --init --recursive
```

## 子模块 remote 配置

每个子模块应有两条 remote：

```text
origin    → 你的 fork（GitHub）
upstream  → 官方上游
```

检查：

```powershell
git -C vscode remote -v
git -C continue remote -v
```

预期：

```text
# vscode
origin    https://github.com/2441630833/Mobius-vscode.git
upstream  https://github.com/microsoft/vscode.git

# continue
origin    https://github.com/2441630833/Mobius-continue.git
upstream  https://github.com/continuedev/continue.git
```

## 日常 rebase 上游

### 同步 VS Code 上游

```powershell
cd D:\AI\physical-ai-ide\vscode
git fetch upstream
git checkout mobius-custom
git rebase upstream/main
```

有冲突时：

```powershell
# 手动解决冲突后
git add .
git rebase --continue

# 放弃本次 rebase
git rebase --abort
```

rebase 完成后，推送 fork 并更新主仓库指针：

```powershell
git push origin mobius-custom

cd D:\AI\physical-ai-ide
git add vscode
git commit -m "chore: bump vscode submodule"
git push origin main
```

### 同步 Continue 上游

```powershell
cd D:\AI\physical-ai-ide\continue
git fetch upstream
git checkout mobius-custom
git rebase upstream/main
```

解决冲突后：

```powershell
git add .
git rebase --continue
git push origin mobius-custom

cd D:\AI\physical-ai-ide
git add continue
git commit -m "chore: bump continue submodule"
git push origin main
```

### 同步 Hermes Agent（只读参考）

一般只跟随上游 `main`，不做自定义分支：

```powershell
cd D:\AI\physical-ai-ide
git submodule update --remote hermes-agent
git add hermes-agent
git commit -m "chore: bump hermes-agent submodule"
git push origin main
```

## 同步频率建议

- 不必每次上游更新都 rebase；按版本需求（例如对齐某个 VS Code release）批量同步即可。
- rebase 前确保工作区干净：`git status` 无未提交改动。
- rebase 后建议跑一遍构建验证：

```powershell
npm run install:continue
npm run build:vscode
npm start
```

## 常见问题

### 为什么不在主仓库里 rebase？

主仓库在 flatten 子模块后，与 `microsoft/vscode` **没有共同提交历史**，在主仓库执行 `git rebase upstream/main` 会报 `refusing to merge unrelated histories`。正确做法是在子模块 fork 内 rebase。

### rebase 中断了怎么办？

```powershell
git rebase --abort          # 回到 rebase 前
git rebase --continue       # 冲突解决后继续
git rebase --skip           # 跳过当前提交（慎用）
```

### 迁移到 GitHub（已完成）

三个仓库均已迁移到 GitHub，并通过孤儿分支（无历史提交）发布：

| 仓库 | URL | 分支 |
|------|-----|------|
| 主仓库 | https://github.com/2441630833/Mobius.git | `main` |
| VS Code fork | https://github.com/2441630833/Mobius-vscode.git | `mobius-custom` |
| Continue fork | https://github.com/2441630833/Mobius-continue.git | `mobius-custom` |

GitHub 单仓库推荐 5 GB 以内，无 Gitee 式 1 GB 硬顶，适合长期维护大型 fork。如需再次以孤儿分支发布：

```powershell
# 主仓库
git checkout --orphan fresh-start
git rm -r --cached .
git add -A
git commit -m "Initial public release"
git push -u origin fresh-start:main

# 各子模块（推送独立 fork）
git -C vscode checkout --orphan fresh-start
git -C vscode add -A
git -C vscode commit -m "Initial public release"
git -C vscode push -u origin fresh-start:mobius-custom
```

### Mobius.exe 锁住 `vscode/.build`

rebase 或清理目录前，先关闭 IDE：

```powershell
taskkill /F /IM Mobius.exe
```

## 恢复过程备注

- 自定义改动从 `c0c01750` 到恢复前的 `HEAD` 导出并迁移到 fork。
- 恢复时若 Mobius 正在运行，可能需先结束进程才能替换 `vscode/` 目录。
- submodule 迁移提交使用了 `--no-verify`（pre-commit 无法处理上万文件的索引变更）。
- 补丁备份（若仍存在）：`D:\AI\mobius-vscode.patch`、`D:\AI\mobius-continue.patch`，可删除。
