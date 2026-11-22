# `xdk.text` 包设计

| 项 | 值 |
| --- | --- |
| 包 | `xdk.text` |
| 层 | `xdk.core` / L2 |
| 依赖 | `xdk.errors`、`xdk.bytes` |
| 被依赖 | `log`、`config`、`cli`、`codec` |
| 稳定性 | 基础 `stable`；Regex/Unicode/Escape `preview` |
| 文档原则 | 包级说明在本 README；每个类一个 PascalCase 文件 |

---

## 1. 包定位

`xdk.text` 处理文本：

- 查找/判断/变换/填充；
- 构建器/连接器/格式化；
- 数字/布尔解析与格式化；
- UTF-8/UTF-16/码点；
- 正则编译/匹配/替换/切分；
- 转义/反转义。

不做：完整 ICU、locale 大小写、模板引擎、i18n 消息目录。

---

## 2. 设计原则

| 原则 | 说明 |
| --- | --- |
| 字节索引 | 文本索引单位是字节；码点操作用 Unicode 函数 |
| 不修改入参 | String 不可变；函数返回新字符串 |
| 严格解析 | 全串消费；非法/溢出 → `Result` |
| 格式化分离 | `Format` 只做宽度/填充/对齐；数字精度由格式化函数负责 |
| 正则可失败 | 编译失败 `InvalidArgument`，不 panic |
| 无全局状态 | 无全局 locale/格式化器/正则缓存 |

---

## 3. 类型总览与索引

| 类型 | 种类 | 能力 | 文件 |
| --- | --- | --- | --- |
| `StringBuilder` | class | 可变字符串构建 | [`StringBuilder.md`](StringBuilder.md) |
| `StringJoiner` | class | 分隔符连接 | [`StringJoiner.md`](StringJoiner.md) |
| `Format` | class | 宽度/填充/对齐 | [`Format.md`](Format.md) |
| `TextAlign` | enum | 左/右/居中 | [`TextAlign.md`](TextAlign.md) |
| `RegexOptions` | class | 正则选项 | [`RegexOptions.md`](RegexOptions.md) |
| `NormalizationForm` | enum | NFC/NFD/NFKC/NFKD | [`NormalizationForm.md`](NormalizationForm.md) |
| `Regex` | class | 编译/匹配/替换/切分 | [`Regex.md`](Regex.md) |
| `Match` | class | 匹配结果/捕获组 | [`Match.md`](Match.md) |
| `Utf16` | class | UTF-16 码元序列 | [`Utf16.md`](Utf16.md) |
| `Unicode` | class | 码点/字符分类/规范化 | [`Unicode.md`](Unicode.md) |
| `Escape` | class | 转义/反转义 | [`Escape.md`](Escape.md) |

---

## 4. 顶层函数

### 4.1 判断/查找

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `contains` | 是否包含 | `String text, String searchText` | `Bool` | 无 |
| `startsWith` | 前缀 | `String text, String prefix` | `Bool` | 无 |
| `endsWith` | 后缀 | `String text, String suffix` | `Bool` | 无 |
| `indexOf` | 首次位置 | `String text, String searchText` | `Int` | 无（-1 缺失） |
| `lastIndexOf` | 末次位置 | 同上 | `Int` | 无（-1 缺失） |
| `containsAny` | 任一子串 | `String text, List<String> searchTexts` | `Bool` | null → panic |
| `countText` | 非重叠次数 | `String text, String searchText` | `Int` | 无 |
| `isEmpty` | 空串 | `String text` | `Bool` | 无 |
| `isBlank` | 全空白 | `String text` | `Bool` | 无 |
| `isAscii` | 全 ASCII | `String text` | `Bool` | 无 |
| `isNumeric` | 全数字 | `String text` | `Bool` | 无 |
| `isAlpha` | 全字母 | `String text` | `Bool` | 无 |
| `isAlnum` | 字母数字 | `String text` | `Bool` | 无 |
| `isLower` | 全小写 | `String text` | `Bool` | 无 |
| `isUpper` | 全大写 | `String text` | `Bool` | 无 |
| `equalsIgnoreCase` | 忽略大小写 | `String left, String right` | `Bool` | 无 |
| `compareIgnoreCase` | 忽略大小写比较 | 同上 | `Int` | 无 |

