# `ValidationContext`

| 项 | 值 |
| --- | --- |
| 类型 | `class ValidationContext` |
| 包 | `xdk.validate` |
| 稳定性 | `preview` |
| 依赖 | `ValidationError` |

---

## 1. 定位

校验过程上下文：当前路径、错误收集、failFast 停止、子路径/分叉上下文。

不做：结果快照（`ValidationResult`）、消息 i18n、线程安全、异步。

---

## 2. 设计逻辑

- 字段：路径、共享错误列表、failFast、停止标志。
- `child(name)` 生成子路径上下文，错误写入同一个列表；点号用于字段，`[n]` 用于数组下标。
- `fork()` 生成独立错误列表的上下文，供 `any`/`not` 探测，不污染主错误。
- `addError` 在 stopped 时忽略；failFast 时首个错误后置 stopped。
- 上下文非线程安全；一次校验应由一个任务持有。
- 无 close；无资源。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_path` | `String` | 当前路径，可为空 |
| `_errors` | `List<ValidationError>` | 错误列表（子上下文共享） |
| `_failFast` | `Bool` | 是否首个错误停止 |
| `_stopped` | `Bool` | 是否停止 |

不变量：path 非 null；errors 非 null；stopped 只从 false 变 true；failFast 时 stopped 与 errors 非空一致。

---

## 4. 生命周期

构造后单次校验使用；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ValidationContext()` | 无 | failFast=false | 无 |
| `ValidationContext(Bool failFast)` | failFast | 任意 | 无 |

私有构造用于 child/fork。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `path` | 当前路径 | 无 | `String` | 无 |
| `failFast` | 是否快速失败 | 无 | `Bool` | 无 |
| `isFailed` | 是否已有错误 | 无 | `Bool` | 无 |
| `isStopped` | 是否停止 | 无 | `Bool` | 无 |
| `errors` | 错误快照 | 无 | `List<ValidationError>` | 无 |
| `addError` | 添加错误 | `String code, String message` | `void` | null/空 → panic |
| `child` | 子路径 | `String name` | `ValidationContext` | null → panic |
| `fork` | 独立探测 | 无 | `ValidationContext` | 无 |

说明：

- `child("user")` 从根得到 `user`；再 `child("name")` 得到 `user.name`。
- `child("[2]")` 从 `items` 得到 `items[2]`。
- `fork` 继承 path/failFast，但错误列表独立、stopped=false。
- `errors` 返回副本；子上下文共享内部列表。

---

## 8. 使用的技术

- 路径栈；
- 共享错误列表；
- failFast；
- 分叉探测。

---

## 9. 需要的支撑

- 语言：class、String、Bool、List；
- 运行时：无；
- 接口：`ValidationError`。

---

## 10. 依赖的特性/接口/类

`ValidationError`。

---

## 11. 所有权与并发

引用语义；错误列表由子上下文共享；非线程安全；无资源。

---

## 12. 示例与反例

正确：`context.child("user").addError("required", "missing")`。  
反例：跨任务共享 context；fork 后期望错误回写主上下文；failFast 后继续添加错误。

---

## 13. 测试/场景义务

根路径；字段/数组子路径；共享错误；fork 隔离；failFast；stopped 后 addError；errors 副本。

---

## 14. XNull 伪代码

```xnull
class ValidationContext {
    final String _path
    final List<ValidationError> _errors
    final Bool _failFast
    Bool _stopped

    ValidationContext() {
        _path = ""
        _errors = []
        _failFast = false
        _stopped = false
    }

    ValidationContext(Bool failFast) {
        _path = ""
        _errors = []
        _failFast = failFast
        _stopped = false
    }

    private ValidationContext(String path, List<ValidationError> errors,
                              Bool failFast, Bool stopped) {
        _path = path
        _errors = errors
        _failFast = failFast
        _stopped = stopped
    }

    String path() { return _path }
    Bool failFast() { return _failFast }
    Bool isFailed() { return _errors.length() > 0 }
    Bool isStopped() { return _stopped }

    List<ValidationError> errors() { return _errors.copy() }

    void addError(String code, String message) {
        if code == null || code == "" {
            throw "ValidationContext.addError: empty code"
        }
        if message == null || message == "" {
            throw "ValidationContext.addError: empty message"
        }
        if _stopped { return }
        _errors.push(new ValidationError(_path, code, message))
        if _failFast { _stopped = true }
    }

    ValidationContext child(String name) {
        if name == null { throw "ValidationContext.child: null name" }
        String childPath = name
        if _path != "" {
            if name.startsWith("[") {
                childPath = _path + name
            } else {
                childPath = _path + "." + name
            }
        }
        return new ValidationContext(childPath, _errors, _failFast, _stopped)
    }

    ValidationContext fork() {
        return new ValidationContext(_path, [], _failFast, false)
    }
}
```
