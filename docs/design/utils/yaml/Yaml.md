# `Yaml`

| 项 | 值 |
| --- | --- |
| 类型 | `class Yaml` |
| 包 | `xdk.yaml` |
| 稳定性 | `preview` |
| 依赖 | `YamlOptions`、`YamlVersion`、`YamlDocument`、`YamlPropertySource`、`JsonValue`、`Error` |

---

## 1. 定位

YAML 静态入口：单文档/多文档解析、profile 文档元数据、属性扁平化、单/多文档生成。

不做：对象绑定/反射、`${...}` 占位符解析、Schema 校验、注释/格式保留、文件 IO、流式 Reader、Spring 容器集成。

---

## 2. 设计逻辑

- 无实例状态；构造器私有；所有调用独立。
- `parse` 委托 `parseAll`，要求恰好一个文档。
- `parseAll` 先检查 UTF-8 字节与文档数上限，再委托 `parseYamlAllRaw(text, options.copy())`；每个原始文档提取 profile 后包装为 `YamlDocument`。
- profile 键按点号路径查找（如 `spring.config.activate.on-profile`）；值为字符串或字符串数组；缺失 → 空列表。
- `parsePropertySources` 要求每个文档根为对象；递归展平：
  - 映射 → 点号路径；
  - 序列 → `path[index]`；
  - null → 空串；bool → `true`/`false`；number → 原始文本；string 原样；
  - 空对象/空数组不产生属性。
- `stringify` 委托 `formatYamlRaw`；`stringifyAll` 用 `---` 分隔文档。
- 锚点/别名/合并键、YAML 1.1/1.2、标准标签由 `YamlOptions` 控制。
- 失败分类：参数/预算 `InvalidArgument`；语法/重复键/别名环 `DataCorrupted`；不支持特性 `Unsupported`。
- 无 close；可并发调用。

---

## 3. 表示与不变量

无实例字段。

不变量：

- 每次调用返回新结果；不复用解析器状态；
- `parse` 成功时恰好一个文档；
- `parseAll` 的文档索引从 0 连续递增；
- `parsePropertySources` 的属性源与文档一一对应；
- 选项在入口复制；调用后修改 options 不影响本次结果；
- 值树按只读使用；锚点别名可能共享节点（DAG），不存在环。

---

## 4. 生命周期

静态命名空间；无 close；无资源；无后台任务。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Yaml()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parse` | 默认单文档 | `String text` | `Result<JsonValue, Error>` | `DataCorrupted`/`Unsupported`/`InvalidArgument` |
| `parse` | 单文档 | `String text, YamlOptions options` | `Result<JsonValue, Error>` | 同上 |
| `parseAll` | 默认多文档 | `String text` | `Result<List<YamlDocument>, Error>` | 同上 |
| `parseAll` | 多文档 | `String text, YamlOptions options` | `Result<List<YamlDocument>, Error>` | 同上 |
| `parsePropertySources` | 默认属性源 | `String sourceName, String text` | `Result<List<YamlPropertySource>, Error>` | 同上 |
| `parsePropertySources` | 属性源 | `String sourceName, String text, YamlOptions options` | `Result<List<YamlPropertySource>, Error>` | 同上 |
| `stringify` | 默认生成 | `JsonValue value` | `Result<String, Error>` | `InvalidArgument` |
| `stringify` | 生成 | `JsonValue value, YamlOptions options` | `Result<String, Error>` | `InvalidArgument` |
| `stringifyAll` | 默认多文档生成 | `List<YamlDocument> documents` | `Result<String, Error>` | `InvalidArgument`/`Unsupported` |
| `stringifyAll` | 多文档生成 | `List<YamlDocument> documents, YamlOptions options` | `Result<String, Error>` | 同上 |

说明：

- `parse` 遇到多文档返回 `InvalidArgument`，提示使用 `parseAll`；空文本/仅注释视为一个 null 文档。
- `parseAll` 超过 `maxDocuments` 返回 `InvalidArgument`；`maxBytes` 是输入 UTF-8 字节。
- `parsePropertySources` 的 `sourceName` 非空；第 n 个文档的属性源名为 `sourceName#n`。
- `parsePropertySources` 的根不是对象 → `InvalidArgument`；不做属性合并，调用方按文档顺序合并。
- `stringify` 输出以换行结束；`stringifyAll` 文档之间输出 `---` 行。
- `stringify` 输出超过 `maxBytes`、值树环或深度超限 → `InvalidArgument`。
- `${...}` 占位符原样输出/保留，不解析。

