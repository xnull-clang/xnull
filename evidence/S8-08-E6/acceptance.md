# S8-08 自检结论（资源收割器 / 清单侧）

## 交付

`impl/internal/resman`（新包，清单侧收割器；构建侧渲染/打包留给 E4）：
- `Collect(roots)`：资源根遍历 + `includes`/`excludes` glob（`**` 跨段、`*` 单段内、`?` 单字符；字符类不支持）、空目录零条目、符号链接按目标内容收录（断链/指向目录 → `XPD-805`）、非法根 → `XPD-801`、非法 glob → `XPD-802`。
- 制品路径：统一 `resources/<相对路径>`（S8 §5.6 固定前缀）。
- 冲突：同一制品路径 → `XPD-803` 并**点名两个来源**（两条源路径 / 两个 `groupId:artifactId`）。
- `MergeDependency`：依赖资源并入 app；同路径冲突点名两个 owner；`packaging=starter` 的资源不合并。
- `CollectForPackaging`：`pom` 声明任何资源根 → `XPD-804`。
- `CollectForPhase`：`main` 阶段不含测试资源；`test` 阶段并入 `src/test/resources`（与主资源冲突同样点名）。
- `impl/internal/manifest`：`build.resources.resource` 解析为 `Resolved.ResourceRoots{Dir, Includes, Excludes}`。

## 诊断码说明

卡片写「XPD-7xx」，但 S8 附录 C.6 规定 7xx=元数据、**8xx=资源与打包**。本实现按规范落 8xx（801–805）；如需 7xx 请先改规范段位。

## 验证

| 项 | 结果 |
|---|---|
| 红 | 实现前 `go test ./internal/resman` 编译失败（`red.txt`） |
| 绿 | `go test ./internal/resman -count=1` → **ok**（glob/前缀、glob 语义表、冲突点名、依赖合并/starter、符号链接、阶段隔离/pom/空目录、非法根与 glob） |
| 清单侧 | `go test ./internal/manifest` → ok（含 `build.resources` 解析用例） |

## 缺口 / 分工

1. **构建侧（E4）**：把 `resman.Set` 渲染为资源表/打包布局（`resources/` 前缀）、`.xmeta` 输入摘要、依赖来源的仓库取件——本卡只到“收割集合”。
2. `includes`/`excludes` 的 glob 无字符类（规范明确不支持）；`**` 后仍有段时要求至少消费一段（与 `**/*.psd` 不匹配根文件的用例一致）。
3. 依赖资源合并 API 已就绪，但未接实际的依赖解析/仓库（依赖图卡待做）。
4. 资源根路径相对工程根的解析由调用方负责（本包接收绝对/相对路径）。
