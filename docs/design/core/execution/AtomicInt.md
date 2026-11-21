# `AtomicInt`

| 项 | 值 |
| --- | --- |
| 类型 | `class AtomicInt` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | 无（运行时原子原语） |

---

## 1. 定位

顺序一致的整数原子：`load`、`store`、`compareExchange`、`addAndGet`、`getAndAdd`。

不做：浮点原子、指针原子、无锁算法框架、内存序参数、`AtomicLong` 独立类型。

---

## 2. 设计逻辑

- 字段 `_value: Int`；由运行时原子原语读写。
- 所有操作顺序一致；不提供 relaxed/acquire/release。
- `compareExchange` 成功返回 true；失败返回 false 且不写。
- `addAndGet` 返回新值；`getAndAdd` 返回旧值。
- `Int` 溢出按语言整数规则回绕。
- 无 close；可跨任务共享。
- 不承诺无锁实现，也不承诺公平。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_value` | `Int` | 当前值 |

不变量：读写原子；CAS 成功才替换；溢出回绕。

---

## 4. 生命周期

构造后长期使用；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AtomicInt(Int initialValue)` | initialValue | 任意 Int | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `load` | 读 | 无 | `Int` | 无 |
| `store` | 写 | `Int value` | `void` | 无 |
| `compareExchange` | CAS | `Int expected, Int replacement` | `Bool` | 无 |
| `addAndGet` | 加并返回新值 | `Int delta` | `Int` | 无 |
| `getAndAdd` | 加并返回旧值 | `Int delta` | `Int` | 无 |

说明：

- `compareExchange` 比较当前值与 expected；相等才写 replacement。
- `addAndGet` / `getAndAdd` 是单次原子加，不是 CAS 循环。
- 溢出回绕，不抛错。
- ABA 是整数值语义的一部分，不单独检测。

---

## 8. 使用的技术

- 顺序一致原子；
- CAS；
- 原子加。

---

## 9. 需要的支撑

- 语言：class、Int、Bool；
- 运行时：原子 load/store/CAS/add 原语；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

引用语义；线程安全；无资源；可共享。

---

## 12. 示例与反例

正确：`AtomicInt a = AtomicInt(1); a.addAndGet(2)` → 3。  
反例：用 load + store 冒充原子加；期望 CAS 失败仍写入；依赖无锁实现。

---

## 13. 测试/场景义务

初始值；load/store；CAS 成功/失败；addAndGet/getAndAdd；溢出；并发计数；顺序一致可见性。

---

## 14. XNull 伪代码

```xnull
class AtomicInt {
    Int _value

    AtomicInt(Int initialValue) {
        _value = initialValue
    }

    Int load() {
        return atomicLoadInt(self)
    }

    void store(Int value) {
        atomicStoreInt(self, value)
    }

    Bool compareExchange(Int expected, Int replacement) {
        return atomicCasInt(self, expected, replacement)
    }

    Int addAndGet(Int delta) {
        return atomicAddInt(self, delta)
    }

    Int getAndAdd(Int delta) {
        return atomicGetAndAddInt(self, delta)
    }
}
```

> `atomicLoadInt`、`atomicStoreInt`、`atomicCasInt`、`atomicAddInt`、`atomicGetAndAddInt` 是运行时原语；均为顺序一致操作。
