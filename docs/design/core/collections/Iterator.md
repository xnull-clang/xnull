# `Iterator<T>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Iterator<T>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

单次迭代器：`hasNext`/`next`，可选 `close`。

不做：泛型 protocol、并发、重置、惰性流框架。

---

## 2. 设计逻辑

- 用两个函数值注入行为：`hasNext`、`next`；可选 `close`。
- 单次消费；`close` 后 `next` 返回 null 或 panic？定义：`next` 在结束/关闭后返回 null；`hasNext` 返回 false。
- `close` 幂等。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_hasNext` | `Bool()` | 判断 |
| `_next` | `T()` | 取值 |
| `_close` | `void()?` | 可选清理 |
| `_closed` | `Bool` | 关闭标志 |

不变量：closed 后 hasNext=false；close 幂等。

---

## 4. 生命周期

构造后使用；可 close；单次迭代。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Iterator(Bool() hasNext, T() next)` | 两个函数 | 非 null | null → panic |
| `Iterator(Bool() hasNext, T() next, void() close)` | 三个函数 | 非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `hasNext` | 是否还有 | 无 | `Bool` | 无 |
| `next` | 取下一个 | 无 | `T?` | 无 |
| `close` | 关闭 | 无 | `void` | 无 |
| `isClosed` | 是否关闭 | 无 | `Bool` | 无 |

---

## 8. 使用的技术

- 函数值注入；
- 单次消费；
- 可选关闭。

---

## 9. 需要的支撑

- 语言：class、函数类型、泛型 T、Bool；
- 运行时：闭包；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

迭代器持有闭包；close 清理；非线程安全。

---

## 12. 示例与反例

正确：`Iterator(hasNext,next)`；while hasNext next。  
反例：多次迭代同一 Iterator；close 后继续 next 期望值；多任务共享。

---

## 13. 测试/场景义务

空/单/多；close 幂等；close 后 hasNext/next；异常闭包；嵌套迭代。

---

## 14. XNull 伪代码

```xnull
class Iterator<T> {
    Bool() _hasNext
    T() _next
    void()? _close
    Bool _closed

    Iterator(Bool() hasNext, T() next) {
        if hasNext == null || next == null {
            throw "Iterator: null function"
        }
        _hasNext = hasNext
        _next = next
        _close = null
        _closed = false
    }

    Iterator(Bool() hasNext, T() next, void() close) {
        if hasNext == null || next == null || close == null {
            throw "Iterator: null function"
        }
        _hasNext = hasNext
        _next = next
        _close = close
        _closed = false
    }

    Bool hasNext() {
        if _closed { return false }
        return _hasNext()
    }

    T? next() {
        if _closed { return null }
        if !_hasNext() { return null }
        return _next()
    }

    void close() {
        if _closed { return }
        _closed = true
        if _close != null {
            _close()
        }
    }

    Bool isClosed() { return _closed }
}
```
