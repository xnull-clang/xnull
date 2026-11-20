# xdk.text —— T0 文本面 v1.0

| 项 | 值 |
| --- | --- |
| 包 | `xdk.text` |
| 层级 | T0 |
| 稳定性 | 核心 `stable`；扩展 `preview` |
| 依赖 | `xdk.errors`、`xdk.bytes` |
| 被依赖 | log、config、cli、codec（T1） |
| 对应源码 | `src/xdk/text/base/*.x`、`src/xdk/text/full/*.x` |
| 当前状态 | Partial（base/full 场景通过；命名与字符集边界待补） |

## 1. 能力

| 能力 | 说明 | 承载 |
| --- | --- | --- |
| CAP-1 查找/判断 | contains、indexOf、isEmpty、isBlank、equalsIgnoreCase | 顶层函数 |
| CAP-2 变换 | trim、split、replace、reverse、capitalize、truncate | 顶层函数 |
| CAP-3 填充/重复 | padLeft、padRight、repeatText、repeatJoined | 顶层函数 |
| CAP-4 解析 | parseInt、parseFloat，全串消费、溢出报错 | `Result` 函数 |
| CAP-5 格式化 | `Format` 链式宽度/填充 | `Format` |
| CAP-6 Unicode | UTF-8 ↔ UTF-16、code point 访问 | T0-X |
| CAP-7 正则 | POSIX ERE 子集 | T0-X |

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

- 文本索引单位是字节；Unicode 码点操作使用 T0-X 函数。
- 所有函数不修改入参；`String` 不可变。
- `Format` 只做左填充，不实现 printf 全格式。

## 3. 错误与边界

- `parseInt` 的溢出上限是 32 位 `Int`；64 位值使用 `xdk.math`/`Long` 方案。
- UTF-8 非法字节替换为 U+FFFD；UTF-16 非法代理对返回 `DataCorrupted`。
- Regex 编译失败返回 `InvalidArgument`，不 panic。

## 4. 示例与反例

```text
Result<Int, Error> number = parseInt("42")
if number.isErr() { print(number.error().describe()) }
String padded = padLeft("7", 3, "0")      // 007
Format.int(7).width(4).pad('0').build()   // 0007
```

反例：

- 用 `parseInt` 解析带空白的字符串；
- 用 `replace` 传正则；
- 用字节索引切分 UTF-8 字符中间。

## 5. 测试义务

- 空串/非法字符/32 位溢出；
- 填充/重复边界；
- UTF-8 ↔ UTF-16、非法代理对；
- Regex 字面量/量词子集；
- base/full 输出一致。

场景：`xdk_text.x`、`xdk_text_full.x`。

## 6. 已知缺口

- 源码公开参数仍有短名（`s`、`xs`、`sep` 等），需在源码命名 lint 阶段统一；
- 完整 Unicode 大小写/规范化不在 T0；
- T0-X Regex 只是 ERE 子集；
- `Format` 只覆盖左填充，printf 风格格式属于后续。
