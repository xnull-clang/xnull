# S0-28 自检结论：9 个研发 worktree

> 前置 S0-04b 已完成（`65e7dd4`）。基线 `main` = `dfcf033`。本卡只做 worktree/branch 创建，不 push、不合并。

## 创建结果

| 目录 | 分支 | HEAD | `git status --porcelain` |
|---|---|---|---|
| `wt/c1-rd1` | `pod/c1-rd1` | `dfcf033` | 空（干净） |
| `wt/c1-rd2` | `pod/c1-rd2` | `dfcf033` | 空 |
| `wt/c1-rd3` | `pod/c1-rd3` | `dfcf033` | 空 |
| `wt/c2-rd1` | `pod/c2-rd1` | `dfcf033` | 空 |
| `wt/c2-rd2` | `pod/c2-rd2` | `dfcf033` | 空 |
| `wt/c2-rd3` | `pod/c2-rd3` | `dfcf033` | 空 |
| `wt/c3-rd1` | `pod/c3-rd1` | `dfcf033` | 空 |
| `wt/c3-rd2` | `pod/c3-rd2` | `dfcf033` | 空 |
| `wt/c3-rd3` | `pod/c3-rd3` | `dfcf033` | 空 |

9/9 成功；全部 `git worktree add -b <branch> <dir> dfcf033`（等价于在 main 仓库以 `HEAD` 为基线），无冲突、无已存在分支。

## `git worktree list` 行数

- 实测 **17 行**：`main` 1 + 原有 `e1-front`/`e2-sema`/`e3-interp`/`e4-codegen`/`e5-runtime`/`e6-toolchain`/`qa-1` 7 个 + 本卡新增 9 个。
- 卡面预期「10 行」对应「1 主 + 9 新」，未把既有 7 个 worktree 计入；本卡不改动既有 worktree。完整清单见 `worktree-list.txt`。

## 边界

- 新分支全部从 `main`（`dfcf033`）拉出，**不含** `pod/e6-toolchain` 上未合入的提交（`f826d1f` 之后的 `65e7dd4` S0-04b）；这是按卡面「基于 main 当前 HEAD」执行的结果。若研发需要 CI 第 10 项，应先由董事会把 S0-04b 合入 main 再让各 wt `git merge main --ff-only`。
- 未 push、未合并、未改 main。

## 声明

执行侧自检，不构成验收签署。
