# `xdk.net.uri` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.net.uri` |
| 层 | `xdk.net` / L5 |
| 依赖 | `xdk.errors`、`xdk.text`、`xdk.bytes` |
| 被依赖 | `net`、`net.http`、`net.websocket` |
| 稳定性 | `preview` |
| 文档原则 | 包级说明在本 README；每个类型一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.net.uri` 提供 URI/URL 解析、组件读取、派生、查询串和百分号编码：

- `Uri` 不可变 URI；
- `Query` 可变查询串构造器；
- 顶层百分号编码/解码函数。

不做：HTTP 语义、DNS、相对 URL 抓取、IDN/Punycode、URI 模板、文件 URI 特殊语义、浏览器 URL 规范化。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 严格解析 | 非法 scheme/port/百分号编码 → `InvalidArgument`/`DataCorrupted` |
| 不隐式解码 | `Uri` 组件保留原始百分号编码；解码用 Query/顶层函数 |
| 不用哨兵 | 可选组件用 `String?`/`Int?`；空串是合法组件值 |
| 不可变 Uri | `with*` 返回新实例；可跨任务共享 |
| 可变 Query | 显式构建器；`Uri.query()` 返回副本 |
| 无全局状态 | 无全局缓存、无默认 base URI |
| 无 IDN | 国际化域名 X；只处理 ASCII/已编码文本 |
| 无网络 | 本包不打开 socket、不解析 DNS |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `Uri` | class | 不可变 URI | [`Uri.md`](Uri.md) |
| `Query` | class | 查询串构造/读取/编码 | [`Query.md`](Query.md) |

X 未纳入本批：`UriBuilder`、`Url`、`UriTemplate`、`PercentCodec` 类（编码函数已在 README）、IDN/Punycode、`normalize` 的完整 RFC 语义、file URI 特殊处理、IPv6 zone id。

---

## 4. 顶层函数

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isValidScheme` | scheme 合法性 | `String scheme` | `Bool` | 无 |
| `percentEncode` | 百分号编码 | `String text, String allowed` | `String` | 无 |
| `percentDecode` | 百分号解码 | `String text` | `Result<String, Error>` | `DataCorrupted` |
| `queryEncode` | 查询串编码 | `String text` | `String` | 无 |
| `queryDecode` | 查询串解码 | `String text` | `Result<String, Error>` | `DataCorrupted` |

编码规则：

- `percentEncode` 只保留 `allowed` 中的 ASCII 字符；其余 UTF-8 字节写成大写 `%HH`。
- `queryEncode` 保留 `A-Z a-z 0-9 - . _ ~`；空格编码为 `%20`。
- `queryDecode` 把 `+` 当空格，再执行百分号解码；字面 `+` 必须编码为 `%2B`。
- 非法 `%` 序列、非法 UTF-8 → `DataCorrupted`。

### 4.1 顶层函数伪代码

```xnull
Bool isValidScheme(String scheme) {
    if scheme == null || scheme == "" { return false }
    Char first = scheme.charAt(0)
    Bool firstLetter = first >= 'a' && first <= 'z'
    if !firstLetter {
        firstLetter = first >= 'A' && first <= 'Z'
    }
    if !firstLetter { return false }
    Int index = 1
    while index < scheme.length() {
        Char character = scheme.charAt(index)
        Bool letter = character >= 'a' && character <= 'z'
        if !letter { letter = character >= 'A' && character <= 'Z' }
        Bool digit = character >= '0' && character <= '9'
        if !letter && !digit && character != '+' && character != '-' && character != '.' {
            return false
        }
        index = index + 1
    }
    return true
}

String percentEncode(String text, String allowed) {
    if text == null || allowed == null { throw "percentEncode: null argument" }
    Bytes bytes = fromUtf8(text)
    String result = ""
    Int index = 0
    while index < bytes.length() {
        Int value = bytes.get(index)
        Bool keep = false
        String keptText = ""
        Int allowedIndex = 0
        while allowedIndex < allowed.length() {
            if asciiCodeAt(allowed, allowedIndex) == value {
                keep = true
                keptText = allowed.substring(allowedIndex, 1)
            }
            allowedIndex = allowedIndex + 1
        }
        if keep {
            result = result + keptText
        } else {
            result = result + "%" + hexDigit(value / 16) + hexDigit(value % 16)
        }
        index = index + 1
    }
    return result
}

Result<String, Error> percentDecode(String text) {
    if text == null { throw "percentDecode: null text" }
    Bytes bytes = Bytes.empty()
    Int index = 0
    while index < text.length() {
        Char character = text.charAt(index)
        if character == '%' {
            if index + 2 >= text.length() {
                return Err(new BasicError(ErrorKind.DataCorrupted, "truncated percent escape"))
            }
            Int high = hexValue(text.charAt(index + 1))
            Int low = hexValue(text.charAt(index + 2))
            if high < 0 || low < 0 {
                return Err(new BasicError(ErrorKind.DataCorrupted, "invalid percent escape"))
            }
            bytes.push(high * 16 + low)
            index = index + 3
        } else {
            Bytes raw = fromUtf8(str(character))
            Int rawIndex = 0
            while rawIndex < raw.length() {
                bytes.push(raw.get(rawIndex))
                rawIndex = rawIndex + 1
            }
            index = index + 1
        }
    }
    return decodeUtf8Strict(bytes)
}

String queryEncode(String text) {
    return percentEncode(text, "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

Result<String, Error> queryDecode(String text) {
    if text == null { throw "queryDecode: null text" }
    String normalized = text.replace("+", " ")
    return percentDecode(normalized)
}
```

---

## 5. 技术/支撑/依赖

- 技术：URI 组件解析/组装、查询串、UTF-8 百分号编码、相对引用解析。
- 支撑：`parseUriRaw`/`formatUriRaw`/`resolveUriRaw` 运行时原语、`fromUtf8`、`decodeUtf8Strict`、`hexDigit(Int) -> String`、`hexValue(Char) -> Int`（非法 -1）、`asciiCodeAt(String, Int) -> Int`。
- 依赖：`xdk.errors`、`xdk.text`、`xdk.bytes`。

---

## 6. 场景

### U1：解析 HTTP URL

`Uri.parse("https://user@example.com:8443/a/b?q=1#f")`；读取 scheme/host/port/path/query/fragment。

### U2：构造查询串

`Query()` + `add`/`set`；`encode()`；`Uri.withQuery(query)`。

### U3：相对引用

`base.resolve(Uri.parse("../v2?q=1"))`；由运行时 `resolveUriRaw` 实现 RFC 3986 引用解析。

### U4：百分号编码

路径/查询参数用 `queryEncode`；`percentDecode` 遇到非法 `%` 返回 `DataCorrupted`。

### U5：IPv6

`Uri.parse("http://[::1]:8080/")`；`host()` 返回 `::1`，`text()` 保留方括号。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| `UriBuilder` | X |
| `Url` | X；Uri 已覆盖必要组件 |
| `UriTemplate` | X |
| IDN/Punycode | X；不静默转换 |
| `normalize` | X；本批不做完整 RFC 点段/大小写规范化 |
| `resolve` | 本批提供；由运行时原语实现 |
| 组件解码 | `Uri` 不解码；`Query` 解码键值 |
| 空串 vs 缺失 | 可选组件用 null；path 空串合法 |
| 查询参数顺序 | 保留插入/解析顺序 |
| 重复键 | 允许；`getOrNull` 取首个 |
| `+` | `queryDecode` 当空格；字面 `+` 用 `%2B` |
