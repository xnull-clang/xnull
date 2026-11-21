# `Pair<A,B>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Pair<A,B>` |
| 包 | `xdk.collections` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

两元组值对象；用于 `Map.entries`、`zip`、`partition` 等。

不做：资源、迭代、可变性。

---

## 2. 设计逻辑

- 两个字段 `first`/`second`；构造后不可变。
- 值语义：按字段相等；可读；可派生新 Pair。
- 不持有资源；无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_first` | `A` | 第一值 |
| `_second` | `B` | 第二值 |

不变量：字段不可变；无资源。

---

## 4. 生命周期

不可变值对象；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Pair(A first, B second)` | first/second | 任意 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `first` | 第一值 | 无 | `A` | 无 |
| `second` | 第二值 | 无 | `B` | 无 |
| `withFirst` | 派生 | `A value` | `Pair<A,B>` | 无 |
| `withSecond` | 派生 | `B value` | `Pair<A,B>` | 无 |
| `equals` | 值相等 | `Pair<A,B> other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变二元组；
- 字段相等；
- 泛型。

---

## 9. 需要的支撑

- 语言：class、泛型 A/B、Bool、String；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；字段引用共享；可共享；无资源。

---

## 12. 示例与反例

正确：`new Pair("a",1)`；`first()`/`second()`。  
反例：期望 Pair 是可变；把 Pair 当 Map；用引用相等做值比较。

---

## 13. 测试/场景义务

构造/读取；with* 返回新实例；equals；toString；Map.entries/zip 使用。

---

## 14. XNull 伪代码

```xnull
class Pair<A, B> {
    final A _first
    final B _second

    Pair(A first, B second) {
        _first = first
        _second = second
    }

    A first() { return _first }
    B second() { return _second }

    Pair<A, B> withFirst(A value) {
        return new Pair<A, B>(value, _second)
    }

    Pair<A, B> withSecond(B value) {
        return new Pair<A, B>(_first, value)
    }

    Bool equals(Pair<A, B> other) {
        if other == null { return false }
        return _first == other._first && _second == other._second
    }

    String toString() {
        return "(" + str(_first) + ", " + str(_second) + ")"
    }
}
```
