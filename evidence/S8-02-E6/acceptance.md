# S8-02 自检结论（继承 / 变量 / profile）

## 交付

`impl/internal/manifest/manifest.go`（新包）：
- `Load(path, Options{Profiles, Platform, ToolchainVersion})` → `Resolved{坐标/属性/依赖/build/configuration/激活 profile/继承链}` + `[]diag.Diagnostic`；
- 继承链：`relativePath`（缺省 `../xnull.project`）自底向上解析，深度上限 8、环/self-parent、缺失 parent、parent 非 `pom` 全部拒绝；
- 坐标不继承：`groupId`/`artifactId`/`version`/`packaging` 必须由子工程自声明；
- 变量：`${name}` 单次替换（不递归展开替换结果），内置 `project.groupId/artifactId/version/basedir`、`xnull.version`，未解析即失败；`packaging`/`scope`/`phase`/`kind` 等枚举字段禁变量；
- profile：`-P` 显式 + `activation.platform` 并集激活，可覆盖 `properties`/`dependencies`/`build`/`configuration`，多 profile 同键冲突失败、未知 `-P` 失败、覆盖坐标/`parent`/`modules`/`repositories` 失败。

## 诊断码（XPD-3xx，段位内自定义）

| 码 | 含义 |
|---|---|
| XPD-301 | 缺坐标字段 / 缺 project 块 |
| XPD-303 | 继承深度 > 8 |
| XPD-304 | 继承环 / self-parent |
| XPD-305 | parent 缺失 |
| XPD-306 | parent 非 pom |
| XPD-307 | 未解析变量 |
| XPD-308 | 枚举字段变量化 |
| XPD-309 | profile 冲突/未知/不可覆盖 |

## 验证

| 项 | 结果 |
|---|---|
| `go test ./internal/manifest -count=1` | **ok**（6 个顶层用例 / 14 个子用例） |
| `go test ./internal/xpd -count=1` | ok |
| 红证据 | 实现前包不存在/缺 API，测试编译失败（`red.txt`） |

## 缺口（未覆盖，如实登记）

1. parent 定位仅实现 `relativePath`；本地仓库/远程仓库定位（S8 §3.3 后两级）未接，`relativePath` 亦不做变量替换后的仓库回退。
2. 依赖合并只保留 `坐标→版本`（S8-02 判据所需的最小面）；`dependencyManagement`/`exclusions`/scope/optional 未建模（属 S8 依赖解析卡）。
3. 继承合并实现 `properties`/`dependencies`/`build`/`configuration` 四类；`dependencyManagement`/`repositories`/`plugins` 合并未实现（属 S8 依赖/插件卡）。
4. 未接入 `xnull build`/`xnull check`（清单模式构建仍是 `notImplemented`）；本卡只交付语义库与测试。
