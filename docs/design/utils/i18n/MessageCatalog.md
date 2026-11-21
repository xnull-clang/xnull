# `MessageCatalog`

| 项 | 值 |
| --- | --- |
| 类型 | `class MessageCatalog` |
| 包 | `xdk.i18n` |
| 稳定性 | `preview` |
| 依赖 | `Locale`、`Context`、`Path`、`Reader`、`Map`、`List`、`BasicError`、`ErrorKind` |

---

## 1. 定位

单 locale 的键值消息目录：`add`/`get`/`getOr`/`has`/`remove`/`merge`/`keys`/`length`，以及从 UTF-8 属性文件或 `Reader` 加载。

不做：全局目录表、跨 locale 合并、复数/数字/日期规则、二进制资源包、热加载、翻译管理、消息继承链。

---

## 2. 设计逻辑

- 字段 `_locale` 与 `_messages: Map<String,String>`；一个目录只属于一个 locale。
- key 必须是 `[A-Za-z0-9_.-]` 且非空；value 可为空字符串，不可为 null。
- `add` 对重复 key 返回 `InvalidArgument`，不静默覆盖。
- `merge` 只接受同 locale；先检查冲突，再写入，保证失败时目录不变。
- 文件格式是 UTF-8 属性子集：`key=value`、空行、`#`/`!` 注释、`\n`/`\t`/`\r`/`\\`/`\=`/`\uXXXX` 转义。
- `load` 内部打开并关闭文件；`loadFromReader` 只读，不关闭调用方的 Reader。
- 目录可变，非线程安全；构造完成后只读共享，写入需外部同步。
- 没有全局目录；调用方持有目录并把 locale 显式传给格式化器/翻译器。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_locale` | `Locale` | 目录所属 locale |
| `_messages` | `Map<String,String>` | 消息键值 |

不变量：`_locale` 非 null；所有 key 合法；key 唯一；value 非 null；目录不隐含其他 locale。

---

## 4. 生命周期

`MessageCatalog(locale)` 创建空目录；`load`/`loadFromReader`/`parse` 返回已填充目录；可继续 `add`/`remove`/`merge`；无 close；`copy` 产生独立副本；GC 管理内存。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MessageCatalog(Locale locale)` | locale | 非 null | null → panic |
| `MessageCatalog.load(Context, Locale, Path)` | 上下文/locale/路径 | 文件存在且 UTF-8 | `NotFound`/`PermissionDenied`/`DataCorrupted`/`InvalidArgument`/`Cancelled` |
| `MessageCatalog.loadFromReader(Context, Locale, Reader)` | 上下文/locale/Reader | 读取 UTF-8 | `Io`/`DataCorrupted`/`InvalidArgument`/`Cancelled` |
| `MessageCatalog.parse(Locale, String)` | locale/文本 | 属性子集 | `InvalidArgument` |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `locale` | 所属 locale | 无 | `Locale` | 无 |
| `add` | 添加条目 | `String key, String value` | `Result<Unit, Error>` | key 非法/重复/value null |
| `get` | 取消息 | `String key` | `Result<String, Error>` | `NotFound` |
| `getOr` | 取消息/兜底 | `String key, String fallback` | `String` | null → panic |
| `has` | 是否存在 | `String key` | `Bool` | 无 |
| `remove` | 删除 | `String key` | `Bool` | 无 |
| `merge` | 合并同 locale | `MessageCatalog other, Bool overwrite` | `Result<Int, Error>` | locale 不同/冲突 |
| `merge` | 合并同 locale（不覆盖） | `MessageCatalog other` | `Result<Int, Error>` | locale 不同/冲突 |
| `keys` | 键快照 | 无 | `List<String>` | 无 |
| `length` | 键数 | 无 | `Int` | 无 |
| `copy` | 独立副本 | 无 | `MessageCatalog` | 无 |
| `load` | 文件加载 | `Context, Locale, Path` | `Result<MessageCatalog, Error>` | 见 §5 |
| `loadFromReader` | Reader 加载 | `Context, Locale, Reader` | `Result<MessageCatalog, Error>` | 见 §5 |
| `parse` | 文本解析 | `Locale, String` | `Result<MessageCatalog, Error>` | `InvalidArgument` |

说明：

- `get` 使用 `Map.tryGet`；缺失返回 `NotFound`，不返回 null。
- `getOr` 只读，不插入；`key` 非法时按缺失处理，返回 fallback。
- `merge` 的返回值是导入条目数；`overwrite=false` 时任一冲突返回 `InvalidArgument`，且不写入任何条目。
- `merge(other)` 等价于 `merge(other, false)`；需要覆盖时显式传 `true`。
- `merge` 不复制对方 locale；locale 不等直接拒绝。
- `keys` 是快照，顺序不承诺。
- `load` 在读取成功后关闭文件；读取失败时仍尝试关闭，主错误优先。
- `loadFromReader` 不关闭 Reader；调用方负责关闭。
- `parse` 遇到重复 key 返回 `InvalidArgument`，并保留行号；首行 UTF-8 BOM 被忽略。

