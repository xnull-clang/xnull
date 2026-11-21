# `AtomicBool`

| 项 | 值 |
| --- | --- |
| 类型 | `class AtomicBool` |
| 包 | 执行层内建 |
| 稳定性 | `preview` |
| 依赖 | 无（运行时原子原语） |

---

## 1. 定位

顺序一致的布尔原子：`load`、`store`、`compareExchange`。

不做：布尔算术、位图、无锁算法框架、内存序参数。

---

## 2. 设计逻辑

- 字段 `_value: Bool`；由运行时原子原语读写。
- 所有操作顺序一致。
- `compareExchange` 成功返回 true；失败返回 false 且不写。
- 无 close；可跨任务共享。
- 不承诺无锁实现。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_value` | `Bool` | 当前值 |

不变量：读写原子；CAS 成功才替换。

---

## 4. 生命周期

构造后长期使用；无 close；无资源。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AtomicBool(Bool initialValue)` | initialValue | true/false | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `load` | 读 | 无 | `Bool` | 无 |
| `store` | 写 | `Bool value` | `void` | 无 |
| `compareExchange` | CAS | `Bool expected, Bool replacement` | `Bool` | 无 |

说明：

- CAS 比较当前布尔值；相等才写 replacement。
- 不提供 `toggle`；需要时用 CAS 循环。
- 不提供 `add`。

---

## 8. 使用的技术

- 顺序一致原子；
- CAS。

---

## 9. 需要的支撑

- 语言：class、Bool、void；
- 运行时：原子 load/store/CAS 原语；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

引用语义；线程安全；无资源；可共享。

---

## 12. 示例与反例

正确：`AtomicBool b = AtomicBool(false); b.compareExchange(false, true)`。  
反例：用 load + store 实现 toggle；期望 CAS 失败仍写入；依赖公平性。

---

## 13. 测试/场景义务

初始值；load/store；CAS 成功/失败；并发置位；可见性；重复 store。

---

## 14. XNull 伪代码

```xnull
class AtomicBool {
    Bool _value

    AtomicBool(Bool initialValue) {
        _value = initialValue
    }

    Bool load() {
        return atomicLoadBool(self)
    }

    void store(Bool value) {
        atomicStoreBool(self, value)
    }

    Bool compareExchange(Bool expected, Bool replacement) {
        return atomicCasBool(self, expected, replacement)
    }
}
```

> `atomicLoadBool`、`atomicStoreBool`、`atomicCasBool` 是运行时原语；均为顺序一致操作。
