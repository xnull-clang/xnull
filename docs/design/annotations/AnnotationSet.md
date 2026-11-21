# `AnnotationSet`

| 项 | 值 |
| --- | --- |
| 类型 | `class AnnotationSet` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | `AnnotationInfo`、`AnnotationTarget`、`List`、`String`、`Bool`、`Int` |

---

## 1. 定位

同一目标上的有序不可变注解集合。支持按注解类型名取首个、取全部、取子集、判断存在、合并。

不做：不做注解声明、不做目标校验、不做重复策略判定、不做运行时扫描、不做全局注册。

---

## 2. 设计逻辑

- 一个 `AnnotationSet` 只承载**同一目标**（相同 `target` 与相同 `targetName`）的注解；跨目标混放是合同错误。
- 内部保存 `List<AnnotationInfo>`，保持源码出现顺序；不排序、不去重（除合同校验外）。
- 同一 `typeName` 可以出现多次，但 `repeatIndex` 必须不同；这支持 `@Repeatable`。
- 同一 `typeName` 与同一 `repeatIndex` 的组合在集合内唯一；重复即合同错误。
- `first` 返回按出现顺序的第一个；不返回“最大 repeatIndex”或“最后声明”。
- `all` 返回按出现顺序的全部；返回列表副本。
- `byTypeName` 返回新的子集，仍保持原顺序；不修改原集合。
- `merge` 返回新集合；`this` 顺序在前，`other` 中不冲突项按 `other` 顺序追加；冲突项保留 `this` 的版本。
- 空集合没有目标约束，可作为注册表未知查询的结果；`empty()` 每次返回新的不可变空集合。
- 集合不可变；无 close；可跨任务只读共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_annotations` | `List<AnnotationInfo>` | 内部列表；构造时复制，保持输入顺序 |

不变量：

- 元素非 null。
- 非空集合中所有元素的 `target()` 相同。
- 非空集合中所有元素的 `targetName()` 相同。
- 同一 `typeName` 与同一 `repeatIndex` 的组合不重复。
- 构造后列表不再修改；`toList()` 返回副本。
- 顺序是源码出现顺序；`first`/`all`/`describe` 均按该顺序。
- 空集合无目标；`merge` 时由非空一侧确定目标。

---

## 4. 生命周期

由编译器/处理器构造；构造后不可变；无 close；无资源；可被 `AnnotationElement`、`AnnotationRegistry`、处理器上下文长期持有；可跨任务只读共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AnnotationSet(List<AnnotationInfo> annotations)` | annotations | 非 null；元素非 null；同一 target/targetName；typeName+repeatIndex 唯一 | null/含 null/跨目标/重复序号 → panic |
| `empty` | 无 | 无 | 无 |

说明：

- 构造时逐个复制到内部列表；调用方之后修改输入列表不影响集合。
- `repeatIndex` 的唯一性只按同一 `typeName` 检查；不同注解类型可以有相同的 `repeatIndex`。
- 不检查注解是否真的声明了 `@Repeatable`；那是编译器的前置校验。
- 不检查 `targetName` 格式；由 `AnnotationInfo` 的构造方保证。

---

## 6. 字段表

见 §3；字段私有、`final`。`_annotations` 保存内部副本。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `empty` | 空集合 | 无 | `AnnotationSet` | 无 |
| `first` | 按类型名取首个 | `String typeName` | `AnnotationInfo?` | null/空 typeName → panic；缺失 → null |
| `all` | 按类型名取全部 | `String typeName` | `List<AnnotationInfo>` | null/空 typeName → panic；缺失 → 空列表 |
| `byTypeName` | 按类型名取子集 | `String typeName` | `AnnotationSet` | null/空 typeName → panic |
| `has` | 是否存在该类型 | `String typeName` | `Bool` | null/空 typeName → panic |
| `length` | 注解数量 | 无 | `Int` | 无 |
| `isEmpty` | 是否为空 | 无 | `Bool` | 无 |
| `merge` | 合并同目标集合 | `AnnotationSet other` | `AnnotationSet` | null/跨目标 → panic |
| `toList` | 列表快照 | 无 | `List<AnnotationInfo>` | 无 |
| `describe` | 稳定诊断文本 | 无 | `String` | 无 |

说明：

- `first`/`all` 的 `typeName` 必须是非空注解类型全限定名；不做简单名匹配。
- `all` 与 `byTypeName` 的区别是返回形态；两者都保持顺序、返回副本/新集合。
- `merge` 的冲突判定是 `typeName + repeatIndex`；冲突时保留 `this` 项，不比较值树。
- `merge` 对空集合幂等；但总是返回新集合，不承诺返回同一对象。
- `describe()` 用 `AnnotationInfo.describe()`，以 `", "` 连接；空集合返回 `""`。
- 不提供 `equals`；集合值比较需要逐项判断。`==` 是引用身份。

---

## 8. 使用的技术

- 不可变集合；
- 防御性复制；
- 有序列表；
- 同目标不变量；
- 按类型名线性过滤；
- 合并去冲突。

---

## 9. 需要的支撑

- 语言：class、final 字段、List、String、Bool、Int；
- 运行时：无；
- 接口：`AnnotationInfo`、`AnnotationTarget`、`List.copy`、`List.push`。

---

## 10. 依赖的特性/接口/类

`AnnotationInfo`、`AnnotationTarget`、`List`、`String`、`Bool`、`Int`。

被 `AnnotationElement`、`AnnotationRegistry`、`AnnotationProcessorContext`（间接）使用。

---

## 11. 所有权与并发

