# `CapabilitySet`

| 项 | 值 |
| --- | --- |
| 类型 | `class CapabilitySet` |
| 包 | `xdk.meta` |
| 稳定性 | `preview` |
| 依赖 | `Capability` |

---

## 1. 定位

不可变能力集合：判断、合并、求交、求差、快照。用于 `CoreProfile` 和部署校验。

不做：运行时权限、许可、动态加载、能力探测、全局注册表。

---

## 2. 设计逻辑

- 内部保存有序 `List<Capability>`；构造时去重并复制。
- 所有修改方法返回新集合，不修改原对象。
- `has` 线性查找；能力数量小（< 64），不引入哈希表。
- `==` 仍是引用身份；值比较用 `equals`。
- 可作 `CoreProfile` 字段；不可变后可跨任务只读共享。
- 不依赖 `Set<Capability>`，避免容器实现差异影响核心。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_values` | `List<Capability>` | final | 去重、保持插入顺序 |

不变量：无重复；不含 null；构造后不再修改；快照返回副本。

---

## 4. 生命周期

构造后不可变；无 close；GC 管理；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `CapabilitySet(List<Capability> values)` | values | 非 null；元素非 null | null → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `empty` | 空集合 | 无 | `CapabilitySet` | 无 |
| `of` | 从列表构造 | `List<Capability> values` | `CapabilitySet` | null → panic |
| `length` | 能力数 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `has` | 是否包含 | `Capability capability` | `Bool` | null → panic |
| `with` | 添加一个 | `Capability capability` | `CapabilitySet` | null → panic |
| `without` | 移除一个 | `Capability capability` | `CapabilitySet` | null → panic |
| `withAll` | 添加多个 | `List<Capability> values` | `CapabilitySet` | null → panic |
| `withoutAll` | 移除多个 | `List<Capability> values` | `CapabilitySet` | null → panic |
| `union` | 并集 | `CapabilitySet other` | `CapabilitySet` | null → panic |
| `intersection` | 交集 | `CapabilitySet other` | `CapabilitySet` | null → panic |
| `difference` | 差集（this - other） | `CapabilitySet other` | `CapabilitySet` | null → panic |
| `containsAll` | 是否包含全部 | `CapabilitySet other` | `Bool` | null → panic |
| `containsAny` | 是否包含任一 | `CapabilitySet other` | `Bool` | null → panic |
| `toList` | 快照 | 无 | `List<Capability>` | 无 |
| `equals` | 值比较 | `CapabilitySet other` | `Bool` | null → false |
| `describe` | 稳定文本 | 无 | `String` | 无 |
| `copy` | 复制 | 无 | `CapabilitySet` | 无 |

说明：

- `with` 已存在时返回等价新集合；不保证返回同一对象。
- `union` 保持 `this` 顺序，再追加 `other` 中不存在项。
- `describe` 用 `capabilityName`，按插入顺序，逗号分隔。
- `equals` 只比较成员集合，不比较顺序。

---

## 8. 使用的技术

- 不可变集合；
- 线性成员查找；
- 构造时去重；
- 快照复制。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、String、Bool、Int；
- 运行时：无；
- 接口：`Capability`、`capabilityName`。

---

## 10. 依赖的特性/接口/类

`Capability`、`capabilityName`、`List`。

---

## 11. 所有权与并发

不可变；可跨任务共享；`toList` 返回副本；无取消点；无资源。
相等：`equals` 做成员集合比较；`==` 仍是引用身份；不推荐作为 `Map` 键。

---

## 12. 示例与反例

正确：`CoreProfile.client().capabilities().has(Capability.HttpClient)`。  
反例：把 `CapabilitySet` 当权限令牌；修改 `toList()` 期望改集合；运行时动态增删；
用 `==` 做值比较。

---

## 13. 测试/场景义务

空集合；去重；添加/移除；并/交/差；包含全部/任一；快照独立；值相等；describe；
null 参数；客户端/服务器能力矩阵。

---

## 14. XNull 伪代码

```xnull
class CapabilitySet {
    final List<Capability> _values

