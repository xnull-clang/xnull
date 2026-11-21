# `TypeInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class TypeInfo` |
| 包 | `xdk.reflect` |
| 稳定性 | `preview` |
| 依赖 | `ReflectKind`、`MemberInfo` |

---

## 1. 定位

不可变类型元数据快照：类型名、种类、成员列表、直接父类型/协议名；提供字段/方法按名查找与稳定描述。

不做：实例 `typeOf`、`Object` 根类型、构造器元数据、动态调用/构造、注解、泛型实参、方法参数元数据、可见性、外部程序集加载、可变注册表。

---

## 2. 设计逻辑

- 四个 final 字段：`_name`、`_kind`、`_members`、`_supertypes`。
- 构造时复制 `members` 与 `supertypes`，调用方之后修改原列表不影响快照。
- 每个成员的 `ownerTypeName` 必须等于类型名；同一成员种类内成员名唯一；字段与方法可以同名，由 `fieldOrNull`/`methodOrNull` 区分。
- `supertypes` 只保存直接父类型/协议名，保持声明顺序；拒绝空名、自身名、重复名。
- `Primitive` 必须没有成员、没有父类型；其他 kind 不强制成员形态。
- `fieldOrNull`/`methodOrNull` 线性查找**本类型声明的**成员，返回首个匹配或 null；继承成员不展开，继承关系由 `supertypes` 表达。
- `members`/`supertypes` 返回独立快照；不可变；无 close。
- `describe` 使用 `reflectKindName`，输出稳定单行。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_name` | `String` | 类型名，非空 |
| `_kind` | `ReflectKind` | 类型分类，非 null |
| `_members` | `List<MemberInfo>` | 成员快照，可为空 |
| `_supertypes` | `List<String>` | 直接父类型/协议名，可为空 |

不变量：名称非空；kind 非 null；成员 owner 与类型名一致；同一 `(memberName, isMethod)` 不重复；父类型名非空、无重复、无自身；`Primitive` 元数据为空；两个列表均为快照。

---

## 4. 生命周期

不可变；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `TypeInfo(String name, ReflectKind kind, List<MemberInfo> members, List<String> supertypes)` | 全部 | 名称非空；kind 非 null；列表非 null；成员 owner 匹配；成员键唯一；父类型合法；`Primitive` 为空 | 非法 → panic |

说明：

- 构造器验证单类型内部一致性，不验证父类型是否真实存在；跨类型解析由 `Reflect.resolve` 负责。
- 测试/工具可以构造合成类型，但合成元数据不代表运行时类型。
- 不提供增量 `addMember`；需要变化时构造新快照。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 类型名 | 无 | `String` | 无 |
| `kind` | 类型分类 | 无 | `ReflectKind` | 无 |
| `members` | 成员快照 | 无 | `List<MemberInfo>` | 无 |
| `supertypes` | 直接父类型快照 | 无 | `List<String>` | 无 |
| `fieldOrNull` | 按名找字段 | `String memberName` | `MemberInfo?` | null → panic |
| `methodOrNull` | 按名找方法 | `String memberName` | `MemberInfo?` | null → panic |
| `describe` | 单行描述 | 无 | `String` | 无 |

说明：

- `members()`/`supertypes()` 每次返回新列表；修改返回值不影响 `TypeInfo`。
- `members()` 只包含本类型声明的成员，不合并父类型成员。
- `fieldOrNull` 只匹配 `isMethod() == false` 的成员；`methodOrNull` 只匹配 `isMethod() == true`；两者都只查本类型声明的成员。
- 同一名称的字段与方法可以共存；两个查找互不干扰。
- `describe` 格式：
  - 有父类型：`class Point : Base, Named (members=3)`
  - 无父类型：`primitive Int (members=0)`
- 成员顺序与父类型顺序保持构造输入顺序，不排序。

---

## 8. 使用的技术

- 不可变快照；
- 列表复制；
- 线性成员查找；
- 成员键去重；
- 名称图（仅直接边）；
- 稳定字符串格式化。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、List、Set、`MemberInfo?`；
- 运行时：`str`；
- 接口：`ReflectKind`、`MemberInfo`、`reflectKindName`。

---

## 10. 依赖的特性/接口/类

`ReflectKind`、`MemberInfo`、`reflectKindName`、`List`、`Set`、`str`。

---

## 11. 所有权与并发

不可变；引用语义；成员对象本身也不可变；快照可并发读取；无资源；无 close。

---

## 12. 示例与反例

正确：`new TypeInfo("Point", ReflectKind.Class, [new MemberInfo("Point", "x", "Int", false, false)], ["Base"])`。  
正确：`point.fieldOrNull("x")` 返回字段；`point.methodOrNull("distance")` 返回方法；缺失返回 null。  
反例：把方法放进字段索引；同一字段名重复；把自身名写进 `supertypes`；给 `Primitive` 添加成员；修改 `members()` 返回值并期望影响快照；用 `fieldOrNull` 查找方法。

---

## 13. 测试/场景义务

构造校验：空名、null kind、null 列表、owner 不匹配、重复字段、重复方法、字段与方法同名、父类型重复/自身、`Primitive` 非空。  
查询：字段命中/缺失、方法命中/缺失、字段与方法同名分流、空成员类型。  
快照：修改输入列表与返回列表均不影响内部状态。  
描述：有/无父类型、四种 kind、成员计数；并发读取；多任务共享。

---

## 14. XNull 伪代码

```xnull
class TypeInfo {
    final String _name
    final ReflectKind _kind
    final List<MemberInfo> _members
    final List<String> _supertypes

