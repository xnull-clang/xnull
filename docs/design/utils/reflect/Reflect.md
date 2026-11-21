# `Reflect`

| 项 | 值 |
| --- | --- |
| 类型 | `class Reflect` |
| 包 | `xdk.reflect` |
| 稳定性 | `preview` |
| 依赖 | `ReflectKind`、`MemberInfo`、`TypeInfo`、`Error` |

---

## 1. 定位

只读类型元数据静态入口：按名字解析 `TypeInfo`、读取成员、按名查找字段/方法、判断纯元数据可赋值性、生成稳定描述。

不做：构造器元数据、动态调用/构造（X）、基于实例的 `typeOf`、`Object` 根类型、运行时类型注册、注解/泛型/参数/可见性、外部程序集加载、序列化、缓存。

---

## 2. 设计逻辑

- 无状态静态命名空间；私有构造器；全部方法为静态方法。
- `resolve` 是唯一运行时类型入口：校验名称后调用编译器/运行时只读元数据原语 `reflectResolveRaw`；null/空名返回 `InvalidArgument`，未知类型返回 `NotFound`，元数据损坏由原语返回 `DataCorrupted`。
- 元数据是编译期写入二进制的只读快照，不是全局可变注册表；不提供 `register`/`unregister`/`allTypes`，也不从外部程序集按名加载。
- `members` 返回 `TypeInfo` 的成员快照；`field`/`method` 复用 `TypeInfo` 的按名查找，缺失时返回 `NotFound`。
- `isAssignable` 只做名称图遍历：名称相同为真；`Primitive` 只允许名称同一；否则沿 `supertypes` 直接边做传递闭包，用 visited 集合防环；无法解析的父类型名按“无更多信息”跳过，不使整个判断失败。
- `describe` 直接委托 `TypeInfo.describe`，保证同一类型在不同入口下描述一致。
- 无 `Context`、无 I/O、无取消；所有方法为纯 CPU 元数据操作。
- 失败用 `Result`；null 参数属于调用方错误，使用 panic。

---

## 3. 表示与不变量

无实例字段。

不变量：

- 静态命名空间不可实例化；
- `resolve` 对同一名称返回内容一致的独立快照；
- 不缓存、不注册、不修改任何全局状态；
- `field`/`method` 的字段/方法区分与 `TypeInfo` 一致；
- `isAssignable` 对同一输入确定；不因遍历顺序改变结果。

---

## 4. 生命周期

静态命名空间；无 close；无资源；进程内长期可用。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Reflect()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `resolve` | 按名解析类型 | `String typeName` | `Result<TypeInfo, Error>` | `InvalidArgument`/`NotFound`/`DataCorrupted` |
| `members` | 成员快照 | `TypeInfo type` | `List<MemberInfo>` | null → panic |
| `field` | 按名找字段 | `TypeInfo type, String memberName` | `Result<MemberInfo, Error>` | null → panic；`NotFound` |
| `method` | 按名找方法 | `TypeInfo type, String memberName` | `Result<MemberInfo, Error>` | null → panic；`NotFound` |
| `isAssignable` | 元数据可赋值判断 | `TypeInfo source, TypeInfo target` | `Bool` | null → panic |
| `describe` | 单行描述 | `TypeInfo type` | `String` | null → panic |

说明：

- `resolve` 使用精确名称，不做 trim、别名、大小写折叠或后缀匹配；名称必须与元数据中的类型名完全一致；null/空名在进入原语前返回 `InvalidArgument`。
- `resolve` 可解析 `Class`/`Protocol`/`Enum`/`Primitive`；`Primitive` 的 `TypeInfo` 没有成员与父类型。
- `field`/`method` 缺失时返回 `NotFound`；同一名称的字段与方法可以共存，两个入口分别命中。
- `members`/`field`/`method` 只查该 `TypeInfo` 的直接成员；继承成员需沿 `supertypes` 用 `resolve` 逐级查询。
- `isAssignable` 不检查实例、不做装箱/拆箱、不做数值拓宽；`Primitive` 只与同名 `Primitive` 可赋值。
- `isAssignable` 对 `Class`/`Protocol`/`Enum` 统一按名称图判断，不按 kind 额外放行或拒绝。
- `isAssignable` 的传递闭包只使用名称与可解析的直接父类型；父类型不可解析时保留已发现的名称边，不报错。
- `describe` 与 `TypeInfo.describe` 完全一致，不额外添加前缀。
- 所有方法都不改变 `TypeInfo`/`MemberInfo`。

---

## 8. 使用的技术

- 只读元数据读取；
- 按名解析；
- 不可变快照；
- 名称图传递闭包；
- visited 集合防环；
- 稳定字符串格式化；
- 无缓存、无注册表。

---

## 9. 需要的支撑

