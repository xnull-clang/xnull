# S8-05 自检结论（构建期插件合同，XPD-5xx）

## 交付

`impl/internal/plugin/plugin.go`（新包）：
- `LoadMetadata`：解析 `.xplugin`（plugin 块、goals/goal、phase、configKeys）；缺失文件/缺字段/未知段落/configKeys 非列表 → `XPD-504`；phase 非法或缺失（缺失记 504）→ `XPD-501/504`。
- `Validate`：清单声明与元数据一致——坐标/版本不一致 → `XPD-504`；版本非精确、phase 非法、goal 未声明、goal.phase 不符、configuration 键未在 `configKeys` → `XPD-501`；`toolchainVersion` 主版本不一致 → `XPD-504`。
- `Run`：执行插件前快照 `target/` 之外文件，执行后比对——新增/修改/删除 → `XPD-502`；命令非零退出 → `XPD-503`；网络通过 `sandbox-exec` profile `(deny network*)` 隔离，沙箱不可用或显式 `NoSandbox` → `XPD-505` 拒绝执行（不裸跑）；环境变量只注入白名单。
- `impl/internal/manifest`：解析 `build.plugins.plugin` 为 `Resolved.Plugins`（坐标/版本/phase/goal/configuration），供上述校验消费。

## 验证

| 项 | 结果 |
|---|---|
| 红 | 实现前 `go test ./internal/plugin` 编译失败（包/API 不存在，`evidence/S8-05-E6/red.txt`） |
| 绿 | `go test ./internal/plugin -count=1` → **ok**（元数据 5 例、声明一致性 8 例、执行策略 4 例） |
| 执行策略实测 | target 内写通过；`src/` 写入 → `XPD-502`；`exit 3` → `XPD-503`；`NoSandbox` → `XPD-505`（本机存在 `sandbox-exec`，正常路径真实运行） |
| 回归 | `go test ./internal/manifest` → ok（含新增插件解析用例） |

## 缺口（如实登记）

1. 插件**依赖隔离**按“完全不解析插件依赖”实现：插件 dependencies 不进编译类路径（天然隔离），但插件自身依赖解析/仲裁未实现。
2. 插件制品定位（按坐标找仓库制品 + `.xplugin`）未接；本卡只做元数据与声明校验、执行策略。
3. 未接入 `xnull build` 生命周期（validate/compile/test/package/install 编排未实现），因此 `Run` 目前是策略层 API。
4. `sandbox-exec` 为 macOS 工具；Linux/Windows 无等价实现时按 `XPD-505` 拒绝执行（安全侧默认关闭）。
5. `configuration` 键只校验“在 configKeys 中”，不校验类型/取值。
