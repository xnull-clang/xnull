# `BiMap<K,V>`

| 项 | 值 |
| --- | --- |
| 类型 | `class BiMap<K,V>` |
| 包 | `xdk.collections` |
| 稳定性 | `preview` |
| 依赖 | `Map` |

---

## 1. 定位

双向映射：键→值、值→键唯一；支持 `inverse()`。

不做：并发、多值映射（用 `MultiMap`）、有序键。

---

## 2. 设计逻辑

- 维护 forward/inverse 两张 `Map`。
- `put` 若值已绑定其他键，返回 false（不破坏双射）。
- `remove` 同时删两向。
- `inverse()` 返回反向视图（同一对映射，非副本）。为避免别名复杂度，首版返回新 BiMap 副本；文档注明。
- 非线程安全。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_forward` | `Map<K,V>` | 键→值 |
| `_inverse` | `Map<V,K>` | 值→键 |

不变量：双射；两张表键值互逆。

---

## 4. 生命周期

引用类型；无 close；可 clear。

---

## 5. 构造契约

`BiMap()` 空。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `put` | 建立映射 | `K key, V value` | `Bool` | 值已绑定 → false |
| `get` | 键→值 | `K key` | `V?` | 无 |
| `getKey` | 值→键 | `V value` | `K?` | 无 |
| `inverse` | 反向副本 | 无 | `BiMap<V,K>` | 无 |
| `remove` | 删除键 | `K key` | `Bool` | 无 |
| `keys` | 键快照 | 无 | `List<K>` | 无 |
| `values` | 值快照 | 无 | `List<V>` | 无 |
| `clear` | 清空 | 无 | `void` | 无 |

---

## 8. 使用的技术

- 双映射；
- 双射约束；
- 反向副本；
- 快照。

---

## 9. 需要的支撑

- 语言：class、Map、List、泛型 K/V、Bool；
- 运行时：映射；
- 接口：`Map`。

---

## 10. 依赖的特性/接口/类

`Map`。

---

## 11. 所有权与并发

持有键值引用；非线程安全；inverse 副本独立。

---

## 12. 示例与反例

正确：put("a",1)；getKey(1)="a"；put("b",1) false。  
反例：期望覆盖已绑定值；多任务共享；用可变对象作值。

---

## 13. 测试/场景义务

双射；重复值拒绝；remove 两向；inverse；keys/values 快照；clear。

---

## 14. XNull 伪代码

```xnull
class BiMap<K, V> {
    Map<K, V> _forward
    Map<V, K> _inverse

    BiMap() {
        _forward = new Map<K, V>()
        _inverse = new Map<V, K>()
    }

    Bool put(K key, V value) {
        if _inverse.has(value) {
            K existing = _inverse.get(value)
            if existing != key {
                return false
            }
        }
        if _forward.has(key) {
            V oldValue = _forward.get(key)
            _inverse.remove(oldValue)
        }
        _forward.put(key, value)
        _inverse.put(value, key)
        return true
    }

    V? get(K key) {
        return _forward.getOr(key, null)
    }

    K? getKey(V value) {
        return _inverse.getOr(value, null)
    }

    BiMap<V, K> inverse() {
        BiMap<V, K> result = new BiMap<V, K>()
        List<K> keys = _forward.keys()
        Int index = 0
        while index < keys.length() {
            K key = keys.get(index)
            result.put(_forward.get(key), key)
            index = index + 1
        }
        return result
    }

    Bool remove(K key) {
        if !_forward.has(key) { return false }
        V value = _forward.get(key)
        _forward.remove(key)
        _inverse.remove(value)
        return true
    }

    List<K> keys() { return _forward.keys() }
    List<V> values() { return _forward.values() }

    void clear() {
        _forward.clear()
        _inverse.clear()
    }
}
```