### 4.2 变换

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `trim` | 去首尾空白 | `String text` | `String` | 无 |
| `trimStart` | 去首部空白 | `String text` | `String` | 无 |
| `trimEnd` | 去尾部空白 | `String text` | `String` | 无 |
| `stripIndent` | 去公共缩进 | `String text` | `String` | 无 |
| `normalizeWhitespace` | 空白归一 | `String text` | `String` | 无 |
| `split` | 分隔符切分 | `String text, String separator` | `List<String>` | 无 |
| `splitLines` | 按行切分 | `String text` | `List<String>` | 无 |
| `splitWhitespace` | 按空白切分 | `String text` | `List<String>` | 无 |
| `replace` | 字面量替换 | `String text, String searchText, String replacementText` | `String` | 无 |
| `replaceFirst` | 替换首个 | 同上 | `String` | 无 |
| `replaceAll` | 替换全部 | 同上 | `String` | 无 |
| `removePrefix` | 去前缀 | `String text, String prefix` | `String` | 无 |
| `removeSuffix` | 去后缀 | `String text, String suffix` | `String` | 无 |
| `reverse` | 反转 | `String text` | `String` | 无 |
| `capitalize` | 首字母大写 | `String text` | `String` | 无 |
| `decapitalize` | 首字母小写 | `String text` | `String` | 无 |
| `truncate` | 截断字节 | `String text, Int maximumBytes` | `String` | 负值 → panic |
| `wrap` | 换行包裹 | `String text, Int width` | `String` | 非正 width → panic |
| `indent` | 缩进 | `String text, String prefix` | `String` | 无 |
| `padLeft` | 左填充 | `String text, Int width, String padding` | `String` | 负 width → panic |
| `padRight` | 右填充 | 同上 | `String` | 负 width → panic |
| `repeatText` | 重复 | `String text, Int repetitions` | `String` | 负值 → panic |
| `repeatJoined` | 带分隔重复 | `String text, String separator, Int repetitions` | `String` | 负值 → panic |

### 4.3 解析/格式化

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `parseInt` | 32 位整数 | `String text` | `Result<Int, Error>` | `InvalidArgument` |
| `parseLong` | 64 位整数 | `String text` | `Result<Long, Error>` | `InvalidArgument` |
| `parseFloat` | 浮点 | `String text` | `Result<Double, Error>` | `InvalidArgument` |
| `parseDouble` | 双精度 | `String text` | `Result<Double, Error>` | `InvalidArgument` |
| `parseBool` | 布尔 | `String text` | `Result<Bool, Error>` | `InvalidArgument` |
| `parseHexInt` | 十六进制 | `String text` | `Result<Int, Error>` | `InvalidArgument` |
| `parseBinaryInt` | 二进制 | `String text` | `Result<Int, Error>` | `InvalidArgument` |
| `formatInt` | 整数格式化 | `Int value` | `Format` | 无 |
| `formatLong` | Long 格式化 | `Long value` | `Format` | 无 |
| `formatFloat` | 浮点格式化 | `Double value, Int precision` | `String` | 负 precision → panic |
| `formatDouble` | 双精度格式化 | `Double value, Int precision` | `String` | 负 precision → panic |
| `formatBool` | 布尔格式化 | `Bool value` | `Format` | 无 |
| `formatHex` | hex 格式化 | `Long value` | `String` | 无 |
| `formatBinary` | 二进制格式化 | `Long value` | `String` | 无 |
| `formatBytes` | 字节格式化 | `Bytes value` | `String` | 无 |