    TypeInfo(String name, ReflectKind kind,
             List<MemberInfo> members, List<String> supertypes) {
        if name == null || name == "" { throw "TypeInfo: empty name" }
        if kind == null { throw "TypeInfo: null kind" }
        if members == null { throw "TypeInfo: null members" }
        if supertypes == null { throw "TypeInfo: null supertypes" }
        _name = name
        _kind = kind
        _members = []
        Set<String> seen = new Set<String>()
        Int index = 0
        while index < members.length() {
            MemberInfo member = members.get(index)
            if member == null { throw "TypeInfo: null member" }
            if member.ownerTypeName() != name {
                throw "TypeInfo: member owner mismatch for " + member.memberName()
            }
            String key = "f:" + member.memberName()
            if member.isMethod() { key = "m:" + member.memberName() }
            if !seen.add(key) {
                throw "TypeInfo: duplicate member " + member.memberName()
            }
            _members.push(member)
            index = index + 1
        }
        _supertypes = []
        index = 0
        while index < supertypes.length() {
            String parent = supertypes.get(index)
            if parent == null || parent == "" {
                throw "TypeInfo: empty supertype"
            }
            if parent == name { throw "TypeInfo: self supertype" }
            if _supertypes.contains(parent) {
                throw "TypeInfo: duplicate supertype " + parent
            }
            _supertypes.push(parent)
            index = index + 1
        }
        if kind == ReflectKind.Primitive && (_members.length() > 0 || _supertypes.length() > 0) {
            throw "TypeInfo: primitive metadata must be empty"
        }
    }

    String name() { return _name }
    ReflectKind kind() { return _kind }

    List<MemberInfo> members() {
        List<MemberInfo> copy = []
        Int index = 0
        while index < _members.length() {
            copy.push(_members.get(index))
            index = index + 1
        }
        return copy
    }

    List<String> supertypes() {
        List<String> copy = []
        Int index = 0
        while index < _supertypes.length() {
            copy.push(_supertypes.get(index))
            index = index + 1
        }
        return copy
    }

    MemberInfo? fieldOrNull(String memberName) {
        if memberName == null { throw "TypeInfo.fieldOrNull: null name" }
        Int index = 0
        while index < _members.length() {
            MemberInfo member = _members.get(index)
            if !member.isMethod() && member.memberName() == memberName {
                return member
            }
            index = index + 1
        }
        return null
    }

    MemberInfo? methodOrNull(String memberName) {
        if memberName == null { throw "TypeInfo.methodOrNull: null name" }
        Int index = 0
        while index < _members.length() {
            MemberInfo member = _members.get(index)
            if member.isMethod() && member.memberName() == memberName {
                return member
            }
            index = index + 1
        }
        return null
    }

    String describe() {
        String text = reflectKindName(_kind) + " " + _name
        if _supertypes.length() > 0 {
            text = text + " : "
            Int index = 0
            while index < _supertypes.length() {
                if index > 0 { text = text + ", " }
                text = text + _supertypes.get(index)
                index = index + 1
            }
        }
        return text + " (members=" + str(_members.length()) + ")"
    }
}
```
