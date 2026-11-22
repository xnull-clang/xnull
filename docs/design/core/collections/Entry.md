# `Entry<K,V>`

| 项 | 值 |
| --- | --- |
| 类型 | `class Entry<K,V>` |
| 包 | `xdk.collections` |
| 稳定性 | `stable` |
| 依赖 | 无 |

---

## 1. 定位

通用 `Map<K,V>.entries()` 的键值值对象；用于非 `Map<String,Int>`/`Map<Int,Int>` 的受支持 K/V。

不做：资源、迭代、可变性、Map 本身。

---

## 2. 设计逻辑

- 两个字段 `_key`/`_value`；构造后不可变。
- 值语义：按字段相等；引用字段按引用身份比较。
- `Map<String,Int>` 仍返回固定兼容形状 `Pair<String,Int>`；`Map<Int,Int>` 返回 `IntPair`。
- 1.x `Entry` 的公共字段 `key`/`value` 在 2.x 改为 `key()`/`value()` 访问器；这是 C7 登记的有意迁移边界。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_key` | `K` | 键 |
| `_value` | `V` | 值 |

不变量：字段不可变；键按 `Map` 的键规则；无资源。

---

## 4. 生命周期

不可变值对象；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Entry(K key, V value)` | key/value | 任意受支持 K/V | 无 |

---

## 6. 字段表

见 §3；字段私有，通过访问器读取。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `key` | 键 | 无 | `K` | 无 |
| `value` | 值 | 无 | `V` | 无 |
| `withKey` | 派生新键 | `K key` | `Entry<K,V>` | 无 |
| `withValue` | 派生新值 | `V value` | `Entry<K,V>` | 无 |
| `equals` | 值相等 | `Entry<K,V> other` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变二元组；
- 字段相等；
- 泛型。

---

## 9. 需要的支撑

- 语言：class、泛型 K/V、Bool、String；
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

正确：

```xnull
Map<String, Bool> flags = [:]
flags.put("ready", true)
Entry<String, Bool> firstEntry = flags.entries().get(0)
String key = firstEntry.key()
Bool value = firstEntry.value()
```

反例：

- 期望修改 `Entry` 会写回 `Map`；
- 把 1.x 公共字段 `entry.key` 直接当 2.x 字段；
- 用引用相等比较两个 `Entry` 值。

---

## 13. 测试/场景义务

构造/读取；`withKey`/`withValue` 返回新实例；`equals`；`toString`；通用 `Map.entries()` 返回 `Entry`；`Map<String,Int>`/`Map<Int,Int>` 仍返回 `Pair`/`IntPair`；1.x 字段访问迁移到访问器。

---

## 14. XNull 伪代码

```xnull
class Entry<K, V> {
    final K _key
    final V _value

    Entry(K key, V value) {
        _key = key
        _value = value
    }

    K key() { return _key }
    V value() { return _value }

    Entry<K, V> withKey(K key) {
        return new Entry<K, V>(key, _value)
    }

    Entry<K, V> withValue(V value) {
        return new Entry<K, V>(_key, value)
    }

    Bool equals(Entry<K, V> other) {
        if other == null { return false }
        return _key == other._key && _value == other._value
    }

    String toString() {
        return "(" + str(_key) + ", " + str(_value) + ")"
    }
}
```
