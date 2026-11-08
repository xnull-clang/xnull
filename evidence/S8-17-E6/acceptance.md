# S8-17 自检结论（依赖命令 install / tree / why）

## 交付

新增 `impl/internal/cli/deps_commands.go`（复用 `artifact` 与 `manifest` 图，不改 codegen/xfront）：
- **`xnull install [dir]`**：先走清单构建（library 在 install 阶段写 `.xlib`；app 在此复制可执行体 + `.xmeta` + `xnull.project` 到本地仓库 `artifact.RepoDir`），stdout 输出 `已安装 <产物>（sha256 …）`。
- **`xnull tree [dir]`**：`manifest.ResolveDependencies` + `ResolveGraph` 后按 `Graph.Paths` 重建层级，输出 `坐标@版本` 缩进树（根为工程 GAV）；冲突时图解析直接报 XPD-403 等。
- **`xnull why <GAV> [dir]`**：输出坐标、仲裁版本、完整路径（`a@v -> b@v`）、版本来源（直接依赖 / `dependencyManagement 固定` / 最近优先）、深度；未解析坐标 → 退出 2 并提示。
- 命令注册：`install/tree/why` 进入 `commands` 表与 `Run` 分派；`--profile` 沿用。

## 验证

| 项 | 结果 |
|---|---|
| 红 | 实现前三命令均为 `CLI-001` 未知命令（`red.txt`） |
| 绿 | `TestTreeCommand`（根 + 两级依赖版本齐全）、`TestWhyCommand`（路径含 `g:a@1.0.0 → g:b@2.0.0`；未知坐标失败）、`TestInstallCommand`（`.xlib` 与 `xnull.project` 入仓库，stdout 含实际 sha256） |
| 包级 | `go test ./internal/cli` 通过 |
| 全量 `go test ./...` | **红**：`codegen`、`codegen-ffi`，与 S8-16 基线同集（本次少 1 个偶发项，新增 0） |

## 缺口

1. `install` 对 app 只复制产物/元数据/清单，未做依赖闭包打包（`.xlib` 链接面仍待 B2/B3）。
2. `tree`/`why` 的路径取自 `Graph.Paths`（每坐标保留仲裁后的代表路径）；被裁剪的其他候选路径不展开（冲突时直接报错）。
3. `tree` 未标注 scope/optional；`why` 未区分“被某模块声明”与“传递引入”的来源模块（路径已够定位）。
4. `install` 不写 sha 清单文件，只在 stdout 输出。