- 引用语义对象，但构造后不可变。
- 可跨任务只读共享；无同步需求。
- `toList`/`all` 返回副本；`byTypeName`/`merge` 返回新集合。
- 相等：没有值相等实现；`==` 是引用身份。顺序参与集合语义，但本类不实现排序比较。
- 空集合可被多个查询共享；`empty()` 不返回全局单例，避免引入隐式全局状态。

---

## 12. 示例与反例

正确：

```xnull
AnnotationInfo primary = new AnnotationInfo(
    "app.Marker",
    AnnotationTarget.Type,
    "app.Device",
    ["name": AnnotationValue.ofString("device")],
    1
)
AnnotationInfo secondary = new AnnotationInfo(
    "app.Marker",
    AnnotationTarget.Type,
    "app.Device",
    ["name": AnnotationValue.ofString("device-2")],
    2
)
AnnotationSet set = new AnnotationSet([primary, secondary])
AnnotationInfo? firstMarker = set.first("app.Marker")
List<AnnotationInfo> markers = set.all("app.Marker")
AnnotationSet subset = set.byTypeName("app.Marker")
Bool present = set.has("app.Marker")
AnnotationSet merged = set.merge(AnnotationSet.empty())
```

反例：把不同 `targetName` 的注解放进同一集合；同一类型使用相同 `repeatIndex`；期望 `first` 返回最后声明；修改 `toList()` 返回值期望改变集合；用 `merge` 合并不同目标的集合；把空集合当“目标未知”的注解容器并附加语义。

---

## 13. 测试/场景义务

- 空集合的 `length`/`isEmpty`/`first`/`all`/`has`/`describe`；
- 单元素与多元素顺序；
- 同类型不同 `repeatIndex`；
- 同类型同 `repeatIndex` 拒绝；
- 跨 target 拒绝；
- 跨 targetName 拒绝；
- `first`/`all`/`byTypeName` 顺序与副本独立性；
- `merge` 空集、无冲突、有冲突、跨目标拒绝、幂等；
- 输入列表修改不影响集合；
- null 参数；
- 并发只读。

---

## 14. XNull 伪代码

```xnull
class AnnotationSet {
    final List<AnnotationInfo> _annotations

    AnnotationSet(List<AnnotationInfo> annotations) {
        if annotations == null {
            throw "AnnotationSet: null annotations"
        }
        _annotations = []
        Int index = 0
        while index < annotations.length() {
            AnnotationInfo annotation = annotations.get(index)
            if annotation == null {
                throw "AnnotationSet: null annotation"
            }
            if _annotations.length() > 0 {
                AnnotationInfo reference = _annotations.get(0)
                if annotation.target() != reference.target() {
                    throw "AnnotationSet: mixed targets"
                }
                if annotation.targetName() != reference.targetName() {
                    throw "AnnotationSet: mixed target names"
                }
            }
            Int scan = 0
            while scan < _annotations.length() {
                AnnotationInfo existing = _annotations.get(scan)
                if existing.typeName() == annotation.typeName()
                    && existing.repeatIndex() == annotation.repeatIndex() {
                    throw "AnnotationSet: duplicate annotation use"
                }
                scan = scan + 1
            }
            _annotations.push(annotation)
            index = index + 1
        }
    }

    static AnnotationSet empty() {
        return new AnnotationSet([])
    }

    AnnotationInfo? first(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationSet.first: empty type name"
        }
        Int index = 0
        while index < _annotations.length() {
            if _annotations.get(index).typeName() == typeName {
                return _annotations.get(index)
            }
            index = index + 1
        }
        return null
    }

    List<AnnotationInfo> all(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationSet.all: empty type name"
        }
        List<AnnotationInfo> result = []
        Int index = 0
        while index < _annotations.length() {
            if _annotations.get(index).typeName() == typeName {
                result.push(_annotations.get(index))
            }
            index = index + 1
        }
        return result
    }

    AnnotationSet byTypeName(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationSet.byTypeName: empty type name"
        }
        return new AnnotationSet(self.all(typeName))
    }

    Bool has(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationSet.has: empty type name"
        }
        return self.first(typeName) != null
    }

    Int length() {
        return _annotations.length()
    }

    Bool isEmpty() {
        return _annotations.length() == 0
    }

    AnnotationSet merge(AnnotationSet other) {
        if other == null {
            throw "AnnotationSet.merge: null other"
        }
        if !self.isEmpty() && !other.isEmpty() {
            AnnotationInfo selfFirst = _annotations.get(0)
            AnnotationInfo otherFirst = other.toList().get(0)
            if selfFirst.target() != otherFirst.target() {
                throw "AnnotationSet.merge: mixed targets"
            }
            if selfFirst.targetName() != otherFirst.targetName() {
                throw "AnnotationSet.merge: mixed target names"
            }
        }
        List<AnnotationInfo> next = self.toList()
        List<AnnotationInfo> incoming = other.toList()
        Int index = 0
        while index < incoming.length() {
            AnnotationInfo candidate = incoming.get(index)
            Bool exists = false
            Int scan = 0
            while scan < next.length() {
                AnnotationInfo existing = next.get(scan)
                if existing.typeName() == candidate.typeName()
                    && existing.repeatIndex() == candidate.repeatIndex() {
                    exists = true
                    break
                }
                scan = scan + 1
            }
            if !exists {
                next.push(candidate)
            }
            index = index + 1
        }
        return new AnnotationSet(next)
    }

    List<AnnotationInfo> toList() {
        return _annotations.copy()
    }

    String describe() {
        String result = ""
        Int index = 0
        while index < _annotations.length() {
            if index > 0 {
                result = result + ", "
            }
            result = result + _annotations.get(index).describe()
            index = index + 1
        }
        return result
    }
}
```
