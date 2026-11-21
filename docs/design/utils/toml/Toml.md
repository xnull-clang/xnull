# `Toml`

| 项 | 值 |
| --- | --- |
| 类型 | `class Toml` |
| 包 | `xdk.toml` |
| 稳定性 | `preview` |
| 依赖 | `JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`TomlOptions`、`Error` |

---

## 1. 定位

TOML 1.0.0 静态入口：把 TOML 文档解析为以 `JsonObject` 为根的 codec 值树，把值树生成为规范化 TOML。

不做：日期时间类型、`inf`/`nan`、null、注释/格式保留、Schema 校验、对象映射/反射、文件 IO、流式 Reader。

---

## 2. 设计逻辑

- 无实例状态；构造器私有；所有调用独立。
- `parse` 先检查 null 与 UTF-8 字节上限，再委托运行时原语 `parseTomlRaw(text, options.copy())`。
- 文档根必须是表；空文档、仅空白或仅注释 → 空 `JsonObject`。
- 值映射固定：

| TOML 节点 | codec 值 |
| --- | --- |
| table / inline table | `JsonValue.object(JsonObject)` |
| array / array of tables | `JsonValue.array(JsonArray)` |
| string（basic/literal/multiline） | `JsonValue.string` |
| integer | `JsonValue.number(JsonNumber)` |
| float | `JsonValue.number(JsonNumber)` |
| boolean | `JsonValue.bool` |
| offset/local date-time、date、time | `Unsupported` |

- 键：bare key、quoted key、dotted key；最终叶子键进入对应 `JsonObject`。空键 → `Unsupported`（`JsonObject` 不允许空键）；同一表的重复键、重复表定义、非法表扩展 → `DataCorrupted`。
- 表：标准表 `[a.b]`、数组表 `[[a.b]]`、内联表 `{ ... }`。内联表一经定义即封闭，不能再通过点键或表头扩展；内联表必须单行且不允许尾逗号（值内部换行除外）。数组表后续子表挂到最后一个元素。
- 整数：支持十进制、`0x`、`0o`、`0b` 与下划线分隔；规范化为十进制 64 位文本，`-0`/`+0` 归一为 `0`。超出 `Int64` → `DataCorrupted`。
- 浮点：支持下划线与指数；去掉下划线与前导 `+` 后保存为 JSON 兼容文本。`inf`/`nan` → `Unsupported`。
- 字符串：支持 basic、literal、multiline basic、multiline literal 及其 TOML 转义；结果写入 `JsonValue.string`。
- 生成时字符串统一使用 basic string，换行写成 `\n`，其他控制字符写成 `\uXXXX`。
- 数组允许混合类型、嵌套与尾逗号；数组表由连续 `[[key]]` 构造，元素为 object。
- 注释与空白被跳过；不保留注释、空行、键的原始引号或数组表写法。
- `stringify` 只接受 object 根；遍历顺序为：先输出当前表的标量与内联数组，再按首次出现顺序输出子表/数组表。输出因此确定，但不保证与源文件行序一致。
- `stringify` 的数组：在表上下文中，非空且元素全为 object 的数组输出为 `[[path]]`；其他数组输出为内联数组。内联表/内联数组内部的值始终内联，不能再产生表头。
- `stringify` 的 object：表上下文中输出为 `[path]`；内联上下文中输出为 `{ key = value }`。
- 键与表头路径按 bare key 规则（`[A-Za-z0-9_-]+`）决定是否加引号；含点、空格或控制字符的段加双引号并转义。
- `stringify` 拒绝 null（TOML 无 null）、越界整数、非有限浮点、环、超深与超输出字节。
- 失败分类：参数/上限/根类型、生成阶段整数越界 `InvalidArgument`；语法/重复键/表规则、解析阶段整数越界 `DataCorrupted`； 不支持值 `Unsupported`。
- 无 close；可并发调用。

---

## 3. 表示与不变量

无实例字段。

不变量：

- `parse` 成功时根节点必为 object；
- `stringify` 只接受 object 根；
- 每次 `parse` 返回新值树，不复用解析器状态；
- 进入原语前复制 `TomlOptions`，调用后修改选项不影响本次结果；
- 值树无环；解析结果不携带 TOML 语法元数据；
- `stringify` 不修改入参值树；同一值树与选项产生相同文本；
- `maxBytes` 解析时指输入 UTF-8 字节，生成时指输出 UTF-8 字节；
- 生成顺序确定：同层先值后子表，组内保持 `JsonObject` 键顺序。

---

## 4. 生命周期

静态命名空间；无 close；无资源；无后台任务。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Toml()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 默认解析 | `String text` | `Result<JsonValue, Error>` | `DataCorrupted`/`Unsupported`/`InvalidArgument` |
| `parse` | 带选项解析 | `String text, TomlOptions options` | `Result<JsonValue, Error>` | 同上 |
| `stringify` | 默认生成 | `JsonValue value` | `Result<String, Error>` | `InvalidArgument`/`Unsupported` |
| `stringify` | 带选项生成 | `JsonValue value, TomlOptions options` | `Result<String, Error>` | 同上 |

说明：

- `parse(text)` 等价于 `parse(text, new TomlOptions())`；`stringify(value)` 等价于 `stringify(value, new TomlOptions())`。
- `parse` 的 `maxBytes` 在进入原语前检查；超过上限返回 `InvalidArgument`，不返回部分树。
- `parse` 成功时保证根为 object；调用方无需再做根类型判断，但仍需按路径读取。
- `stringify` 根不是 object → `InvalidArgument`；空 object → 空字符串。
- `stringify` 输出非空时以换行结束；字符串不输出多行样式，统一使用 basic string 转义。
- `stringify` 遇到 null → `Unsupported`；遇到环、深度超限或输出超 `maxBytes` → `InvalidArgument`，不返回截断文本；输出预算在追加文本时累计检查，不先生成完整字符串。
- 所有方法无阻塞、无取消点；调用方自行处理并发。

---

## 8. 使用的技术

- TOML 1.0.0 词法与语法；
- 表路径状态与数组表栈；
- 内联表封闭规则；
- 点键/表重定义检测；
- 整数进制规范化与 64 位范围检查；
- 确定性序列化与键 quoting。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Long、Result；
- 运行时：`parseTomlRaw`、`formatTomlRaw`、`toUtf8`、`toLong`；
- 接口：`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`TomlOptions`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`TomlOptions`、`Error`、`BasicError`、`ErrorKind`、TOML 运行时原语。

