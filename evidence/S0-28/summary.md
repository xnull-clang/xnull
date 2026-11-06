# S0-28 摘要

## 一句话

在 `/Users/vjs/Desktop/XNull-Lang/wt/` 下建好 9 个研发 worktree（`c1-rd1..3`、`c2-rd1..3`、`c3-rd1..3`），分支 `pod/c1-rd1..pod/c3-rd3`，全部基于 `main`（`dfcf033`），9 个 wt 工作区全干净。

## 数据

| 项 | 值 |
| --- | --- |
| 基线 | `main` = `dfcf033` |
| 新增 worktree | 9 |
| 新增分支 | 9（`pod/c1-rd1`…`pod/c3-rd3`） |
| 脏工作区 | 0 |
| `git worktree list` | 17 行（1 main + 7 既有 + 9 新增） |
| push / merge | 无 |

## 说明

卡面预期 10 行是按「1 主 + 9 新」估算；仓库中另有 7 个既有 worktree（E1–E5、E6、QA1），故实际 17 行。

S0-04b（CI 入库 + 旧扩展名门禁）目前只在 `pod/e6-toolchain`（`65e7dd4`），未在 main；新 worktree 按卡面以 main 为基线，因此暂时没有 `ci/`。建议董事会合入后由各 wt `merge main --ff-only`。
