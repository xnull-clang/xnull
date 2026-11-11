# B4b-04b-3 设计：构建期插件（plugin）——只设计，不实现

- 卡片：B4b-04b-3（plugin 合同面）
- 日期：2026-11-11
- 依据：`impl/internal/plugin/plugin.go`（494 行，含测试）、`internal/cli/manifest_integration.go:150`
- 结论：XNull 侧需要实现 **元数据解析 + 声明一致性校验 + 受限执行** 三块；本卡只记录语义与方案，不写代码

## 1. Go 侧语义（现状）

### 1.1 `.xplugin` 元数据（XPD DSL）

```text
plugin {
  groupId          = io.xnull
  artifactId       = my-plugin
  version          = 1.2.0
  toolchainVersion = 0.1.0
  goals {
    goal verify {
      phase      = test
      configKeys = [strict, timeout]
    }
  }
}
```

`LoadMetadata`（`XPD-504` / `XPD-501`）：

- 缺文件 / 缺 `plugin` 块 / 缺 `groupId|artifactId|version|toolchainVersion` → `XPD-504`；
- 未声明任何 goal → `XPD-504`；未知段落 → `XPD-504`；
- goal 缺 `phase`，或 `phase ∉ {validate, compile, test, package, install}` → `XPD-501`；
- `configKeys` 必须是列表（否则 `XPD-504`）。

### 1.2 清单声明一致性（`Validate`）

- 坐标与版本必须与 `.xplugin` 完全一致（`XPD-504`）；
- 插件版本必须是精确版本（`XPD-501`，禁止范围/SNAPSHOT/LATEST/RELEASE）；
- 声明 `phase` 必须合法，且与 goal 的 `phase` 一致（`XPD-501`）；
- `configuration` 的键必须出现在该 goal 的 `configKeys` 里（`XPD-501`）；
- `.xplugin.toolchainVersion` 与当前工具链 **主版本** 必须一致（`XPD-504`）；
- 阶段集成：`validateIntegrations` 在 build 的 validate 阶段校验；`.xmeta` 写 `plugins` 列表与
  `pluginsSha256 = sha256(join(sorted("coord@ver:goal"), "\n"))`。

### 1.3 执行（`Run`）

- 只允许在 `target/` 内写：执行前后对工程目录做快照，target 之外新增/修改/删除 → `XPD-502`；
- 禁网：必须用 `sandbox-exec`（macOS）启动，不可用或 `NoSandbox` → `XPD-505` 拒绝执行（"不得裸跑"）；
- 环境只传白名单（如 `XNULL_REPO`），不继承宿主环境；
- 非零退出 → `XPD-503`；诊断按文件排序后返回。

## 2. XNull 侧缺口与方案

| 能力 | XNull 现状 | 方案 |
|---|---|---|
| `.xplugin` 解析 | `xpd.x` 只覆盖 `project` 子集 | 扩 `xpd.x` 为通用块/字段树，或 `plugin.x` 自带最小解析 |
| 元数据校验 | 无 | `plugin.x`：`loadMetadata` + `validate`，诊断码/文本对齐 Go |
| 声明读取 | `config.x` 只读 `build {}` | 扩到 `build.plugins.plugin`（坐标/版本/phase/goal/configuration） |
| `.xmeta` 插件摘要 | `xmeta.x` 写 `plugins = []` | 按 Go 口径计算 `pluginsSha256` 并填 `plugins` 列表 |
| 受限执行 | 只有 `procStatus`（继承宿主环境、无沙箱） | 需要 `procRun(cmd, dir, env)` 与 sandbox 能力（E5 域） |
| 禁网 | 无 | 一期与 Go 一致：无 sandbox 即拒绝执行（`XPD-505`）；二期接 `sandbox-exec` |
| 越界写检测 | 无 `stat`/快照能力 | 需要目录遍历 + 文件摘要（`fsx` 建设项，B4b-03c） |

### 2.1 需要的最小 API（XNull）

```text
# xpd.x（扩展）
Node parseAny(String path)                 # 通用 Block/Field 树
# plugin.x
Meta loadPluginMeta(String path)           # XPD-504/501 诊断
Diags validatePlugin(Meta md, Decl d, String toolchain)
String pluginsDigest(Decl[] ds)            # sha256(join(sorted("coord@ver:goal"), "\n"))
# 执行（依赖 E5 绑定）
Int runPlugin(String dir, String target, String[] cmd, Map<String,String> env, Bool noSandbox)
```

## 3. 卡拆分建议（B4b-04b-3 → 4 个子项）

| 子卡 | 范围 | 验收 |
|---|---|---|
| a | `xpd` 通用树 + `.xplugin` 解析 | 对 Go `plugin_test.go` 的元数据用例对拍（诊断码/文本） |
| b | 声明一致性校验（坐标/版本/phase/goal/configKeys/主版本） | 6 类负例逐条一致 |
| c | `.xmeta` 的 `plugins` / `pluginsSha256` | 与 Go 产物逐字节一致 |
| d | 受限执行（target 写检测 + 禁网 + 环境白名单） | 需 E5 的 `procRun`/sandbox 能力；否则只能标 NA |

## 4. 风险

1. **执行面依赖平台**：`sandbox-exec` 仅 macOS；Linux 需 namespace/seccomp，Windows 无对应物。
   Go 当前在无 sandbox 时"拒绝执行"，XNull 必须保持同一语义而不是放宽。
2. **写越界检测成本**：需对工程目录做全量快照（含内容摘要），大仓库代价高；Go 已接受该成本。
3. **环境白名单**：XNull 没有"传入受控环境"的能力（`procStatus` 继承宿主环境），直接实现会破坏合同。
4. **诊断文本稳定性**：插件诊断是 XPD-5xx 合同面，必须逐字节对拍，不能只保证码相同。
5. **`.xplugin` 分发**：元数据随 `.xlib` 安装（B4b-03c 的 `xlib.meta`/仓库布局）；打包落地前，
   只能从工程本地 `plugins/` 读取（Go 也有该回退路径）。