---

## 11. 所有权与并发

无状态；可并发；每次调用独立。返回值树归调用方所有；`stringify` 不取得入参所有权，也不修改入参。`TomlOptions` 在入口复制，调用方保留原对象所有权；无 close。

---

## 12. 示例与反例

正确：`Result<JsonValue, Error> loaded = Toml.parse(text)`；成功后按 object 读取。  
正确：`Toml.stringify(value, new TomlOptions().maxDepth(64).maxBytes(1048576))`。  
反例：把数组或标量作为 TOML 根；TOML 文档根必须是表。  
反例：在值树中放入 `null` 后 `stringify`；TOML 无 null。  
反例：期望解析日期时间为 `String`； 直接 `Unsupported`。  
反例：期望接受重复键或重复 `[table]`；TOML 禁止。  
反例：期望注释、空行、数组表写法逐字节往返。  
反例：用 `inf`/`nan` 或超出 64 位的整数。

---

## 13. 测试/场景义务

- 空文档、空白、仅注释；根表；
- bare/quoted/dotted key；空键失败；重复键失败；
- basic/literal/multiline 字符串、转义、换行；
- 整数：十进制、`0x`/`0o`/`0b`、下划线、`+`、`Int64` 边界与越界；
- 浮点：小数、指数、下划线、`+`、`inf`/`nan` 失败；
- 布尔；
- 数组：空、嵌套、混合类型、尾逗号、跨行；
- 内联表：嵌套、封闭后扩展失败；
- 标准表、嵌套表、数组表、数组表子表；
- 表重定义/点键冲突/重复表失败；
- 静态数组后追加数组表失败；表与数组表同名冲突失败；数组表子表挂到最后一个元素；
- 日期时间、时间、日期失败；
- `maxDepth`/`maxBytes` 边界；UTF-8 多字节计数；
- `stringify`：根类型、键顺序、先值后表、空表、数组表、内联表、字符串转义、null、越界数字、环、输出上限；
- parse/stringify 语义往返：表、数组表、内联结构、标量；
- 并发调用无共享状态。

---

## 14. XNull 伪代码

```xnull
class Toml {
    private Toml() {
    }

    static Result<JsonValue, Error> parse(String text) {
        return Toml.parse(text, new TomlOptions())
    }

    static Result<JsonValue, Error> parse(String text, TomlOptions options) {
        if text == null || options == null { throw "Toml.parse: null argument" }
        if toLong(toUtf8(text).length()) > options.getMaxBytes() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "TOML input exceeds maxBytes"))
        }
        return parseTomlRaw(text, options.copy())
    }

    static Result<String, Error> stringify(JsonValue value) {
        return Toml.stringify(value, new TomlOptions())
    }

    static Result<String, Error> stringify(JsonValue value, TomlOptions options) {
        if value == null || options == null { throw "Toml.stringify: null argument" }
        if !value.isObject() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "TOML root must be object"))
        }
        return formatTomlRaw(value, options.copy())
    }
}
```

> `parseTomlRaw`、`formatTomlRaw` 是运行时 TOML 原语；不是 XDK 公共类型，也不依赖第三方库。
