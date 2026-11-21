# `ErrorCollector`

| 项 | 值 |
| --- | --- |
| 类型 | `class ErrorCollector` |
| 包 | `xdk.errors` |
| 稳定性 | `preview` |
| 依赖 | `BasicError`、`ErrorGroup`、`Result` |

---

## 1. 定位

可变错误收集器：把多次 `Error`/`Result` 收集成一个 `ErrorGroup`。

不做：重试、日志、去重、全局注册。

---

## 2. 设计逻辑

- 适合批量操作/多字段校验：先收集，最后统一转组。
- 非线程安全；共享需外部同步。
- `addResult` 只收 `Err`，Ok 忽略。
- `toGroup`/`toList` 返回快照；不清空 collector。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_errors` | `List<BasicError>` | 可变 | 已收集错误 |

不变量：元素非 null；顺序 = 加入顺序；无 self 问题（collector 不是 Error）。

---

## 4. 生命周期

- 构造空；无 close；构建完成后可只读/转组。
- 非线程安全；共享需外部同步。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ErrorCollector()` | 无 | 无 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `add` | 追加错误 | `BasicError error` | `void` | null → panic |
| `addResult` | 追加 Err | `Result<T, BasicError> result` | `void` | null → panic |
| `addAll` | 追加多个 | `List<BasicError> errors` | `void` | 非法 → panic |
| `hasErrors` | 是否有错误 | 无 | `Bool` | 无 |
| `length` | 数量 | 无 | `Int` | 无 |
| `first` | 首个 | 无 | `BasicError?` | 无 |
| `last` | 最后 | 无 | `BasicError?` | 无 |
| `toGroup` | 转组 | 无 | `ErrorGroup` | 无 |
| `toList` | 快照 | 无 | `List<BasicError>` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |

---

## 8. 使用的技术

- 可变构建器；
- 结果收集；
- 快照列表；
- 聚合器。

---

## 9. 需要的支撑

- 语言：class、List、Bool、Int、Result；
- 运行时：无；
- 接口：`BasicError`、`ErrorGroup`。

---

## 10. 依赖的特性/接口/类

`BasicError`、`ErrorGroup`、`Result`、`List`。

---

## 11. 所有权与并发

- 可变；非线程安全。
- `toGroup`/`toList` 返回快照；外部修改不影响 collector。
- 无资源、无 close。

---

## 12. 示例与反例

正确：多字段校验逐个 `addResult`；最后 `toGroup()`；`isEmpty()` 判断全部通过。  
反例：多任务同时 add 不加锁；`toGroup` 后修改 collector 期望组变化；收集 fatal。

---

## 13. 测试/场景义务

add/addResult/addAll；Ok 忽略；null panic；toGroup 快照；clear；first/last；并发外部同步。

---

## 14. XNull 伪代码

```xnull
class ErrorCollector {
    List<BasicError> _errors = []

    ErrorCollector() {
    }

    void add(BasicError error) {
        if error == null {
            throw "ErrorCollector.add: null"
        }
        _errors.push(error)
    }

    void addResult<T>(Result<T, BasicError> result) {
        if result.isErr() {
            self.add(result.error())
        }
    }

    void addAll(List<BasicError> errors) {
        Int index = 0
        while index < errors.length() {
            self.add(errors.get(index))
            index = index + 1
        }
    }

    Bool hasErrors() { return _errors.length() > 0 }
    Int length() { return _errors.length() }

    BasicError? first() {
        if _errors.length() == 0 {
            return null
        }
        return _errors.get(0)
    }

    BasicError? last() {
        if _errors.length() == 0 {
            return null
        }
        return _errors.get(_errors.length() - 1)
    }

    ErrorGroup toGroup() {
        ErrorGroup group = new ErrorGroup()
        Int index = 0
        while index < _errors.length() {
            group.add(_errors.get(index))
            index = index + 1
        }
        return group
    }

    List<BasicError> toList() {
        List<BasicError> result = []
        Int index = 0
        while index < _errors.length() {
            result.push(_errors.get(index))
            index = index + 1
        }
        return result
    }

    void clear() {
        _errors.clear()
    }
}
```