---

## 8. 使用的技术

- UTF-8 属性文件子集解析；
- 转义解码（含 `\uXXXX`）；
- 键校验与重复检测；
- Map 快照与复制；
- 文件/Reader 读取与关闭；
- Result 错误传播。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Int、Unit、Result、Map、List；
- 运行时：`File`、`OpenOptions`、`Reader`、`Bytes`、`BytesBuilder`、`Utf16`、`Context`；
- 接口：`Locale`、`trim`、`splitLines`、`indexOf`、`startsWith`、`parseHexInt`、`fromCodePoint`、`utf8ToUtf16`、`cancelledError`、`BasicError`、`ErrorKind`。

---

## 10. 依赖的特性/接口/类

`Locale`、`Context`、`Path`、`File`、`OpenOptions`、`Reader`、`Bytes`、`BytesBuilder`、`Utf16`、`Map`、`List`、`BasicError`、`ErrorKind`、`xdk.text` 字符串与 UTF-8 函数。

---

## 11. 所有权与并发

- 目录拥有自己的 Map；`copy` 返回独立 Map。
- `load` 拥有并关闭文件；`loadFromReader` 不拥有 Reader。
- 可变目录非线程安全；并发写需外部同步；构造完成后只读共享安全。
- `Translator` 会复制目录，避免调用方后续修改影响翻译器。

---

## 12. 示例与反例

正确：`MessageCatalog.load(ctx, Locale.parse("en-US").value(), new Path("i18n/en-US.properties"))`。  
正确：`catalog.add("welcome", "Hello")`；`catalog.getOr("missing", "Hello")`。  
正确：`catalog.merge(otherEnUs, false)` 冲突时报错且不部分写入。  
反例：用全局目录；重复 key 静默覆盖；把 `en-US` 目录合并进 `fr` 目录；`loadFromReader` 后擅自关闭 Reader；期望目录线程安全；把空 value 当成缺失。

---

## 13. 测试/场景义务

add 正常/重复/非法 key/null value；get 命中/缺失；getOr；has；remove；merge 正常/冲突/覆盖/不同 locale/空目录；keys/length；copy 独立性；parse 注释/空行/BOM/转义/等号值/重复键/缺等号/非法转义/非法 Unicode；load 文件不存在/权限/非法 UTF-8/取消/关闭；loadFromReader 短读/取消/不关闭；空目录；并发只读。

---

## 14. XNull 伪代码

