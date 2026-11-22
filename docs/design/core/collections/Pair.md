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

---

## 15. 1.x 固定 Pair 兼容边界（C7）

1.x 源码同时保留两种形态：

```text
class Pair {              // 固定兼容形态
    String first
    Int second
}

class Pair<A, B> {        // 2.x 泛型形态
    A first()
    B second()
}
```

- 2.x 公共合同只有泛型 `Pair<A,B>`；字段为私有 `_first`/`_second`，通过 `first()`/`second()` 读取。
- `Map<String,Int>.entries()` 返回 `Pair<String,Int>`；1.x 的 `pair.first`/`pair.second` 字段访问迁移到 `pair.first()`/`pair.second()`。
- 不保留同名第二类；需要键值语义时用 [`Entry<K,V>`](Entry.md) 的 `key()`/`value()`。
- `Map<Int,Int>.entries()` 继续返回固定 `IntPair`（`first`/`second` 字段）；这是专用快速路径，不属于泛型 `Pair`。

测试义务：泛型 `Pair` 与固定 `IntPair` 的访问器/字段形状；`Map<String,Int>.entries()` 返回 `Pair<String,Int>`；1.x 字段访问迁移示例；不出现同名固定 `Pair` 类。
