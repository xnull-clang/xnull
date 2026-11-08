# S8-12 自检结论（继承 / 依赖接入 build）

## 交付

`impl/internal/cli/manifest.go`：build 的 validate 改为 **`internal/manifest` 完整模型**：
- `loadProjectManifest(root, profile)` 调用 `manifest.ResolveDependencies`（parent 展开 `relativePath`、属性替换、profile 合并、dependencyManagement/坐标校验），并从 `Resolved` 取坐标、`Properties`、合并后的 `Build` 字段（parent 的 `sourceRoot`/`warnings`/`entryFile` 等按字段级覆盖生效）。
- 删除 cli 自带简化 loader（`parseBuildSpec`/`blockField`/`childBlock`/`valueText`），保留 `validateBuildSpec`/`resolveEntry`。
- 所有清单语义错误直接透传 `internal/manifest` 的 XPD 码与位置（301/303/304/305/306/307/308/309/403/404/405/406/409 等）。
- `manifestPipeline` 持有已解析的 `*manifest.Resolved`；`validateIntegrations` 不再重复解析，锁/配置/资源/插件校验共用同一模型。

## 验证

| 项 | 结果 |
|---|---|
| 红 | 继承工程用例失败（旧简化 loader 不继承 `build.sourceRoot`，入口按默认 `src/main/x` 找不到）：`red.txt` |
| 绿（继承） | `TestBuildInheritsParentBuild`：pom 父工程 `sourceRoot=alt/src` 被子工程继承，`xnull build` 通过并出产物 |
| 绿（依赖+锁） | `TestBuildDependencyWithLock`：依赖 `g:lib` + 本地仓库 + `xnull.lock`，构建通过；`.xmeta` 的 `lockSha256` 与锁字节一致；锁版本不一致 → `XPD-404` 失败 |
| 既有集成回归 | `TestManifestIntegrationEndToEnd` / `MissingPluginMeta` 仍通过 |
| `go test ./internal/cli` | 通过 |
| 全量 `go test ./...` | **红**：`internal/codegen`、`internal/codegen/ffi`（与上一卡基线完全同一批，新增失败为 0；`go-test-all.out`） |

## 缺口 / 边界

1. parent 定位只实现 `relativePath`；「本地仓库 → 远程仓库」两级属 S8-13（本地仓库/依赖解析卡），本卡未越界改 `internal/manifest`。
2. 配置键 schema 仍取清单 `configuration` 键集合（S8-INTEG 已知缺口）。
3. 全量测试红为 E4/E5 在途（`codegen` FFI `rt_string` 等），非本卡引入；本卡未新增失败。
4. 依赖目前只参与图/锁校验，不链接 `.xlib`（S8-13 负责）。
