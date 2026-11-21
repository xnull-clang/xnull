# `TestContext`

| 项 | 值 |
| --- | --- |
| 类型 | `class TestContext` |
| 包 | `xdk.test` |
| 稳定性 | `preview` |
| 依赖 | `Context`、`BasicError`、`ErrorKind`、`Error`、`Result`、`Unit`、`List`、`String`、`trim` |

---

## 1. 定位

单个测试执行期的上下文：测试名、日志缓冲、跳过信号、显式失败信号、取消视图。

不做：全局当前测试、跨测试共享、终端输出、i18n、结果聚合、统计、重试。

一个 `TestContext` 只服务一次测试执行；由 `TestRunner` 创建。

---

## 2. 设计逻辑

- 字段：测试名、核心 `Context`、日志列表。
- `log` 追加一条日志；null 是合同错误；空串允许。
- `skip` 追加 `skip: <reason>` 日志，并返回 `Err(BasicError(code=test.skipped))`。
- `fail` 追加 `fail: <message>` 日志，并返回 `Err(BasicError(code=test.failed))`。
- `skip`/`fail` 从不返回 `Ok`；它们不用 `throw`，body 必须 `return context.skip(...)` 或传播该 `Err`。
- `isCancelled` 委托给核心 `Context`；父 Context 取消或 runner 超时取消都能看到。
- 日志由 body 写入、runner 在 body 结束后读取；不做全局缓冲。
- 无全局状态；不读取当前线程/当前测试。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | final；去首尾空白后非空 |
| `_context` | `Context` | final；非 null；取消视图 |
| `_logs` | `List<String>` | 内部列表；元素非 null |

不变量：名称非空；context 非 null；日志只由本测试写入；`skip`/`fail` 只返回 `Err`；一实例一测试。

---

## 4. 生命周期

`TestRunner` 在测试开始前创建；body 通过参数使用；测试结束后 runner 读取日志快照；不跨测试复用；无 close、无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TestContext(String name, Context context)` | name/context | name 去空白非空；context 非 null | null/空白 → panic |

说明：构造器公开以允许测试工具自建上下文，但常规路径由 `TestRunner` 创建。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 测试名 | 无 | `String` | 无 |
| `log` | 追加日志 | `String text` | `void` | null → panic |
| `skip` | 跳过测试 | `String reason` | `Result<Unit, Error>` | 总是 `Err`；null/空白 reason → panic |
| `fail` | 显式失败 | `String message` | `Result<Unit, Error>` | 总是 `Err`；null/空白 message → panic |
| `isCancelled` | 是否取消 | 无 | `Bool` | 无 |
| `logs` | 日志快照 | 无 | `List<String>` | 无 |

说明：

- `skip`/`fail` 的返回值必须被 `return` 或传播；它们不会正常返回 `Ok(unit)`。忽略返回值违反 `Result` 的 `@mustUse` 规则。
- `skip` 错误：`BasicError(ErrorKind.Cancelled, reason).withCode("test.skipped")`。
- `fail` 错误：`BasicError(ErrorKind.Internal, message).withCode("test.failed")`。
- `skip`/`fail` 先写一条日志，再返回 `Err`；日志前缀固定为 `skip: `、`fail: `。
- `log` 原样保存文本，不做单行规范化；`TestResult.describe` 不输出日志正文。
- `isCancelled` 只读；取消由父 Context 或 runner 触发，`TestContext` 不提供 `cancel`。
- `logs()` 返回副本；runner 在 body 结束后读取。

---

## 8. 使用的技术

- 每测试日志缓冲；
- 取消委托；
- 固定错误 code；
- `Result` 控制流；
- 防御性快照。

---

## 9. 需要的支撑

- 语言：class、final 字段、可空引用、Bool、String、List、Result、Unit；
- 运行时：`Context` 取消可见性；
- 接口：`BasicError`、`ErrorKind`、`Error`、`Context`、`trim`。

---

## 10. 依赖的特性/接口/类

`Context`、`BasicError`、`ErrorKind`、`Error`、`Result`、`Unit`、`List`、`String`、`trim`。

---

## 11. 所有权与并发

引用语义；每测试一个实例；日志列表非线程安全，body 应单任务写入；runner 在 body 结束后读取。`isCancelled` 可并发调用。无资源。

---

## 12. 示例与反例

正确：

```xnull
Test test = new Test("platform", [], 0, (TestContext context) -> {
    context.log("checking platform")
    if !supported {
        return context.skip("platform feature unavailable")
    }
    if broken {
        return context.fail("known defect")
    }
    return Ok(unit)
})
```

反例：`context.skip(...)` 后继续执行并返回 `Ok(unit)`；把 `TestContext` 存到全局；跨测试复用；在多个任务中并发 `log`；期望 `skip`/`fail` 用异常/`throw` 中止。

---

## 13. 测试/场景义务

名称校验；日志追加/快照独立性/null；skip 的 code/日志/总是 Err；fail 的 code/日志/总是 Err；空白 reason/message panic；isCancelled 随父取消；父取消传播；每测试隔离；并发 log 文档边界。

---

## 14. XNull 伪代码

```xnull
class TestContext {
    final String _name
    final Context _context
    final List<String> _logs = []

    TestContext(String name, Context context) {
        if name == null || context == null {
            throw "TestContext: null argument"
        }
        String normalized = trim(name)
        if normalized == "" {
            throw "TestContext: empty name"
        }
        _name = normalized
        _context = context
    }

    String name() {
        return _name
    }

    Bool isCancelled() {
        return _context.isCancelled()
    }

    void log(String text) {
        if text == null {
            throw "TestContext.log: null text"
        }
        _logs.push(text)
    }

    Result<Unit, Error> skip(String reason) {
        if reason == null {
            throw "TestContext.skip: null reason"
        }
        String normalized = trim(reason)
        if normalized == "" {
            throw "TestContext.skip: empty reason"
        }
        _logs.push("skip: " + normalized)
        return Err(new BasicError(ErrorKind.Cancelled, normalized).withCode("test.skipped"))
    }

    Result<Unit, Error> fail(String message) {
        if message == null {
            throw "TestContext.fail: null message"
        }
        String normalized = trim(message)
        if normalized == "" {
            throw "TestContext.fail: empty message"
        }
        _logs.push("fail: " + normalized)
        return Err(new BasicError(ErrorKind.Internal, normalized).withCode("test.failed"))
    }

    List<String> logs() {
        return _logs.copy()
    }
}
```
