# xdk.text —— T0 文本面 v1.1

| 项 | 值 |
| --- | --- |
| 包 | `xdk.text` |
| 层级 | T0 |
| 稳定性 | 核心 `stable`；扩展 `preview` |
| 依赖 | `xdk.errors`、`xdk.bytes` |
| 被依赖 | log、config、cli、codec（T1） |
| 对应源码 | `src/xdk/text/full/*.x`（`src/xdk/text/base/*.x` 与 full 同源） |
| 当前状态 | Verified |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 查找/判断 | contains、indexOf、isEmpty、isBlank、equalsIgnoreCase | 顶层函数 |
| CAP-2 变换 | trim、split、replace、reverse、capitalize、truncate | 顶层函数 |
| CAP-3 填充/重复 | padLeft、padRight、repeatText、repeatJoined | 顶层函数 |
| CAP-4 解析 | parseInt、parseFloat，全串消费、溢出报错 | `Result` 函数 |
| CAP-5 格式化 | `Format` 链式宽度/填充；printf 风格 `printf` | `Format`、`FormatArgument` |
| CAP-6 Unicode | UTF-8 ↔ UTF-16、code point 访问与计数 | 顶层函数、`Utf16` |
| CAP-7 正则 | POSIX ERE 子集：字面量、量词、类、分组、分支、锚 | `Regex`、`Match` |
| CAP-8 比较 | UTF-8 字节字典序比较，供排序/查找使用 | `compareText` |
| CAP-9 构造 | append-only 文本构造；长度与不可变快照 | `StringBuilder` |

**非目标**：完整正则引擎（T1 `xdk.regex`）、i18n、locale、完整 Unicode
大小写/规范化、字符串内部表示 API。

## 2. 关键契约

```text
Result<Int, Error> parseInt(String text)
Result<Double, Error> parseFloat(String text)
String trim(String text)
List<String> split(String text, String separator)
String replace(String text, String searchText, String replacementText)
String padLeft(String text, Int width, String padding)
String padRight(String text, Int width, String padding)
String repeatText(String text, Int repetitions)
String repeatJoined(String text, String separator, Int repetitions)
Bool contains(String text, String searchText)
Int compareText(String left, String right)
```

| 函数 | 前置 | 后置 | 失败 |
| --- | --- | --- | --- |
| `parseInt(text)` | 十进制、可选正负号、全串消费 | 返回 32 位 `Int` | 空串/非法字符/32 位溢出 → `InvalidArgument` |
| `parseFloat(text)` | 十进制/小数/指数、全串消费 | 返回 `Double` | 非法 → `InvalidArgument` |
| `trim(text)` | 无 | 去首尾空白 | 无 |
| `split(text, separator)` | separator 可空 | 返回分段；空 separator 不分段 | 无 |
| `replace` | 无 | 字面量替换，不是正则 | 无 |
| `repeatText` | `repetitions >= 0` | 重复；0 返回空串 | 负数为合同错误 |
| `Format.build()` | width ≥ 0 | 左侧填充到 width | 无 |
| `compareText(left, right)` | 无 | 按 UTF-8 字节字典序比较：`left < right` 返回负数，相等返回 `0`，`left > right` 返回正数 | 无 |

- 文本索引单位是字节；Unicode 码点操作使用本节 T0-X 函数。
- `String` 只支持 `==`/`!=`/`===`/`!==`，不提供 `<`/`<=`/`>`/`>=`（S1 §2.8）。
  排序必须用 `compareText(a, b) < 0` 作为比较器，例如
  `sortBy(names, (String a, String b) -> compareText(a, b) < 0)`。
- 所有函数不修改入参；`String` 不可变。
- 公开 API 的值参数使用完整英文名；单字母只用于类型参数和实现循环下标。

### 2.1 Unicode

```text
Result<Utf16, Error> utf8ToUtf16(Bytes source)
Result<Bytes, Error> utf16ToUtf8(List<UInt16> units)
Utf16 textToUtf16(String text)
Result<String, Error> utf16ToText(Utf16 source)
Int codePointAt(String text, Int byteIndex)
Int codePointLen(String text, Int byteIndex)
List<Int> codePoints(String text)
Int codePointCount(String text)
String fromCodePoint(Int codePoint)
```

- `Utf16` 包装 `List<UInt16>`，提供 `length()`、`get(index)`、`isEmpty()`、`toList()`。
- UTF-8 解码拒绝过长编码、代理区码点和超出 `U+10FFFF` 的码点。
- `utf8ToUtf16` / `codePoints` 对每个非法 UTF-8 单字节写入 U+FFFD 并前进一字节；
  `codePointAt` / `codePointLen` 在非法位置返回 `-1`。
- `utf16ToUtf8` / `utf16ToText` 遇到孤立高代理或低代理返回 `DataCorrupted`。
- `fromCodePoint` 对越界或代理区码点返回 U+FFFD。
- 匹配偏移仍是 UTF-8 字节下标；`codePointCount` 用于按字符计数。

### 2.2 Regex（POSIX ERE 子集）

```text
Result<Regex, Error> regexCompile(String pattern)
Bool Regex.isMatch(String text)
Match? Regex.find(String text)
List<Match> Regex.findAll(String text)
String Regex.replaceAll(String text, String replacement)
List<String> Regex.split(String text)
Int Regex.groupCount()
String Match.group(Int groupIndex)
Int Match.length()
```

