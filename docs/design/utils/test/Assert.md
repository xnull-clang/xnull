# `Assert`

| 项 | 值 |
| --- | --- |
| 类型 | `class Assert`（静态命名空间） |
| 包 | `xdk.test` |
| 稳定性 | `preview` |
| 依赖 | `BasicError`、`ErrorKind`、`Error`、`Result`、`Unit`、`String`、`trim`、`replace` |

---

## 1. 定位

测试断言静态命名空间：布尔、相等、空值、数值比较、文本包含/前缀/后缀、错误断言与显式失败。

不做：测试执行、日志缓冲、终端输出、i18n、深度对象比较、自定义 matcher、异常捕获、重试。

断言失败返回 `Err`；不使用 XNull 的 `throw`（`throw` 是 fatal/不可捕获）。

---

## 2. 设计逻辑

- 无字段、无静态可变状态；所有方法为纯函数。
- 成功统一 `Ok(unit)`；失败统一 `Err(assertionError(...))`。
- XNull 的 `throw` 是 fatal 且不可捕获；语义上的“抛出断言错误”在 API 上表达为返回 `Err(assertion error)`，由 `TestRunner` 接收并映射为 `Failed`。
- 断言错误固定为 `BasicError(ErrorKind.Internal, message).withCode("test.assertion_failed")`。
- `message` 为空时按断言生成默认文案；自定义文案与默认文案都去首尾空白，并把 CR/LF/Tab 替换为空格，保证单行。
- 参数合同错误（必需引用为 null、操作回调为 null）用 `throw` panic；断言失败不用 `throw`。
- `equals` 使用 `==`：值类型按值、`String` 按内容、引用类型默认按身份。
- `lessThan`/`greaterThan` 提供 `Int`、`Long`、`Double` 重载；NaN 比较为 false，因此断言失败。
- `contains`/`startsWith`/`endsWith` 的空片段视为 true。
- `throwsError` 执行一个 `Result` 操作：操作返回 `Err` 时得到 `Ok(error)`，操作返回 `Ok` 时得到断言错误。
- `fail` 无条件返回断言错误。
- 无全局状态；不读取当前测试、不写日志。

---

## 3. 表示与不变量

无字段。

| 不变量 | 说明 |
| --- | --- |
| 无状态 | 类只有静态方法；构造器私有 |
| 成功形态 | 每个断言成功都返回 `Ok(unit)` |
| 失败形态 | 每个断言失败都返回 `Err`，错误 code 固定为 `test.assertion_failed` |
| 错误单行 | 断言错误 `describe()` 不含换行/Tab |
| 参数合同 | null 必需参数 panic，不转成断言失败 |
| 无异常控制流 | 断言不使用 `throw` 表达失败 |

---

## 4. 生命周期

静态命名空间；无实例、无 close、无资源；从进程启动到结束均可用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Assert()` | 无 | 私有 | 外部 `new Assert()` → 编译错误 |

断言通过静态方法调用，不创建实例。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `isTrue` | 断言为 true | `Bool condition, String message` | `Result<Unit, Error>` | 断言错误 |
| `isFalse` | 断言为 false | `Bool condition, String message` | `Result<Unit, Error>` | 断言错误 |
| `equals<T>` | 断言相等 | `T expected, T actual, String message` | `Result<Unit, Error>` | 断言错误 |
| `notEquals<T>` | 断言不等 | `T expected, T actual, String message` | `Result<Unit, Error>` | 断言错误 |
| `isNull<T>` | 断言为 null | `T? value, String message` | `Result<Unit, Error>` | 断言错误 |
| `isNotNull<T>` | 断言非 null | `T? value, String message` | `Result<Unit, Error>` | 断言错误 |
| `lessThan` | 断言小于 | `Int/Int`、`Long/Long`、`Double/Double` + `String message` | `Result<Unit, Error>` | 断言错误 |
| `greaterThan` | 断言大于 | `Int/Int`、`Long/Long`、`Double/Double` + `String message` | `Result<Unit, Error>` | 断言错误 |
| `contains` | 文本包含 | `String text, String fragment, String message` | `Result<Unit, Error>` | 断言错误 |
| `startsWith` | 文本前缀 | `String text, String prefix, String message` | `Result<Unit, Error>` | 断言错误 |
| `endsWith` | 文本后缀 | `String text, String suffix, String message` | `Result<Unit, Error>` | 断言错误 |
| `throwsError<T>` | 断言操作返回 Err | `Result<T,Error>() operation, String message` | `Result<Error, Error>` | 断言错误 |
| `fail` | 显式失败 | `String message` | `Result<Unit, Error>` | 总是断言错误 |

说明：

- 断言错误精确类型：`BasicError`，`kind()` 为 `ErrorKind.Internal`，`code()` 为 `test.assertion_failed`，`describe()` 为 `[test.assertion_failed] Internal: <message>`。`kind` 只作粗分类；`TestRunner` 与消费者只匹配 code。
- `message == null` 是合同错误，panic；`message` 为空白时使用默认文案。
- `equals` 的 `expected == actual` 对引用类型是身份比较；需要内容比较时，调用方先计算 `Bool` 再调用 `isTrue`。
- `lessThan`/`greaterThan` 的 `Double` 重载对 NaN 返回断言失败，不 panic。
- `contains`/`startsWith`/`endsWith` 的 `text`、片段参数为 null 时 panic；片段为空时成功。
- `throwsError` 只接受同步 `Result` 操作；操作内部的 panic/`throw` 不被捕获。
- `fail` 用于“到这里就是失败”的分支；等价于返回一个断言错误。

---

## 8. 使用的技术

- 静态纯函数；
- `Result` 错误通道；
- 固定错误 code；
- 单行消息规范化；
- 泛型方法与数值重载；
- 文本查找。

---

## 9. 需要的支撑

- 语言：class、static 方法、泛型方法、方法重载、Bool、Int、Long、Double、String、Result、Unit、可空类型；
- 运行时：无；
- 接口：`BasicError`、`ErrorKind`、`Error`、`trim`、`replace`、`str`。

---

## 10. 依赖的特性/接口/类

`BasicError`、`ErrorKind`、`Error`、`Result`、`Unit`、`String` 方法 `contains`/`startsWith`/`endsWith`、`trim`、`replace`、`str`。

---

## 11. 所有权与并发

无实例、无状态、无资源；所有方法可并发调用；不共享日志或上下文；线程安全。

---

## 12. 示例与反例

正确：

```xnull
Result<Unit, Error> checked = Assert.equals(200, status, "unexpected status")
if checked.isErr() { return Err(checked.error()) }
```

反例：用 `Assert` 写日志；把断言错误当 panic；期望 `equals` 对两个不同实例做内容比较；用 `fail` 代替正常分支返回；忽略 `Result`（语言 `@mustUse` 会拒绝）。

---

## 13. 测试/场景义务

每个断言的通过与失败；空消息默认文案；消息中的换行/Tab 规范化；null 参数 panic；`equals` 的引用身份语义；`lessThan`/`greaterThan` 三种数值重载与 NaN；空片段；`throwsError` 的 Ok/Err；`fail` 总是失败；错误 kind/code/describe；并发调用无状态。

---

## 14. XNull 伪代码

```xnull
class Assert {
    private Assert() {
    }