    CapabilitySet(List<Capability> values) {
        if values == null { throw "CapabilitySet: null values" }
        _values = []
        Int index = 0
        while index < values.length() {
            Capability capability = values.get(index)
            if capability == null { throw "CapabilitySet: null capability" }
            Bool exists = false
            Int scan = 0
            while scan < _values.length() {
                if _values.get(scan) == capability {
                    exists = true
                    break
                }
                scan = scan + 1
            }
            if !exists { _values.push(capability) }
            index = index + 1
        }
    }

    static CapabilitySet empty() {
        return new CapabilitySet([])
    }

    static CapabilitySet of(List<Capability> values) {
        return new CapabilitySet(values)
    }

    Int length() { return _values.length() }
    Bool isEmpty() { return _values.length() == 0 }

    Bool has(Capability capability) {
        if capability == null { throw "CapabilitySet.has: null capability" }
        Int index = 0
        while index < _values.length() {
            if _values.get(index) == capability { return true }
            index = index + 1
        }
        return false
    }

    CapabilitySet with(Capability capability) {
        if capability == null { throw "CapabilitySet.with: null capability" }
        if self.has(capability) { return self.copy() }
        List<Capability> next = self.toList()
        next.push(capability)
        return new CapabilitySet(next)
    }

    CapabilitySet without(Capability capability) {
        if capability == null { throw "CapabilitySet.without: null capability" }
        List<Capability> next = []
        Int index = 0
        while index < _values.length() {
            if _values.get(index) != capability {
                next.push(_values.get(index))
            }
            index = index + 1
        }
        return new CapabilitySet(next)
    }

    CapabilitySet withAll(List<Capability> values) {
        if values == null { throw "CapabilitySet.withAll: null values" }
        CapabilitySet result = self
        Int index = 0
        while index < values.length() {
            result = result.with(values.get(index))
            index = index + 1
        }
        return result
    }

    CapabilitySet withoutAll(List<Capability> values) {
        if values == null { throw "CapabilitySet.withoutAll: null values" }
        CapabilitySet result = self
        Int index = 0
        while index < values.length() {
            result = result.without(values.get(index))
            index = index + 1
        }
        return result
    }

    CapabilitySet union(CapabilitySet other) {
        if other == null { throw "CapabilitySet.union: null other" }
        return self.withAll(other.toList())
    }

    CapabilitySet intersection(CapabilitySet other) {
        if other == null { throw "CapabilitySet.intersection: null other" }
        List<Capability> next = []
        Int index = 0
        while index < _values.length() {
            if other.has(_values.get(index)) {
                next.push(_values.get(index))
            }
            index = index + 1
        }
        return new CapabilitySet(next)
    }

    CapabilitySet difference(CapabilitySet other) {
        if other == null { throw "CapabilitySet.difference: null other" }
        List<Capability> next = []
        Int index = 0
        while index < _values.length() {
            if !other.has(_values.get(index)) {
                next.push(_values.get(index))
            }
            index = index + 1
        }
        return new CapabilitySet(next)
    }

    Bool containsAll(CapabilitySet other) {
        if other == null { throw "CapabilitySet.containsAll: null other" }
        List<Capability> values = other.toList()
        Int index = 0
        while index < values.length() {
            if !self.has(values.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    Bool containsAny(CapabilitySet other) {
        if other == null { throw "CapabilitySet.containsAny: null other" }
        List<Capability> values = other.toList()
        Int index = 0
        while index < values.length() {
            if self.has(values.get(index)) { return true }
            index = index + 1
        }
        return false
    }

    List<Capability> toList() {
        List<Capability> result = []
        Int index = 0
        while index < _values.length() {
            result.push(_values.get(index))
            index = index + 1
        }
        return result
    }

    Bool equals(CapabilitySet other) {
        if other == null { return false }
        if self.length() != other.length() { return false }
        Int index = 0
        while index < _values.length() {
            if !other.has(_values.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    String describe() {
        String result = ""
        Int index = 0
        while index < _values.length() {
            if index > 0 { result = result + "," }
            result = result + capabilityName(_values.get(index))
            index = index + 1
        }
        return result
    }

    CapabilitySet copy() {
        return new CapabilitySet(self.toList())
    }
}
```
