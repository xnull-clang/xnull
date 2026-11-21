# `FileSource`

| 项 | 值 |
| --- | --- |
| 类型 | `class FileSource implements ConfigSource` |
| 包 | `xdk.config` |
| 稳定性 | `preview` |
| 依赖 | `fs`、`text`、`ConfigEntry` |

---

## 1. 定位

文件配置来源：读取 UTF-8 `key=value` 文本。

不做：JSON/TOML/YAML、include、profile 自动发现。

---

## 2. 设计逻辑

- 字段 `_path`、`_name`、`_priority`。
- `load` 用 `fs.readText`；按行 split；trim；空行/`#` 注释跳过；首个 `=` 分隔；缺失 `=` 或空 key → `DataCorrupted`。
- 重复 key 保留顺序，Config/Overlay 后者覆盖。
- 文件不长期持有句柄。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `String` | 文件 |
| `_name` | `String` | 来源名 |
| `_priority` | `Int` | 优先级 |

不变量：path 非空；name 非空。

---

## 4. 生命周期

不可变；无 close；load 时读文件。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `FileSource(String path)` | path | 非空 | 空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `load` | 加载 | `Context` | `Result<List<ConfigEntry>, Error>` | `NotFound`/`DataCorrupted`/`Cancelled` |
| `name` | 名称 | 无 | `String` | 无 |
| `priority` | 优先级 | 无 | `Int` | 无 |
| `withName` | 派生 | `String` | `FileSource` | 空 → panic |
| `withPriority` | 派生 | `Int` | `FileSource` | 无 |

---

## 8. 使用的技术

- 文本行解析；
- 首个 `=` 分隔；
- trim/注释；
- UTF-8。

---

## 9. 需要的支撑

- 语言：class、String、List、Int、Result；
- 运行时：`fs.readText`；
- 接口：`ConfigSource`、`ConfigEntry`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`ConfigSource`、`ConfigEntry`、`fs.readText`、`BasicError`、`ErrorKind`。

---

## 11. 所有权与并发

不可变；可共享；文件按需打开。

---

## 12. 示例与反例

正确：`app.port=8080`；`# comment` 跳过。  
反例：空 key；行无 `=`；把 JSON 当 key=value；key 含换行。

---

## 13. 测试/场景义务

正常/空行/注释；重复 key；空 value；缺失 `=`；文件缺失；取消。

---

## 14. XNull 伪代码

```xnull
class FileSource implements ConfigSource {
    final String _path
    final String _name
    final Int _priority

    FileSource(String path) {
        if path == "" { throw "FileSource: empty path" }
        _path = path
        _name = path
        _priority = 0
    }

    FileSource withName(String name) {
        if name == "" { throw "FileSource.withName: empty" }
        FileSource result = new FileSource(_path)
        result._name = name
        return result
    }

    FileSource withPriority(Int priority) {
        FileSource result = new FileSource(_path)
        result._priority = priority
        return result
    }

    Result<List<ConfigEntry>, Error> load(Context context) {
        Result<String, Error> text = readText(_path)
        if text.isErr() { return Err(text.error()) }
        List<ConfigEntry> result = []
        List<String> lines = splitLines(text.value())
        Int index = 0
        while index < lines.length() {
            String line = trim(lines.get(index))
            if line != "" && !line.startsWith("#") {
                Int equals = line.indexOf("=")
                if equals <= 0 {
                    return Err(new BasicError(ErrorKind.DataCorrupted, "invalid config line"))
                }
                String key = trim(line.substring(0, equals))
                String value = trim(line.substring(equals + 1, line.length() - equals - 1))
                result.push(new ConfigEntry(key, value))
            }
            index = index + 1
        }
        return Ok(result)
    }

    String name() { return _name }
    Int priority() { return _priority }
}
```