---

## 8. 使用的技术

- YAML 1.1/1.2 标量解析；
- 多文档流与 profile 提取；
- 锚点表/别名上限/合并键；
- 点号路径查找；
- 属性扁平化；
- 确定性 scalar quoting/输出预算。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Long、List、Map、Result；
- 运行时：`parseYamlAllRaw`、`formatYamlRaw`、`toUtf8`、`toLong`；
- 接口：`YamlOptions`、`YamlVersion`、`YamlDocument`、`YamlPropertySource`、`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`Error`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`YamlOptions`、`YamlVersion`、`YamlDocument`、`YamlPropertySource`、`JsonValue`、`JsonObject`、`JsonArray`、`JsonNumber`、`Error`、YAML 运行时原语。

---

## 11. 所有权与并发

无状态；可并发；每次调用独立。返回值树/属性源归调用方；锚点别名可能共享节点，按只读使用；`YamlOptions` 入口复制；无 close。

---

## 12. 示例与反例

正确：`Yaml.parse(text)`；`Yaml.parseAll(text, options)`；`Yaml.parsePropertySources("application.yml", text, options.profileKey("spring.config.activate.on-profile"))`。  
正确：`Yaml.stringifyAll(documents)` 生成多文档。  
反例：用 `parse` 期望拿到多文档；期望 YAML 层解析 `${...}`；修改别名共享对象期望其他位置不变；把 profile 表达式 `prod & !dev` 当已支持；无 `maxAliases` 解析不可信 YAML。

---

## 13. 测试/场景义务

单/多文档；空文档；`---`/`...`；profile 键嵌套/字符串/数组/非法；profile 激活；属性扁平化点号/下标/null/空容器；锚点/别名/合并键开关；别名上限；YAML 1.1 bool vs 1.2；重复键；标准标签；深度/字节/文档上限；stringify/stringifyAll；占位符保留；并发。

---

## 14. XNull 伪代码

```xnull
class Yaml {
    private Yaml() {
    }

    static Result<JsonValue, Error> parse(String text) {
        return Yaml.parse(text, new YamlOptions())
    }