- 语言：class、静态方法、私有构造器、String、Bool、List、Set、`Result`；
- 运行时：`reflectResolveRaw` 只读元数据原语；
- 接口：`ReflectKind`、`MemberInfo`、`TypeInfo`、`Error`、`BasicError`、`ErrorKind`。

`reflectResolveRaw` 是编译器/运行时内建原语，只读二进制元数据段；签名 `reflectResolveRaw(String typeName) -> Result<TypeInfo, Error>`，不是公开类型，也不是可变注册表。

---

## 10. 依赖的特性/接口/类

`ReflectKind`、`MemberInfo`、`TypeInfo`、`Error`、`BasicError`、`ErrorKind`、`List`、`Set`、`reflectResolveRaw`。

不依赖 `xdk.graph`、`xdk.event`、`xdk.log`；不引入任何额外公开类型。

---

## 11. 所有权与并发

无状态；线程安全；`resolve` 每次返回独立快照；`members` 返回快照；`isAssignable` 只读；无资源；无 close。

---

## 12. 示例与反例

正确：

```xnull
Result<TypeInfo, Error> resolved = Reflect.resolve("Point")
if resolved.isOk() {
    TypeInfo point = resolved.value()
    List<MemberInfo> members = Reflect.members(point)
    Result<MemberInfo, Error> distance = Reflect.method(point, "distance")
    Result<MemberInfo, Error> x = Reflect.field(point, "x")
    Bool assignable = Reflect.isAssignable(point, point)
    String text = Reflect.describe(point)
}
```

正确：`Reflect.resolve("Int").value().kind() == ReflectKind.Primitive`。  
反例：用 `Reflect` 调用方法或构造实例；假设存在 `Object` 根类型；期望未知类型返回 null；把 `field` 用于方法；假设 `isAssignable` 会做数值拓宽；依赖全局注册表动态添加类型；修改 `members` 返回值并期望影响类型元数据。

---

## 13. 测试/场景义务

解析：类/协议/枚举/内建值类型；null/空名；未知名；精确名称；大小写不匹配拒绝；损坏元数据。  
成员：`members` 快照；字段命中/缺失；方法命中/缺失；字段与方法同名；null 参数。  
可赋值：名称同一；直接父类型；传递父类型；协议实现；`Primitive` 仅同一；环状元数据；不可解析父类型；null 参数。  
描述：与 `TypeInfo.describe` 一致；四种 kind。  
并发：多任务同时解析/查询；快照互不影响；无全局状态；无缓存陈旧问题。

---

## 14. XNull 伪代码

```xnull
class Reflect {
    private Reflect() {
    }

    static Result<TypeInfo, Error> resolve(String typeName) {
        if typeName == null || typeName == "" {
            return Err(new BasicError(ErrorKind.InvalidArgument,
                "Reflect.resolve: empty type name"))
        }
        return reflectResolveRaw(typeName)
    }

    static List<MemberInfo> members(TypeInfo type) {
        if type == null { throw "Reflect.members: null type" }
        return type.members()
    }

    static Result<MemberInfo, Error> field(TypeInfo type, String memberName) {
        if type == null || memberName == null {
            throw "Reflect.field: null argument"
        }
        MemberInfo? found = type.fieldOrNull(memberName)
        if found == null {
            return Err(new BasicError(ErrorKind.NotFound,
                "Reflect.field: " + type.name() + "." + memberName + " not found"))
        }
        return Ok(found)
    }

    static Result<MemberInfo, Error> method(TypeInfo type, String memberName) {
        if type == null || memberName == null {
            throw "Reflect.method: null argument"
        }
        MemberInfo? found = type.methodOrNull(memberName)
        if found == null {
            return Err(new BasicError(ErrorKind.NotFound,
                "Reflect.method: " + type.name() + "." + memberName + " not found"))
        }
        return Ok(found)
    }

    static Bool isAssignable(TypeInfo source, TypeInfo target) {
        if source == null || target == null {
            throw "Reflect.isAssignable: null argument"
        }
        if source.name() == target.name() { return true }
        if source.kind() == ReflectKind.Primitive || target.kind() == ReflectKind.Primitive {
            return false
        }
        Set<String> visited = new Set<String>()
        visited.add(source.name())
        List<String> pending = source.supertypes()
        Int index = 0
        while index < pending.length() {
            String current = pending.get(index)
            index = index + 1
            if visited.has(current) { continue }
            visited.add(current)
            if current == target.name() { return true }
            Result<TypeInfo, Error> resolved = Reflect.resolve(current)
            if resolved.isOk() {
                List<String> parents = resolved.value().supertypes()
                Int parentIndex = 0
                while parentIndex < parents.length() {
                    pending.push(parents.get(parentIndex))
                    parentIndex = parentIndex + 1
                }
            }
        }
        return false
    }

    static String describe(TypeInfo type) {
        if type == null { throw "Reflect.describe: null type" }
        return type.describe()
    }
}
```
