# `AtomicRef`

| 项 | 值 |
| --- | --- |
| 类型 | `class AtomicRef<T>` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | 无（运行时原子原语） |

---

## 1. 定位

顺序一致的引用原子：`load`、`store`、`compareExchange`；按引用身份比较。

不做：值相等 CAS、深拷贝、弱引用、内存回收控制、任意值类型原子。

---

## 2. 设计逻辑

- 字段 `_value: T`；T 必须是引用类型。
- `compareExchange` 用 `===` 比较对象身份；不是 `==` 内容相等。
- 所有操作顺序一致；不承诺无锁。
- 允许 null（引用类型本身可空）。
- 无 close；可跨任务共享。
- 值类型 T 不在  支持范围；需要原子整数/布尔用 `AtomicInt`/`AtomicBool`。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_value` | `T` | 当前引用 |

不变量：T 为引用类型；CAS 按身份；成功才替换。

---

## 4. 生命周期

构造后长期使用；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AtomicRef(T value)` | value | T 为引用类型；可 null | 值类型实例不在  支持范围 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `load` | 读引用 | 无 | `T` | 无 |
| `store` | 写引用 | `T value` | `void` | 无 |
| `compareExchange` | 身份 CAS | `T expected, T replacement` | `Bool` | 无 |

说明：

- `expected` 与当前引用 `===` 相等才写 replacement。
- `store` 不复制对象；只替换引用。
- 不提供内容相等 CAS；需要时由调用方组合。
- ABA 是引用身份语义的一部分，不单独检测。

---

## 8. 使用的技术

- 顺序一致原子；
- 引用身份 CAS。

---

## 9. 需要的支撑

- 语言：class、泛型、Bool、void；
- 运行时：原子引用 load/store/CAS 原语、引用身份比较；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

引用语义；线程安全；不改变对象所有权；无资源；可共享。

---

## 12. 示例与反例

正确：`AtomicRef<String> r = AtomicRef("a"); r.compareExchange("a", "b")`。  
反例：期望按内容相等 CAS；把值类型放进 AtomicRef；store 后期望对象被复制。

---

## 13. 测试/场景义务

初始引用；load/store；身份 CAS 成功/失败；null；相同内容不同对象；并发替换；可见性。

---

## 14. XNull 伪代码

```xnull
class AtomicRef<T> {
    T _value

    AtomicRef(T value) {
        _value = value
    }

    T load() {
        return atomicLoadRef(self)
    }

    void store(T value) {
        atomicStoreRef(self, value)
    }

    Bool compareExchange(T expected, T replacement) {
        return atomicCasRef(self, expected, replacement)
    }
}
```

> `atomicLoadRef`、`atomicStoreRef`、`atomicCasRef` 是运行时原语；CAS 按引用身份（`===`）比较，均为顺序一致操作。