- 支持：字面量、`.`（一个码点）、`*`、`+`、`?`、`{m}`、`{m,}`、`{m,n}`、
  `(...)` 捕获组、`|`、`[...]` 类与区间、`[^...]`、`[[:alpha:]]` 等 POSIX
  名字类、`^`/`$`、转义元字符与 `\n \t \r \f \v \0`；另支持 `\d \D \w \W \s \S`。
- 量词是贪心的；不实现懒惰量词、反向引用、命名组、lookaround、`*` 宽度/精度。
- 字符类范围为码点；`.`、字面量和量词按 UTF-8 码点推进，匹配下标仍是字节。
- `replaceAll` 的替换文本是字面量，不展开 `$1`；`findAll` 跳过空匹配。
- 编译失败返回 `InvalidArgument`，不 panic；`Match.group(0)` 是整匹配。

### 2.3 printf Format

```text
Result<String, Error> printf(String pattern, List<FormatArgument> arguments)
FormatArgument FormatArgument.ofInt(Int value)
FormatArgument FormatArgument.ofLong(Long value)
FormatArgument FormatArgument.ofFloat(Double value)
FormatArgument FormatArgument.ofText(String value)
FormatArgument FormatArgument.ofBool(Bool value)
FormatArgument FormatArgument.ofChar(Char value)
```

- 语法：`%[flags][width][.precision]conversion`；`flags` 为 `-`、`+`、空格、`0`、`#`。
- 转换：`d`/`i`（十进制）、`x`/`X`/`o`（非负整数）、`f`/`e`/`E`/`g`/`G`、
  `s`、`c`、`b`（`true`/`false`）、`%%`。
- 参数按类型显式包装；类型不匹配、参数数量不等、缺转换字符或模式以 `%` 结尾
  返回 `InvalidArgument`。不支持 `*` 动态宽度和长度修饰符。
- `Format` 保留原有链式左填充：`Format.int(7).width(4).pad('0').build()`。

### 2.4 StringBuilder

```text
StringBuilder StringBuilder()
StringBuilder StringBuilder.append(String text)
StringBuilder StringBuilder.appendInt(Int value)
StringBuilder StringBuilder.appendLong(Long value)
StringBuilder StringBuilder.appendChar(Char value)
StringBuilder StringBuilder.clear()
Int StringBuilder.length()
Bool StringBuilder.isEmpty()
String StringBuilder.toString()
```

- `StringBuilder` 是引用类型、可变；append 系列返回 `self`，支持链式调用。
- `length()` 返回当前内容的 UTF-8 字节数；`toString()` 返回当前内容的不可变
  快照，后续 append 不改变已取出的快照。
- `clear()` 清空内容并返回 `self`；空 builder 的 `toString()` 为 `""`。
- 文本索引单位仍是字节；Unicode 码点操作使用 §2.1 的函数。
- 实现可以把内容承载在运行时缓冲区；公开语义以本节为准。

## 3. 错误与边界

- `parseInt` 的溢出上限是 32 位 `Int`；64 位值使用 `xdk.math`/`Long` 方案。
- UTF-8 非法字节替换为 U+FFFD；UTF-16 非法代理对返回 `DataCorrupted`。
- Regex 编译失败返回 `InvalidArgument`，不 panic。
- printf 的 `%x`/`%o` 只接受非负整数；负值返回 `InvalidArgument`。

## 4. 示例与反例

```text
Result<Int, Error> number = parseInt("42")
if number.isErr() { print(number.error().describe()) }
String padded = padLeft("7", 3, "0")      // 007
StringBuilder builder = new StringBuilder()
builder.append("n=").appendInt(7)         // "n=7"
print(builder.toString())
Format.int(7).width(4).pad('0').build()   // 0007
Int order = compareText("alpha", "beta")  // -1
Int codePoint = codePointAt("é", 0)       // 233
String repaired = utf16ToText(textToUtf16("é")).value()
Result<Regex, Error> ere = regexCompile("^(ab)+c{2,3}$")
Bool hit = ere.value().isMatch("abcc")    // true
List<FormatArgument> values = []
values.push(FormatArgument.ofInt(7))
print(printf("%04d", values).value())     // 0007
```

反例：

- 用 `parseInt` 解析带空白的字符串；
- 用 `replace` 传正则；
- 用字节索引切分 UTF-8 字符中间；
- 用 `%x` 格式化负数；
- 把 `replaceAll` 的替换文本当反向引用。

## 5. 测试义务

- 空串/非法字符/32 位溢出；
- 填充/重复边界；
- 比较：空串、前缀、相等、UTF-8 多字节字节序；
- UTF-8 ↔ UTF-16、非法 UTF-8 修复、非法代理对、BMP 外码点；
- Regex 字面量/量词（含 `{m,n}`）/字符类/POSIX 名字类/分组捕获/分支/锚；
- printf 宽度、精度、flags、类型错误与参数数量错误；
- StringBuilder 空值、链式 append、`length()` 字节计数、快照与 `clear()`；
- base/full 输出一致。

场景：`xdk_text.x`、`xdk_text_full.x`、`r4/text_builder.x`、`xdk_core.x`。

## 6. 已知缺口

- 完整 Unicode 大小写/规范化与 locale 不在 T0；
- T0-X Regex 只是 ERE 子集，完整引擎归 T1 `xdk.regex`；
- printf 不支持 `*` 动态宽度/精度、长度修饰符和 locale 分组；
- 零拷贝/可变缓冲区优化、更多 append 重载（Double/Bool）与字符集转码、i18n
  属于后续包；T0 的 `StringBuilder` 只承诺 §2.4 的 append-only 语义。
