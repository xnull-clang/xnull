# `MemberInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class MemberInfo` |
| 包 | `xdk.reflect` |
| 稳定性 | `preview` |
| 依赖 | 无（仅语言 `String`/`Bool`） |

---

## 1. 定位

不可变成员元数据：所属类型名、成员名、声明类型名、是否静态、是否方法；提供稳定单行描述。

不做：参数名/参数类型、注解、可见性、泛型签名、默认值、构造器元数据、字段读写、方法调用、成员值。

---

## 2. 设计逻辑

- 五个 final 字段：`_ownerTypeName`、`_memberName`、`_typeName`、`_isStatic`、`_isMethod`。
- `_typeName` 对字段表示声明值类型；对方法表示返回类型；不展开参数列表。
- `_isMethod` 区分字段与方法；`_isStatic` 与两者正交，表示无接收者。
- 构造函数校验三个名称非空；拒绝 null。
- 只保存所属类型名，不持有 `TypeInfo` 引用，避免类型与成员之间形成环。
- `describe` 使用固定格式；字段与方法、静态与非静态各有一种形态。
- 不可变；无 close；可跨任务共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_ownerTypeName` | `String` | 所属类型名，非空 |
| `_memberName` | `String` | 成员名，非空 |
| `_typeName` | `String` | 字段类型或方法返回类型，非空 |
| `_isStatic` | `Bool` | 是否静态成员 |
| `_isMethod` | `Bool` | 是否方法；false 表示字段 |

不变量：三个名称非空；`isMethod` 为 true 时 `typeName` 是返回类型；`isStatic` 不改变成员种类；构造后不可变。

---

## 4. 生命周期

不可变；无 close；无资源；可跨任务共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `MemberInfo(String ownerTypeName, String memberName, String typeName, Bool isStatic, Bool isMethod)` | 全部 | 三个名称非空；Bool 为值类型 | 名称 null/空 → panic |

说明：

- 构造器不验证成员是否真实存在；真实性由 `Reflect.resolve` 返回的元数据保证。
- 测试/工具可以构造合成成员，但不得把合成元数据当作运行时授权依据。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `ownerTypeName` | 所属类型名 | 无 | `String` | 无 |
| `memberName` | 成员名 | 无 | `String` | 无 |
| `typeName` | 字段类型/返回类型 | 无 | `String` | 无 |
| `isStatic` | 是否静态 | 无 | `Bool` | 无 |
| `isMethod` | 是否方法 | 无 | `Bool` | 无 |
| `describe` | 单行描述 | 无 | `String` | 无 |

说明：

- `describe` 的稳定格式：
  - 实例字段：`field Owner.name: Type`
  - 静态字段：`static field Owner.name: Type`
  - 实例方法：`method Owner.name(): Type`
  - 静态方法：`static method Owner.name(): Type`
- 方法描述中的 `()` 只表示方法形态；参数细节不暴露。
- `describe` 不包含注释、注解或可见性。

---

## 8. 使用的技术

- 不可变值对象；
- 名称快照；
- 布尔标志组合；
- 稳定字符串格式化。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、字符串拼接；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无；只使用语言内建 `String`/`Bool`。

---

## 11. 所有权与并发

不可变；引用语义；无资源；可并发读取；`describe` 无副作用。

---

## 12. 示例与反例

正确：`new MemberInfo("Point", "distance", "Double", false, true).describe()` → `method Point.distance(): Double`。  
正确：`new MemberInfo("Config", "Default", "Config", true, false).describe()` → `static field Config.Default: Config`。  
反例：把参数类型拼进 `typeName`；用空成员名表示未知；假设 `isMethod` 蕴含非静态；构造后试图修改；用合成 `MemberInfo` 绕过真实元数据检查。

---

## 13. 测试/场景义务

三个名称访问；`isStatic`/`isMethod` 四种组合；`describe` 四种格式；空名称/null 拒绝；不可变性；多任务共享；方法描述不暴露参数；字段类型与方法返回类型语义区分。

---

## 14. XNull 伪代码

```xnull
class MemberInfo {
    final String _ownerTypeName
    final String _memberName
    final String _typeName
    final Bool _isStatic
    final Bool _isMethod

    MemberInfo(String ownerTypeName, String memberName, String typeName,
               Bool isStatic, Bool isMethod) {
        if ownerTypeName == null || ownerTypeName == "" {
            throw "MemberInfo: empty owner type name"
        }
        if memberName == null || memberName == "" {
            throw "MemberInfo: empty member name"
        }
        if typeName == null || typeName == "" {
            throw "MemberInfo: empty type name"
        }
        _ownerTypeName = ownerTypeName
        _memberName = memberName
        _typeName = typeName
        _isStatic = isStatic
        _isMethod = isMethod
    }

    String ownerTypeName() { return _ownerTypeName }
    String memberName() { return _memberName }
    String typeName() { return _typeName }
    Bool isStatic() { return _isStatic }
    Bool isMethod() { return _isMethod }

    String describe() {
        String prefix = ""
        if _isStatic { prefix = "static " }
        if _isMethod {
            return prefix + "method " + _ownerTypeName + "." + _memberName
                + "(): " + _typeName
        }
        return prefix + "field " + _ownerTypeName + "." + _memberName
            + ": " + _typeName
    }
}
```
