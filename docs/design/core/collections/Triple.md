# `Triple<A,B,C>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Triple<A,B,C>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

三元组值对象；用于三值返回/坐标/统计。

不做：资源、迭代、可变性。

---

## 2. 设计逻辑

- 三个字段 `first/second/third`；不可变。
- 值语义：按字段相等。
- 无 close。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_first` | `A` | 第一值 |
| `_second` | `B` | 第二值 |
| `_third` | `C` | 第三值 |

不变量：字段不可变；无资源。

---

## 4. 生命周期

不可变值对象；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Triple(A first, B second, C third)` | 三个值 | 任意 | 无 |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `first` | 第一值 | 无 | `A` | 无 |
| `second` | 第二值 | 无 | `B` | 无 |
| `third` | 第三值 | 无 | `C` | 无 |
| `withFirst` | 派生 | `A value` | `Triple<A,B,C>` | 无 |
| `withSecond` | 派生 | `B value` | `Triple<A,B,C>` | 无 |
| `withThird` | 派生 | `C value` | `Triple<A,B,C>` | 无 |
| `equals` | 值相等 | `Triple<A,B,C> other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变三元组；
- 字段相等；
- 泛型。

---

## 9. 需要的支撑

- 语言：class、泛型 A/B/C、Bool、String；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new Triple(1,"a",true)`。  
反例：期望可变；用引用相等；把 Triple 当容器。

---

## 13. 测试/场景义务

构造/读取；with*；equals；toString；嵌套泛型。

---

## 14. XNull 伪代码

```xnull
class Triple<A, B, C> {
    final A _first
    final B _second
    final C _third

    Triple(A first, B second, C third) {
        _first = first
        _second = second
        _third = third
    }

    A first() { return _first }
    B second() { return _second }
    C third() { return _third }

    Triple<A, B, C> withFirst(A value) {
        return new Triple<A, B, C>(value, _second, _third)
    }

    Triple<A, B, C> withSecond(B value) {
        return new Triple<A, B, C>(_first, value, _third)
    }

    Triple<A, B, C> withThird(C value) {
        return new Triple<A, B, C>(_first, _second, value)
    }

    Bool equals(Triple<A, B, C> other) {
        if other == null { return false }
        return _first == other._first
            && _second == other._second
            && _third == other._third
    }

    String toString() {
        return "(" + str(_first) + ", " + str(_second) + ", " + str(_third) + ")"
    }
}
```
