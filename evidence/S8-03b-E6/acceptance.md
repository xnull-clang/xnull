# S8-03b 自检结论（传递依赖图 / 同深度仲裁 / 冲突路径 / 锁交互）

## 交付

`impl/internal/manifest/graph.go`：
- `ResolveGraph(res, repoRoot)`：从直接依赖 BFS 构建传递依赖图；依赖元数据取自本地仓库 `group/artifact/version/xnull.project`（无元数据视为叶子）。
- 最近优先：同坐标取最小深度；**同深度多版本 → `XPD-403`**，消息列出**全部路径**（`coord@ver <- root -> …`）。
- `dependencyManagement` **恒优先**于最近优先（根链管理版本直接钉住）。
- scope：`compile`/`runtime` 传递（runtime 向下传播，compile 按子声明）；`test`/`provided` 不传递。
- `exclusions`：随子树传递，命中坐标即剪枝。
- 环依赖 → `XPD-409`（路径输出）；依赖清单非法 → `XPD-408`。
- `GenerateLockForGraph` / `ValidateLockForGraph`：锁条目覆盖**传递闭包**；缺条目/版本不一致 → 404，多余坐标 → 405，摘要不符 → 406。
- `impl/internal/cli/lock.go`：`xnull lock` 与 `--update-lock` 改为图解析 + 图校验。

`impl/internal/manifest` 依赖解析补 `scope`/`exclusions`（`Resolved.Scopes`/`Resolved.Exclusions`）。

## 验证

| 项 | 结果 |
|---|---|
| 红 | 实现前 `go test -run TestGraph` 编译失败（`red.txt`） |
| 绿 | `go test ./internal/manifest -count=1` → ok（传递图、最近优先、同深度冲突、冲突路径含四个路径片段、管理版本优先、test scope 不传递、exclusions、环） |
| 锁交互 | 锁含传递依赖（`g:a,g:b`）；`TestLockCommand` 通过（缺锁/生成/校验/清单变更 XPD-404） |
| 回归 | `go test ./internal/cli` → ok |

## 缺口

1. 依赖元数据只从本地 `XNULL_REPO` 读取；无元数据按叶子处理（不报错），远程/HTTP 与制品内嵌元数据未接。
2. 同深度冲突判定基于“坐标+版本”，未做完整 Maven 式图裁剪（例如已选版本对不同分支的裁剪差异）。
3. `optional=true` 未参与裁决（字段已解析但未用）。
4. 锁的 `kind=plugin` 未生成。