### 4.4 Unicode / 正则

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `utf8ToUtf16` | UTF-8 → UTF-16 | `Bytes source` | `Result<Utf16, Error>` | `DataCorrupted` |
| `utf16ToUtf8` | UTF-16 → UTF-8 | `List<UInt16> units` | `Result<Bytes, Error>` | `DataCorrupted` |
| `codePoints` | 码点序列 | `String text` | `List<Int>` | 无 |
| `codePointAt` | 指定字节位置码点 | `String text, Int byteIndex` | `Int` | 越界/非法 → panic |
| `codePointLen` | 码点字节长度 | `String text, Int byteIndex` | `Int` | 越界/非法 → panic |
| `fromCodePoint` | 码点转字符串 | `Int codePoint` | `String` | 非法 → panic |
| `decodeCodePoint` | 解码一个码点 | `String text, Int byteIndex` | `Int` | 非法 → panic |
| `regexCompile` | 编译正则 | `String pattern` | `Result<Regex, Error>` | `InvalidArgument` |
| `regexIsMatch` | 是否匹配 | `String pattern, String text` | `Result<Bool, Error>` | `InvalidArgument` |
| `regexFind` | 首个匹配 | `String pattern, String text` | `Result<Match?, Error>` | `InvalidArgument` |
| `regexFindAll` | 全部匹配 | `String pattern, String text` | `Result<List<Match>, Error>` | `InvalidArgument` |
| `regexReplaceAll` | 全部替换 | `String pattern, String text, String replacement` | `Result<String, Error>` | `InvalidArgument` |
| `regexEscape` | 转义元字符 | `String text` | `String` | 无 |

### 4.5 使用的技术

- 字节索引 + UTF-8 解码；
- 字符分类表/Unicode 表；
- 正则解析/匹配引擎；
- 字符串构建/连接；
- 数字解析/格式化；
- 转义表。

### 4.6 需要的支撑

- 语言：String、Char、Int、Long、Double、Bool、List、Bytes、Result；
- 运行时：UTF-8 编解码、字符分类、正则引擎；
- 接口：`Error`、`BasicError`、`ErrorKind`、`Bytes`、`Utf16`、`Regex`、`Format`、`StringBuilder`。

### 4.7 依赖的特性/接口/类

`errors`、`bytes`、`StringBuilder`、`StringJoiner`、`Format`、`Regex`、`Match`、`Utf16`、`Unicode`、`Escape`。

---

## 5. 关键函数伪代码

### 5.1 `parseInt` / `parseLong`

```xnull
Result<Int, Error> parseInt(String text) {
    if text == "" {
        return Err(new BasicError(ErrorKind.InvalidArgument, "empty number"))
    }
    Int index = 0
    Bool negative = false
    if text.charAt(0) == '-' {
        negative = true
        index = 1
    } else if text.charAt(0) == '+' {
        index = 1
    }
    if index >= text.length() {
        return Err(new BasicError(ErrorKind.InvalidArgument, "no digits"))
    }
    Long value = 0
    while index < text.length() {
        Char character = text.charAt(index)
        if character < '0' || character > '9' {
            return Err(new BasicError(ErrorKind.InvalidArgument, "invalid digit"))
        }
        value = value * 10 + (character as Int - 48)
        if value > 2147483648 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "overflow"))
        }
        index = index + 1
    }
    if negative {
        value = 0 - value
    }
    if value > 2147483647 || value < -2147483648 {
        return Err(new BasicError(ErrorKind.InvalidArgument, "overflow"))
    }
    return Ok(value as Int)
}
```

### 5.2 `split`

```xnull
List<String> split(String text, String separator) {
    List<String> result = []
    if separator == "" {
        result.push(text)
        return result
    }
    Int start = 0
    Int index = 0
    while index <= text.length() - separator.length() {
        if text.substring(index, separator.length()) == separator {
            result.push(text.substring(start, index - start))
            index = index + separator.length()
            start = index
        } else {
            index = index + 1
        }
    }
    result.push(text.substring(start, text.length() - start))
    return result
}
```