    static Result<Unit, Error> isTrue(Bool condition, String message) {
        if condition { return Ok(unit) }
        return Err(assertionError(messageOr(message, "expected true")))
    }

    static Result<Unit, Error> isFalse(Bool condition, String message) {
        if !condition { return Ok(unit) }
        return Err(assertionError(messageOr(message, "expected false")))
    }

    static Result<Unit, Error> equals<T>(T expected, T actual, String message) {
        if expected == actual { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected " + str(expected) + ", got " + str(actual)
        )))
    }

    static Result<Unit, Error> notEquals<T>(T expected, T actual, String message) {
        if expected != actual { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected values to differ: " + str(actual)
        )))
    }

    static Result<Unit, Error> isNull<T>(T? value, String message) {
        if value == null { return Ok(unit) }
        return Err(assertionError(messageOr(message, "expected null")))
    }

    static Result<Unit, Error> isNotNull<T>(T? value, String message) {
        if value != null { return Ok(unit) }
        return Err(assertionError(messageOr(message, "expected non-null")))
    }

    static Result<Unit, Error> lessThan(Int actual, Int expected, String message) {
        if actual < expected { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected " + str(actual) + " < " + str(expected)
        )))
    }

    static Result<Unit, Error> lessThan(Long actual, Long expected, String message) {
        if actual < expected { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected " + str(actual) + " < " + str(expected)
        )))
    }

    static Result<Unit, Error> lessThan(Double actual, Double expected, String message) {
        if actual < expected { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected " + str(actual) + " < " + str(expected)
        )))
    }

    static Result<Unit, Error> greaterThan(Int actual, Int expected, String message) {
        if actual > expected { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected " + str(actual) + " > " + str(expected)
        )))
    }

    static Result<Unit, Error> greaterThan(Long actual, Long expected, String message) {
        if actual > expected { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected " + str(actual) + " > " + str(expected)
        )))
    }

    static Result<Unit, Error> greaterThan(Double actual, Double expected, String message) {
        if actual > expected { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected " + str(actual) + " > " + str(expected)
        )))
    }

    static Result<Unit, Error> contains(String text, String fragment, String message) {
        if text == null || fragment == null {
            throw "Assert.contains: null argument"
        }
        if text.contains(fragment) { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected text to contain " + fragment
        )))
    }

    static Result<Unit, Error> startsWith(String text, String prefix, String message) {
        if text == null || prefix == null {
            throw "Assert.startsWith: null argument"
        }
        if text.startsWith(prefix) { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected text to start with " + prefix
        )))
    }

    static Result<Unit, Error> endsWith(String text, String suffix, String message) {
        if text == null || suffix == null {
            throw "Assert.endsWith: null argument"
        }
        if text.endsWith(suffix) { return Ok(unit) }
        return Err(assertionError(messageOr(
            message,
            "expected text to end with " + suffix
        )))
    }

    static Result<Error, Error> throwsError<T>(
        Result<T, Error>() operation,
        String message
    ) {
        if operation == null {
            throw "Assert.throwsError: null operation"
        }
        Result<T, Error> result = operation()
        if result.isErr() { return Ok(result.error()) }
        return Err(assertionError(messageOr(
            message,
            "expected operation to fail"
        )))
    }

    static Result<Unit, Error> fail(String message) {
        return Err(assertionError(messageOr(message, "explicit failure")))
    }

    private static String messageOr(String message, String fallback) {
        if message == null {
            throw "Assert: null message"
        }
        String text = singleLine(trim(message))
        if text == "" { return singleLine(fallback) }
        return text
    }

    private static String singleLine(String text) {
        String result = replace(text, "\n", " ")
        result = replace(result, "\r", " ")
        result = replace(result, "\t", " ")
        return result
    }

    private static BasicError assertionError(String message) {
        if message == null || message == "" {
            throw "Assert.assertionError: empty message"
        }
        return new BasicError(ErrorKind.Internal, message).withCode("test.assertion_failed")
    }
}
```