    static Result<JsonValue, Error> parse(String text, YamlOptions options) {
        if text == null || options == null { throw "Yaml.parse: null argument" }
        Result<List<YamlDocument>, Error> documents = Yaml.parseAll(text, options)
        if documents.isErr() { return Err(documents.error()) }
        if documents.value().length() != 1 {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "expected exactly one document; use parseAll"))
        }
        return Ok(documents.value().get(0).value())
    }

    static Result<List<YamlDocument>, Error> parseAll(String text) {
        return Yaml.parseAll(text, new YamlOptions())
    }

    static Result<List<YamlDocument>, Error> parseAll(String text, YamlOptions options) {
        if text == null || options == null { throw "Yaml.parseAll: null argument" }
        if toLong(toUtf8(text).length()) > options.getMaxBytes() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "YAML input exceeds maxBytes"))
        }
        YamlOptions copied = options.copy()
        Result<List<JsonValue>, Error> raw = parseYamlAllRaw(text, copied)
        if raw.isErr() { return Err(raw.error()) }
        if raw.value().length() > copied.getMaxDocuments() {
            return Err(new BasicError(ErrorKind.InvalidArgument, "too many YAML documents"))
        }
        List<YamlDocument> result = []
        Int index = 0
        while index < raw.value().length() {
            Result<List<String>, Error> profiles =
                Yaml.profilesFrom(raw.value().get(index), copied.getProfileKey())
            if profiles.isErr() { return Err(profiles.error()) }
            result.push(new YamlDocument(index, raw.value().get(index), profiles.value()))
            index = index + 1
        }
        return Ok(result)
    }

    static Result<List<YamlPropertySource>, Error> parsePropertySources(
            String sourceName, String text) {
        return Yaml.parsePropertySources(sourceName, text, new YamlOptions())
    }

    static Result<List<YamlPropertySource>, Error> parsePropertySources(
            String sourceName, String text, YamlOptions options) {
        if sourceName == null || sourceName == "" {
            throw "Yaml.parsePropertySources: empty source name"
        }
        Result<List<YamlDocument>, Error> documents = Yaml.parseAll(text, options)
        if documents.isErr() { return Err(documents.error()) }
        List<YamlPropertySource> result = []
        Int index = 0
        while index < documents.value().length() {
            YamlDocument document = documents.value().get(index)
            if !document.value().isObject() {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "YAML property source document root must be an object"))
            }
            Map<String, String> properties = new Map<String, String>()
            Yaml.flattenValue(document.value(), "", properties)
            String name = sourceName + "#" + str(document.index())
            result.push(new YamlPropertySource(name, document.index(),
                document.profiles(), properties))
            index = index + 1
        }
        return Ok(result)
    }

    static Result<String, Error> stringify(JsonValue value) {
        return Yaml.stringify(value, new YamlOptions())
    }

    static Result<String, Error> stringify(JsonValue value, YamlOptions options) {
        if value == null || options == null { throw "Yaml.stringify: null argument" }
        return formatYamlRaw(value, options.copy())
    }

    static Result<String, Error> stringifyAll(List<YamlDocument> documents) {
        return Yaml.stringifyAll(documents, new YamlOptions())
    }

    static Result<String, Error> stringifyAll(List<YamlDocument> documents,
                                               YamlOptions options) {
        if documents == null || options == null {
            throw "Yaml.stringifyAll: null argument"
        }
        String result = ""
        Int index = 0
        while index < documents.length() {
            if index > 0 { result = result + "---\n" }
            Result<String, Error> part = Yaml.stringify(documents.get(index).value(), options)
            if part.isErr() { return Err(part.error()) }
            result = result + part.value()
            index = index + 1
        }
        return Ok(result)
    }

    private static void flattenValue(JsonValue value, String prefix,
                                      Map<String, String> output) {
        if value.isObject() {
            JsonObject object = value.asObject() as JsonObject
            List<String> keys = object.keys()
            Int index = 0
            while index < keys.length() {
                String key = keys.get(index)
                if key == "" { throw "Yaml.flattenValue: empty key" }
                String path = key
                if prefix != "" { path = prefix + "." + key }
                Yaml.flattenValue(object.get(key), path, output)
                index = index + 1
            }
            return
        }
        if value.isArray() {
            JsonArray array = value.asArray() as JsonArray
            Int index = 0
            while index < array.length() {
                String path = prefix + "[" + str(index) + "]"
                Yaml.flattenValue(array.get(index), path, output)
                index = index + 1
            }
            return
        }
        output.put(prefix, Yaml.scalarText(value))
    }

    private static String scalarText(JsonValue value) {
        if value.isNull() { return "" }
        if value.isBool() {
            if value.asBool() as Bool { return "true" }
            return "false"
        }
        if value.isNumber() { return (value.asNumber() as JsonNumber).raw() }
        if value.isString() { return value.asString() as String }
        return ""
    }

    private static Result<List<String>, Error> profilesFrom(JsonValue value,
                                                             String profileKey) {
        if profileKey == "" { return Ok([]) }
        if !value.isObject() { return Ok([]) }
        JsonObject object = value.asObject() as JsonObject
        JsonValue? found = Yaml.lookupPath(object, profileKey)
        if found == null { return Ok([]) }
        if found.isString() {
            List<String> result = []
            result.push(found.asString() as String)
            return Ok(result)
        }
        if found.isArray() {
            JsonArray array = found.asArray() as JsonArray
            List<String> result = []
            Int index = 0
            while index < array.length() {
                JsonValue item = array.get(index)
                if !item.isString() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "profile entries must be strings"))
                }
                result.push(item.asString() as String)
                index = index + 1
            }
            return Ok(result)
        }
        return Err(new BasicError(ErrorKind.InvalidArgument,
            "profile value must be a string or an array of strings"))
    }

    private static JsonValue? lookupPath(JsonObject object, String path) {
        List<String> parts = path.split(".")
        JsonObject current = object
        Int index = 0
        while index < parts.length() {
            JsonValue? next = current.getOrNull(parts.get(index))
            if next == null { return null }
            if index == parts.length() - 1 { return next }
            if !next.isObject() { return null }
            current = next.asObject() as JsonObject
            index = index + 1
        }
        return null
    }
}
```
