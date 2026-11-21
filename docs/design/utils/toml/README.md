# `xdk.toml` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.toml` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.codec`（`JsonValue`/`JsonObject`/`JsonArray`/`JsonNumber`） |
| 被依赖 | 配置加载、构建/发布清单、应用 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

TOML 1.0.0 解析/生成，值树复用 [`xdk.codec`](../codec/README.md)：

- 解析：TOML 文档 → `JsonValue.object`；表 → `JsonObject`，数组 → `JsonArray`，标量 → `JsonValue`；
- 生成：`JsonObject` 根值 → 规范化 TOML 文本。

不做：对象映射/反射、注释/格式保留、日期时间类型、`inf`/`nan`、null、Schema 校验、文件 IO、流式解析。

本包是 TOML 与 codec 值树之间的适配层，不是通用 TOML 引擎；调用方负责读取/写入文本与 UTF-8 解码。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 复用值树 | 不新增 TOML 节点类型；表/数组/标量直接用 codec 类型 |
| 严格解析 | 语法错误、重复键、重复表、非法表扩展 → `DataCorrupted` |
| 重复键不可选 | TOML 禁止重复键/表；不提供 `allowDuplicateKeys` |
| 资源有界 | `maxDepth`/`maxBytes` 防止深嵌套与大输入/输出 |
| 根为表 | 解析结果与生成输入都必须是 object |
| 输出确定 | 固定顺序、键 quoting、字符串转义；不保留注释/空行 |
| 失败显式 |  不支持的值 → `Unsupported`，不静默丢字段 |
| 无全局/无 IO | 静态无状态；无全局 parser/registry；不读文件 |
| 无第三方 | 只使用运行时 TOML 原语，不依赖第三方 toml 库 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Toml` | class | 解析/生成入口 | [`Toml.md`](Toml.md) |
| `TomlOptions` | class | 深度/字节上限 | [`TomlOptions.md`](TomlOptions.md) |

共 2/2 个类型文件；README 索引与文件一一对应。

X：日期时间类型、`inf`/`nan` 表示、注释保留、流式 Reader、任意精度整数。

---

## 4. 顶层函数

无；解析/生成使用静态入口 `Toml`，选项使用 `TomlOptions`。

---

## 5. 技术/支撑/依赖

- 技术：TOML 1.0.0 词法/语法、表路径状态、数组表、内联表封闭、标量规范化、键 quoting。
- 支撑：`parseTomlRaw`、`formatTomlRaw`、`toUtf8`、`toLong`。
- 依赖：`xdk.errors`（`Error`/`BasicError`/`ErrorKind`）、`xdk.codec`（值树与数字）。
- 不依赖：第三方 TOML 库、全局 parser、文件系统。

---

## 6. 场景

### S2：应用配置

调用方读取文本 → `Toml.parse(text)` → 检查 object → `Json.getObject`/`Json.getString`/`Json.getInt`。重复键与重复表直接失败。

### S3：构建/发布清单

`Toml.parse` 支持 bare/quoted/dotted key、标准表、内联表、数组表；读取工具链、依赖与目标列表。

### S4：规范化输出

`Toml.stringify(object)` 输出固定顺序与转义的 TOML；适合生成配置与测试期望，不保证保留源文件注释或原始数组表写法。

### S5：不可信输入

解析前按 UTF-8 字节检查 `maxBytes`，嵌套按 `maxDepth` 检查；拒绝超界整数、`inf`/`nan` 与日期时间，避免把不支持的值静默转成字符串。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 重复键/表 | 始终非法；`DataCorrupted`；无开关 |
| 日期时间 |  不支持；`Unsupported`（X） |
| `inf`/`nan` |  不支持；`Unsupported`（X） |
| null | TOML 无 null；`stringify` 遇到 → `Unsupported` |
| 注释/格式保留 | 不做；值树不携带语法信息 |
| 数组表输出 | 可输出 `[[table]]`；不保证与源文件写法一致 |
| 整数范围 | 严格 64 位有符号；超界 → `DataCorrupted`（解析）/`InvalidArgument`（生成） |
| 空键 | `JsonObject` 不允许空键；`""` 与空 bare key → `Unsupported` |
| 任意精度整数 | 不支持（X） |
| Schema 校验 | 不做；由 `xdk.validate` 承担 |
| 文件/流式 IO | 不做；调用方读取文本；流式 Reader 为 X |
| 全局 parser | 禁止 |

---

## 8. 依赖与顺序

```text
xdk.errors / xdk.codec
  └─ xdk.toml
       ├─ 配置加载
       ├─ 构建/发布工具
       └─ 应用
```

规则：

- 只依赖 `xdk.errors` 与 `xdk.codec`；不依赖 `fs`/`io`/`net`。
- `codec` 不反向依赖本包；YAML/TOML/XML 各自独立。
- 调用方读取文本并完成 UTF-8 解码；本包不读取文件、不建立全局 parser。

