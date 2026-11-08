# S8 集成收口自检结论（build 端到端）

## 交付（`impl/internal/cli/manifest.go` + `manifest_integration.go`）

validate 阶段按序接入，失败即停、诊断带 XPD 码与位置：
1. **锁**：`xnull.lock` 存在则 `LoadLock` → `ResolveGraph` → `ValidateLockForGraph`（XPD-4xx）；缺锁不阻断首次构建。
2. **配置**：`config.Load`（五层覆盖 + profile + 环境白名单；未知键/重复键/类型/必需键 → XPD-6xx），键集合取清单 `configuration` 声明。
3. **资源**：`resman.CollectForPackaging`（资源根/`includes`/`excludes`/冲突/symlink/pom 规则 → XPD-8xx），结果经 `devtool.GenerateResourcesFromMap` 生成资源表。
4. **插件**：按 `XNULL_REPO` 定位 `.xplugin` → `plugin.LoadMetadata` + `plugin.Validate`（XPD-5xx；缺失即 XPD-504）。

compile：`codegen.Options.ResC` 传入资源表（名字去掉 `resources/` 前缀，与运行时资源表口径一致）。
package：`.xmeta` 新增 `configSha256`、`resourcesSha256`、`pluginsSha256`、`profiles`、`plugins` 列表；`inputs` 摘要纳入四项集成摘要。

## 验证

| 项 | 结果 |
|---|---|
| 红（绕过集成） | 资源未进产物（`red.txt`：`产物未包含资源名 templates/a.txt`） |
| 绿（端到端） | `TestManifestIntegrationEndToEnd`：application.properties + resources/（含 excludes）+ .xplugin 一路构建通过；产物含 `templates/a.txt`、不含 `skip.psd`；`.xmeta` 四个摘要字段齐全 |
| 负向 | 缺 `.xplugin` → `XPD-504` 构建失败 |
| 受影响包 | `cli / manifest / resman / plugin / repro / config / devtool` 全绿（见 `green-packages.out`） |
| 全量 `go test ./...` | **红**：`internal/codegen`（`TestExamplesCompileMatchesInterp`、`TestS3_01*`、`TestTupleCodegenRuns` 等）与 `internal/codegen/ffi`（`rt_string` 未定义、`TestS609NetXfbContracts` 等）——**main 基线同样红**，属 E4/E5 在途，不是本卡引入（`go-test-all.out`） |

## 顺带修复

- `resman.Match`：`**` 改为可消费零段（`**/*.psd` 匹配根文件），与 S8 常用 glob 语义一致；对应单测更新。
- 依赖/插件仓库路径：groupId 点号转目录（`com.example` → `com/example`），修正 `.xplugin` 与制品摘要定位。

## 缺口

1. 配置键 schema 取清单 `configuration` 键集合；XDK 运行时键的权威 schema 未接（会产生“未知键”误报，需 B2 后补 key registry）。
2. 插件只做校验，不执行（沙箱执行 `plugin.Run` 未接入生命周期）。
3. `.xmeta` 摘要口径为本实现定义（canonical 排序文本），未与 E4/S8-04 的最终字段表逐字对齐。
4. 资源根只接主资源；`src/test/resources` 的 test 阶段并入未在 build 流程调用（resman API 已就绪）。
