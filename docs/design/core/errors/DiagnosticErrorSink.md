# `DiagnosticErrorSink`

| 项 | 值 |
| --- | --- |
| 类型 | `class DiagnosticErrorSink implements ErrorSink` |
| 包 | `xdk.errors` |
| 稳定性 | `preview` |
| 依赖 | `Error`、`ErrorKind`、`runtime.diagnose` |

---

## 1. 定位

把错误写到 `xdk.runtime.diagnose`（stderr），用于边界观测。

不做：日志级别、格式化字段、持久化、全局注册。

---

## 2. 设计逻辑

- 无状态；`isOpen` 恒 true；`close`/`flush` no-op。
- 写失败不抛错；诊断失败只再诊断一次。
- 可从任意任务调用；底层诊断写串行化。
- 只输出 `[Kind] describe` 单行，不带 details/causes。

---

## 3. 表示与不变量

无字段；无资源。

---

## 4. 生命周期

- 构造即可用；无 close 状态。
- `close` 幂等；`isOpen` 恒 true。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DiagnosticErrorSink()` | 无 | 无 | 无 |

---

## 6. 字段表

无。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `report` | 写一行诊断 | `Error error` | `Result<Unit, Error>` | `Io` |
| `flush` | no-op | 无 | `Result<Unit, Error>` | 无 |
| `close` | no-op | 无 | `Result<Unit, Error>` | 无 |
| `isOpen` | 是否可用 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 运行时诊断；
- 单行格式；
- 无状态实现。

---

## 9. 需要的支撑

- 语言：class、String、Bool、Result；
- 运行时：`diagnose`；
- 接口：`Error`、`ErrorKind`、`errorKindDisplayName`。

---

## 10. 依赖的特性/接口/类

`Error`、`ErrorKind`、`errorKindDisplayName`、`runtime.diagnose`。

---

## 11. 所有权与并发

- 无状态；可跨任务共享。
- 不持有错误引用。

---

## 12. 示例与反例

正确：`reportTo(new DiagnosticErrorSink(), result)`。  
反例：把 sink 当业务处理器；期望它写结构化字段；期望它改变 Result。

---

## 13. 测试/场景义务

写 stderr；单行；无异常；不改变 Result；多任务共享。

---

## 14. XNull 伪代码

```xnull
class DiagnosticErrorSink implements ErrorSink {
    DiagnosticErrorSink() {
    }

    Result<Unit, Error> report(Error error) {
        if error == null {
            throw "DiagnosticErrorSink.report: null"
        }
        diagnose("[" + errorKindDisplayName(error.kind()) + "] " + error.describe())
        return Ok(unit)
    }

    Result<Unit, Error> flush() {
        return Ok(unit)
    }

    Result<Unit, Error> close() {
        return Ok(unit)
    }

    Bool isOpen() {
        return true
    }
}
```