### 5.3 `formatFloat` / `formatDouble`

```xnull
String formatFloat(Double value, Int precision) {
    if precision < 0 {
        throw "formatFloat: negative precision"
    }
    if precision == 0 {
        return str(round(value))
    }
    Double scale = powerOfTen(precision)
    Double rounded = round(value * scale) / scale
    String text = str(rounded)
    Int dot = indexOf(text, ".")
    if dot < 0 {
        text = text + "."
        dot = text.length() - 1
    }
    Int digits = text.length() - dot - 1
    while digits < precision {
        text = text + "0"
        digits = digits + 1
    }
    if digits > precision {
        text = text.substring(0, dot + precision + 1)
    }
    return text
}
```

### 5.4 `regexCompile` / `regexReplaceAll`

```xnull
Result<Regex, Error> regexCompile(String pattern) {
    return Regex.compile(pattern)
}

Result<String, Error> regexReplaceAll(String pattern, String text, String replacement) {
    Result<Regex, Error> compiled = Regex.compile(pattern)
    if compiled.isErr() {
        return Err(compiled.error())
    }
    return Ok(compiled.value().replaceAll(text, replacement))
}
```

---

## 6. 场景

### S2：CLI 参数/配置文本

`trim`、`split`、`parseInt`、`parseBool`、`Format` 输出；非法输入 `InvalidArgument`。

### S3：协议文本字段

`utf8ToUtf16`/`utf16ToUtf8`、`codePoints`、`Utf16`；非法代理对 `DataCorrupted`。

### S4：日志/配置格式化

`Format.int().width().pad()`、`StringBuilder` 拼接；不修改入参。

### S5：数据清洗

`splitLines`/`splitWhitespace`/`replace`/`dedup`（collections）组合；大文本按行处理。

### S5：正则校验/提取

`regexCompile` + `isMatch`/`findAll`；编译失败 `InvalidArgument`；不 panic。

### S6：转义/反转义

`Escape.json/html/csv/shell`；输出可逆/可解析。

---

## 7. 缺口与决策

| 项 | 决策 |
| --- | --- |
| 完整 Unicode 规范化 | X/ICU； 只做常用分类/大小写 |
| 正则引擎 | 2.x 只保留 `xdk.text.Regex` 子集；完整引擎不在 2.x 包表 |
| locale 大小写 | `xdk.i18n` |
| 模板引擎 | 不属于 XDK |
| 字符串内部表示 | 不暴露 |
| 文本索引 | 字节索引；码点用 Unicode 函数 |
| Format 精度 | 精度在 `formatFloat/Double`，不在 `Format` |
| 大文本 | 按行/分块；`StringBuilder` 不是流 |

---

## 注解与生成

| 项 | 内容 |
| --- | --- |
| 本包声明 | 无领域注解 |
| 本包消费 | `@Value`、`@Builder`、`@Copy`、`@Override` |
| 处理器 | 标准 A8 / 编译器内建 |
| 生成物 | 匹配/格式/正则选项派生成员 |
| 状态 | 无领域注解；A8 派生 implemented（含限制）；编译器内建 implemented |

### 具体落点

| 类型/成员 | 注解 | 生成/检查 |
| --- | --- | --- |
| `Match`/`Format` | `@Value` | 值语义成员 |
| `RegexOptions` | `@Builder` | 选项构造 |
| `Regex`/`Unicode` 等入口 | — | 静态/实例方法，不强行套派生 |

规则：注解是编译期契约/生成入口；处理器显式启用、沙箱、确定性、失败原子；运行时只读生成的 `AnnotationRegistry`，无反射/扫描/动态代理。

完整声明与 75 包矩阵见 [`ANNOTATION-ADOPTION.md`](../../ANNOTATION-ADOPTION.md)、逐条状态见 [`ANNOTATION-CATALOG.md`](../../ANNOTATION-CATALOG.md)。
