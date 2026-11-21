# `Lazy`

| 项 | 值 |
| --- | --- |
| 类型 | `class Lazy<T>` |
| 包 | `xdk.functional` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

延迟初始化值：首次 `get` 调用 supplier，之后返回缓存；支持链式 `map`。

不做：异步 Future、超时、重试、可重置缓存、并发初始化保证（X）。

---

## 2. 设计逻辑

- 字段：supplier、缓存值、已初始化标志、计算中标志。
- `get` 首次调用 supplier，成功后缓存；后续直接返回。
- supplier 抛错时不缓存，`_computing` 通过 `defer` 复位，调用方可重试。
- 递归调用 `get` 检测到 `_computing` 为 true，抛合同错误，避免无限递归。
- `map` 返回新的 Lazy，不改变原 Lazy 的求值时机。
- 非线程安全；并发 `get` 可能重复计算或数据竞争；需要时由调用方加锁。
- 无 close；无资源。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_supplier` | `T()` | 初始化函数 |
| `_value` | `T?` | 缓存值 |
| `_initialized` | `Bool` | 是否已成功计算 |
| `_computing` | `Bool` | 是否正在计算 |

不变量：`_initialized=true` 时 `_value` 可读；`_computing` 只在计算期间为 true；supplier 非 null。

---

## 4. 生命周期

构造后单次初始化；无 close；缓存随对象生命周期；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Lazy(T() supplier)` | supplier | 非 null | null → panic |
| `Lazy.ready(T value)` | value | 任意 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `ready` | 已初始化值 | `T value` | `Lazy<T>` | 无 |
| `get` | 取值/初始化 | 无 | `T` | supplier 错误；递归 → panic |
| `isInitialized` | 是否已计算 | 无 | `Bool` | 无 |
| `map<R>` | 映射缓存值 | `R(T) transform` | `Lazy<R>` | null → panic |
| `toString` | 状态摘要 | 无 | `String` | 无；不触发计算 |

说明：

- `ready` 创建的 Lazy 首次 `get` 直接返回缓存。
- `get` 不吞 supplier 错误；错误原样传播。
- `map` 的 transform 只在结果 Lazy 首次 `get` 时执行。
- `toString` 不调用 supplier，避免副作用。

---

## 8. 使用的技术

- 延迟求值；
- 单次缓存；
- 递归检测；
- 闭包组合。

---

## 9. 需要的支撑

- 语言：class、泛型、Bool、函数类型、String；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

引用语义；非线程安全；可共享但并发 `get` 需外部同步；无资源。

---

## 12. 示例与反例

正确：`Lazy<Config> cfg = new Lazy<Config>(() -> loadConfig())`；首次访问加载。  
反例：并发 `get` 期望只计算一次；supplier 返回 null 当非空类型；在 supplier 内递归 `get`；用 `toString` 触发昂贵加载。

---

## 13. 测试/场景义务

首次/后续 get；supplier 调用次数；异常后重试；递归检测；ready；map 延迟；toString 不触发；并发文档边界；null 返回。

---

## 14. XNull 伪代码

```xnull
class Lazy<T> {
    final T() _supplier
    T? _value = null
    Bool _initialized = false
    Bool _computing = false

    Lazy(T() supplier) {
        if supplier == null { throw "Lazy: null supplier" }
        _supplier = supplier
    }

    static Lazy<T> ready(T value) {
        Lazy<T> result = new Lazy<T>(() -> value)
        result._value = value
        result._initialized = true
        return result
    }

    T get() {
        if _initialized { return _value as T }
        if _computing { throw "Lazy.get: recursive initialization" }
        _computing = true
        defer { _computing = false }
        T computed = _supplier()
        _value = computed
        _initialized = true
        return computed
    }

    Bool isInitialized() { return _initialized }

    Lazy<R> map<R>(R(T) transform) {
        if transform == null { throw "Lazy.map: null transform" }
        return new Lazy<R>(() -> transform(self.get()))
    }

    String toString() {
        return "Lazy(initialized=" + str(_initialized) + ")"
    }
}
```
