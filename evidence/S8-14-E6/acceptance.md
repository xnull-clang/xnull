# S8-14 自检结论（聚合 reactor）

## 交付

`impl/internal/reactor`（新包）：
- **pom/modules 解析**：聚合根必须 `packaging = pom`；`modules.module <dir>` 按声明保序；目录必须为聚合根下的相对路径。
- **模块模型**：每个模块用 `manifest.ResolveDependencies` 解析（完整 schema/坐标/属性/profile），聚合根 `dependencyManagement` 通过 `Options.ManagedFallback` 注入（模块可省略版本，S8 A.3）。
- **模块图 + 拓扑排序**：Kahn 算法，同层按声明顺序（确定性）；环 → `XPD-409`；同 GAV 重复 → `XPD-302`；模块间依赖版本不一致 → `XPD-403`。
- **library → app 顺序**：由依赖边保证，测试验证 `core < codec < http < cli`。
- **starter**：含 `src/` → 失败；starter 的依赖递归并入使用者（只带依赖不带代码，`XPD-409` 防环）。
- **失败即停**：`Build(plan, fn)` 首个失败返回，后续模块不构建（单测与端到端各一）。

`impl/internal/cli`：
- `build` 遇 `pom` 聚合根走 reactor：逐模块按拓扑序调用 `buildManifestManaged`（注入聚合根仲裁表）；构建后写聚合摘要 `target/reactor-summary.txt`（模块顺序 + 产物路径 + sha256）；任一模块失败即停并返回非零。

## 验证

| 项 | 结果 |
|---|---|
| 红 | 实现前 reactor 包不存在，单测编译失败（`red.txt`） |
| 绿（单元） | 拓扑序、GAV 重复 302、环 409、starter 含 src 失败、starter 依赖传递、失败即停 |
| 绿（端到端） | `TestReactorAggregateBuild`：pom 根 → `core.xlib` + app 产物；摘要顺序 core 先于 app；core 安装到本地仓库；app 源码语法错误 → 失败即停 |
| 包级 | `reactor`、`cli` 全绿 |
| 全量 `go test ./...` | **红**：`codegen`、`codegen-ffi`（与上卡同批；`TestS3_EXPRCallReceiver` 在 codegen 全量运行中偶发失败，非本卡引入，新增失败类型 0） |

## 缺口 / 边界

1. **越界披露**：为注入聚合根仲裁表，在 `internal/manifest.Options` 增加 `ManagedFallback` 字段（`deps.go` 两行兜底）。不改其行为时零影响；本卡外无调用方。
2. `handoff/S8-14-reactor-plan.md` 未出现，按 S8 §2.1/A.3 实现；E5 计划落地后按需对齐。
3. 模块间依赖只做顺序/校验，不链接 `.xlib`（与 S8-13 边界一致）。
4. 模块内 `test` 阶段与插件执行未在 reactor 编排；`--skip` 对每模块生效。
5. 聚合摘要为自定义文本（`target/reactor-summary.txt`），未纳入 `.xmeta`。
