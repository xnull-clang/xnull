# `xdk.codec` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.codec` |
| 层 | L4 数据/编码（文档分组 `utils/`） |
| 依赖 | `xdk.errors`、`xdk.bytes`、`xdk.text`、`xdk.io`、`xdk.collections` |
| 被依赖 | 应用、HTTP/配置/日志 |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.codec` 提供 JSON/CSV/Base64/Hex 编解码：

- JSON：`JsonValue`/`JsonObject`/`JsonArray`/`JsonNumber`/`Json`/`JsonOptions`/`JsonKind`；
- CSV：`Csv`/`CsvOptions`/`CsvReader`/`CsvWriter`；
- Base64/Hex。

不做：YAML/TOML/XML、JSON Schema、JSON Pointer、任意对象反射序列化、URL 编码（`net.uri` 已有）。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 单一 JSON 值树 | XNull 类无动态覆盖；用 `JsonKind` + 单类，不搞子类多态 |
| 严格解析 | 非法 JSON/CSV → `DataCorrupted`/`InvalidArgument` |
| 数字不丢精度 | `JsonNumber` 保存原始文本，读取时显式转换 |
| 无反射 | 只处理 JSON 值树，不做对象映射 |
| 资源关闭 | `CsvReader`/`CsvWriter` 幂等 close |
| 无全局状态 | 无全局 parser/registry |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `JsonKind` | enum | Null/Bool/Number/String/Array/Object | [`JsonKind.md`](JsonKind.md) |
| `JsonNumber` | class | 原始数字/类型转换 | [`JsonNumber.md`](JsonNumber.md) |
| `JsonValue` | class | JSON 值树节点 | [`JsonValue.md`](JsonValue.md) |
| `JsonObject` | class | 有序 JSON 对象 | [`JsonObject.md`](JsonObject.md) |
| `JsonArray` | class | JSON 数组 | [`JsonArray.md`](JsonArray.md) |
| `Json` | class | 解析/生成/便捷读取 | [`Json.md`](Json.md) |
| `JsonOptions` | class | 深度/字节/注释/尾逗号 | [`JsonOptions.md`](JsonOptions.md) |
| `Csv` | class | CSV 解析/写出入口 | [`Csv.md`](Csv.md) |
| `CsvOptions` | class | 分隔符/引号/头 | [`CsvOptions.md`](CsvOptions.md) |
| `CsvReader` | class | 逐条读取 | [`CsvReader.md`](CsvReader.md) |
| `CsvWriter` | class | 逐条写出 | [`CsvWriter.md`](CsvWriter.md) |
| `Base64` | class | Base64 编解码 | [`Base64.md`](Base64.md) |
| `Hex` | class | Hex 编解码 | [`Hex.md`](Hex.md) |

X：`JsonPointer`、JSON Schema、流式 JSON SAX、CSV 类型映射、自定义注册表。

---

## 4. 顶层函数

无；JSON/CSV 使用静态入口，Base64/Hex 使用静态类。

---

## 5. 技术/支撑/依赖

- 技术：JSON 解析/生成、CSV 行解析、Base64/Hex、资源关闭。
- 支撑：`parseJsonRaw`、`formatJsonRaw`、`csv*Raw`、`base64*Raw`、`toHex`/`fromHex`。
- 依赖：`xdk.errors`、`xdk.bytes`、`xdk.text`、`xdk.io`、`xdk.collections`。

---

## 6. 场景

### C1：JSON 配置

`Json.parse(text)` → `Json.getObject`/`getString`/`getInt`。

### C2：JSON API

`Json.stringify(value)` / `stringifyPretty`；数字保原始文本。

### C3：CSV 导入

`Csv.parse(text, options)`；`CsvReader` 逐条读取；关闭。

### C4：Base64/Hex

`Base64.encode`/`decode`；`Hex.decode` 非法字符报错。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| JSON 子类多态 | 不做；单 `JsonValue` + kind |
| 对象映射/反射 | 不做 |
| JSON Pointer/Schema | X |
| 注释/尾逗号 | `JsonOptions` 显式开启 |
| 数字精度 | 原始文本；显式转换 |
| URL 编码 | 由 `net.uri` 提供 |
| CSV 类型映射 | 只做 string 行 |
| 全局注册表 | 禁止 |