```xnull
class MessageCatalog {
    final Locale _locale
    final Map<String, String> _messages

    MessageCatalog(Locale locale) {
        if locale == null {
            throw "MessageCatalog: null locale"
        }
        _locale = locale
        _messages = new Map<String, String>()
    }

    Locale locale() { return _locale }

    Result<Unit, Error> add(String key, String value) {
        if key == null || value == null {
            return Err(new BasicError(ErrorKind.InvalidArgument, "null catalog entry"))
        }
        if !MessageCatalog.isValidKey(key) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid message key: " + key))
        }
        if _messages.has(key) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "duplicate message: " + key))
        }
        _messages.put(key, value)
        return Ok(unit)
    }

    Result<String, Error> get(String key) {
        if key == null {
            throw "MessageCatalog.get: null key"
        }
        Result<String, Error> found = _messages.tryGet(key)
        if found.isErr() {
            return Err(new BasicError(ErrorKind.NotFound, "missing message: " + key))
        }
        return found
    }

    String getOr(String key, String fallback) {
        if key == null || fallback == null {
            throw "MessageCatalog.getOr: null argument"
        }
        if _messages.has(key) {
            return _messages.get(key)
        }
        return fallback
    }

    Bool has(String key) {
        if key == null { return false }
        return _messages.has(key)
    }

    Bool remove(String key) {
        if key == null { return false }
        return _messages.remove(key)
    }

    Result<Int, Error> merge(MessageCatalog other) {
        return self.merge(other, false)
    }

    Result<Int, Error> merge(MessageCatalog other, Bool overwrite) {
        if other == null {
            throw "MessageCatalog.merge: null catalog"
        }
        if !_locale.equals(other.locale()) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "catalog locale mismatch"))
        }
        List<String> incoming = other.keys()
        Int index = 0
        while index < incoming.length() {
            String key = incoming.get(index)
            if _messages.has(key) && !overwrite {
                return Err(new BasicError(ErrorKind.InvalidArgument, "duplicate message: " + key))
            }
            index = index + 1
        }
        Int imported = 0
        index = 0
        while index < incoming.length() {
            String key = incoming.get(index)
            _messages.put(key, other.getOr(key, ""))
            imported = imported + 1
            index = index + 1
        }
        return Ok(imported)
    }

    List<String> keys() {
        return _messages.keys()
    }

    Int length() {
        return _messages.length()
    }

    MessageCatalog copy() {
        MessageCatalog result = new MessageCatalog(_locale)
        result._messages.putAll(_messages)
        return result
    }

    static Result<MessageCatalog, Error> load(Context context, Locale locale, Path path) {
        if context == null || locale == null || path == null {
            throw "MessageCatalog.load: null argument"
        }
        Result<File, Error> opened = File.open(path, OpenOptions.read())
        if opened.isErr() {
            return Err(opened.error())
        }
        File file = opened.value()
        Result<String, Error> read = file.readText(context)
        Result<Unit, Error> closed = file.close()
        if read.isErr() {
            return Err(read.error())
        }
        if closed.isErr() {
            return Err(closed.error())
        }
        return MessageCatalog.parse(locale, read.value())
    }

    static Result<MessageCatalog, Error> loadFromReader(Context context, Locale locale, Reader reader) {
        if context == null || locale == null || reader == null {
            throw "MessageCatalog.loadFromReader: null argument"
        }
        if context.isCancelled() {
            return Err(cancelledError("catalog read"))
        }
        BytesBuilder builder = new BytesBuilder()
        Bytes buffer = Bytes.alloc(4096)
        while true {
            Result<Int, Error> read = reader.read(context, buffer)
            if read.isErr() {
                return Err(read.error())
            }
            Int count = read.value()
            if count == 0 {
                break
            }
            Int index = 0
            while index < count {
                builder.appendByte(buffer.get(index))
                index = index + 1
            }
            if context.isCancelled() {
                return Err(cancelledError("catalog read"))
            }
        }
        if context.isCancelled() {
            return Err(cancelledError("catalog read"))
        }
        Result<Utf16, Error> decoded = utf8ToUtf16(builder.build())
        if decoded.isErr() {
            return Err(decoded.error())
        }
        return MessageCatalog.parse(locale, decoded.value().toString())
    }

    static Result<MessageCatalog, Error> parse(Locale locale, String text) {
        if locale == null || text == null {
            throw "MessageCatalog.parse: null argument"
        }
        MessageCatalog catalog = new MessageCatalog(locale)
        List<String> lines = splitLines(text)
        Int index = 0
        while index < lines.length() {
            String line = trim(lines.get(index))
            Int lineNumber = index + 1
            index = index + 1
            if lineNumber == 1 && startsWith(line, "\uFEFF") {
                line = line.substring(1, line.length() - 1)
            }
            if line == "" || startsWith(line, "#") || startsWith(line, "!") {
                continue
            }
            Int separator = indexOf(line, "=")
            if separator < 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "line " + str(lineNumber) + ": missing '='"))
            }
            String key = trim(line.substring(0, separator))
            if key == "" {
                return Err(new BasicError(ErrorKind.InvalidArgument,
                    "line " + str(lineNumber) + ": empty key"))
            }
            Result<String, Error> decoded = MessageCatalog.decodeEscapes(
                trim(line.substring(separator + 1, line.length() - separator - 1)),
                lineNumber)
            if decoded.isErr() {
                return Err(decoded.error())
            }
            Result<Unit, Error> added = catalog.add(key, decoded.value())
            if added.isErr() {
                return Err(added.error())
            }
        }
        return Ok(catalog)
    }

    private static Result<String, Error> decodeEscapes(String text, Int lineNumber) {
        String result = ""
        Int index = 0
        while index < text.length() {
            String current = text.substring(index, 1)
            if current != "\\" {
                result = result + current
                index = index + 1
            } else {
                if index + 1 >= text.length() {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "line " + str(lineNumber) + ": trailing escape"))
                }
                String escaped = text.substring(index + 1, 1)
                if escaped == "n" {
                    result = result + "\n"
                    index = index + 2
                } else if escaped == "t" {
                    result = result + "\t"
                    index = index + 2
                } else if escaped == "r" {
                    result = result + "\r"
                    index = index + 2
                } else if escaped == "\\" {
                    result = result + "\\"
                    index = index + 2
                } else if escaped == "=" {
                    result = result + "="
                    index = index + 2
                } else if escaped == "u" {
                    if index + 6 > text.length() {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "line " + str(lineNumber) + ": short unicode escape"))
                    }
                    Result<Int, Error> code = parseHexInt(text.substring(index + 2, 4))
                    if code.isErr() {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "line " + str(lineNumber) + ": invalid unicode escape"))
                    }
                    Int value = code.value()
                    if value > 1114111 || (value >= 55296 && value <= 57343) {
                        return Err(new BasicError(ErrorKind.InvalidArgument,
                            "line " + str(lineNumber) + ": invalid code point"))
                    }
                    result = result + fromCodePoint(value)
                    index = index + 6
                } else {
                    return Err(new BasicError(ErrorKind.InvalidArgument,
                        "line " + str(lineNumber) + ": unknown escape"))
                }
            }
        }
        return Ok(result)
    }

    private static Bool isValidKey(String key) {
        if key == "" { return false }
        Int index = 0
        while index < key.length() {
            Char character = key.charAt(index)
            Bool valid = (character >= 'a' && character <= 'z')
                || (character >= 'A' && character <= 'Z')
                || (character >= '0' && character <= '9')
                || character == '_' || character == '.' || character == '-'
            if !valid { return false }
            index = index + 1
        }
        return true
    }
}
```
