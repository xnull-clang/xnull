# `xdk.net.mime` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.net.mime` |
| 层 | `xdk.net` / L5 |
| 依赖 | `xdk.errors`、`xdk.text` |
| 被依赖 | `net.http`、`net.websocket` |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.net.mime` 提供 MediaType/Media Type 参数与常见类型映射：

- `MediaType`：解析 `type/subtype; k=v`、读取/派生参数、常用判断；
- `MimeTypes`：扩展名 ↔ MediaType、默认 charset、常用常量。

不做：内容嗅探、完整 IANA 数据库、文件类型识别、编码转换、multipart 解析。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 大小写 | type/subtype 小写；参数名小写；参数值保留 |
| 严格解析 | 非法 token/参数 → `InvalidArgument` |
| 不可变 | MediaType 无 setter；`withParameter` 返回新实例 |
| 无全局状态 | 映射表只读；无运行时注册 |
| 不猜内容 | 只做显式扩展名/声明类型映射 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `MediaType` | class | 解析/参数/判断 | [`MediaType.md`](MediaType.md) |
| `MimeTypes` | class | 扩展名/常用类型 | [`MimeTypes.md`](MimeTypes.md) |

X：完整 IANA 表、内容嗅探、自定义注册表、结构化后缀（`+json`）策略。

---

## 4. 顶层函数

无。映射为 `MimeTypes` 静态方法。

---

## 5. 技术/支撑/依赖

- 技术：token 解析、参数表、小写归一。
- 支撑：`parseMediaTypeRaw`、`formatMediaTypeRaw`、扩展名映射表。
- 依赖：`xdk.errors`、`xdk.text`。

---

## 6. 场景

### M1：Content-Type

`MediaType.parse("text/html; charset=utf-8")`；`isText()`、`charset()`。

### M2：上传文件

`MimeTypes.fromExtension("png")`；未知扩展名返回 null。

### M3：HTTP body

`MediaType` 作为 Content-Type；HTTP 只传递类型，不做编码转换。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 文件嗅探 | 不做 |
| 完整 IANA 表 | 不做；内置常用类型 |
| 自定义映射 | X 显式 `MimeRegistry` |
| 参数顺序 | 不承诺；按参数集合语义处理 |
| 未知扩展名 | null |
| 非法类型 | `InvalidArgument` |
