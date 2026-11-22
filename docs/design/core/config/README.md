# `xdk.config` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.config` |
| 层 | `xdk.core` / L3 |
| 依赖 | `xdk.errors`、`xdk.meta`、`xdk.text`、`xdk.fs`、`xdk.sys` |
| 被依赖 | `cli`、`log`、应用主逻辑 |
| 稳定性 | 基础 `stable`；来源/校验 `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.config` 提供配置快照/来源/加载/覆盖/类型化读取/校验：

- `Config` 键值快照；
- `ConfigEntry`；
- `ConfigSource` 协议 + Map/File/Env/Overlay 来源；
- `ConfigLoader`；
- `ConfigSchema`/`ConfigField` 校验；
- `ProfileSource`/`ConfigProfileSource` 能力画像加载。

不做：JSON/TOML/YAML 解码（`codec`/）、远程配置、热更新、密钥管理。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 无全局配置 | 由调用方显式持有 |
| 快照 | 来源加载成 Config；运行期不隐式刷新 |
| 白名单 env | 只读显式键 |
| 类型化 Result | 类型转换失败 `InvalidArgument` |
| 有序 | entries 保持插入/加载顺序 |
| 无隐式 key | 键非空、不含 `=`/换行 |
| 校验聚合 | Schema 一次返回全部字段错误 |
| 画像只读 | `ConfigProfileSource` 返回不可变 `CoreProfile`；不缓存、不热更新 |
| 能力自洽 | 画像缺失/非法/不自洽返回 `InvalidArgument` |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Config` | class | 配置快照/读取/覆盖 | [`Config.md`](Config.md) |
| `ConfigEntry` | class | 键值条目 | [`ConfigEntry.md`](ConfigEntry.md) |
| `ConfigSource` | protocol | 配置来源 | [`ConfigSource.md`](ConfigSource.md) |
| `MapSource` | class | 内存来源 | [`MapSource.md`](MapSource.md) |
| `FileSource` | class | 文件来源 | [`FileSource.md`](FileSource.md) |
| `EnvSource` | class | 环境来源 | [`EnvSource.md`](EnvSource.md) |
| `OverlaySource` | class | 多来源覆盖 | [`OverlaySource.md`](OverlaySource.md) |
| `ConfigLoader` | class | 加载/重载 | [`ConfigLoader.md`](ConfigLoader.md) |
| `ConfigSchema` | class | 字段校验 | [`ConfigSchema.md`](ConfigSchema.md) |
| `ConfigField` | class | 字段规则 | [`ConfigField.md`](ConfigField.md) |
| `ProfileSource` | protocol | 能力画像来源 | [`ProfileSource.md`](ProfileSource.md) |
| `ConfigProfileSource` | class | 从 Config 读取画像 | [`ConfigProfileSource.md`](ConfigProfileSource.md) |

X 未纳入本批：`ConfigSnapshot`、`ConfigWatcher`、`ArgsSource`、`ConfigPath`、codec 结构化来源。后续单独设计。

---

## 4. 技术/支撑/依赖

- 技术：有序键值表、来源加载、覆盖优先级、类型解析、Schema 校验、能力画像解析。
- 支撑：`text.parseInt/parseBool/parseFloat`、`fs.readText`、`sys.envOrNull`、`Context`。
- 依赖：`errors`、`meta`、`text`、`fs`、`sys`、`ConfigEntry`、`ConfigSource`、`ConfigSchema`、
  `ConfigField`、`CoreProfile`、`ProfileSource`、`ConfigProfileSource`。

---

## 5. 场景

### C1：CLI 配置

`ConfigLoader` + `FileSource` + `EnvSource`；profile；覆盖顺序；启动失败 `Result`。

### C2：类型化读取

`getIntOr/getBoolOr/getDuration`；失败 `InvalidArgument`；默认值显式。

### C3：多环境

Overlay：默认文件 → profile 文件 → env → CLI；后者覆盖前者。

### C4：校验

`ConfigSchema` 必填/类型/自定义；一次返回 `ErrorGroup`。

### C5：服务热重载（X）

`ConfigLoader.reload`； 不提供 watcher。

### C6：能力画像加载

`ConfigProfileSource` 读取 `profile.role`、能力列表、资源上限、I/O 与关闭策略；
角色缺失/非法/不自洽 → `InvalidArgument`。验收：客户端画像默认不含入站能力；服务器
`deadline` 必须有截止；配置覆盖不改变默认值对象。

---

## 6. 缺口与决策

| 项 | 决策 |
| --- | --- |
| JSON/TOML/YAML |  codec |
| 远程配置 | 不做 |
| 热更新 | X |
| 密钥管理 | 不做；不进日志 |
| 插值/引用 | 不做 |
| 多 profile 自动发现 | 应用/CLI |
| 键大小写 | 大小写敏感 |
| 值类型 | 字符串存储；读取时转换 |

## 9. 1.x 已实现 API 回写

- `Config.setChecked(key, value)` 最小键校验；
- `Config.apply(ConfigSource)` 与 `ConfigSource/MapSource/FileSource`；
- `Config.overlay`、`copy`、`env allowlist` 均已在 1.x 验证。

2.x 的 `ConfigLoader`/`ConfigSchema` 是增量；1.x 面不删。
