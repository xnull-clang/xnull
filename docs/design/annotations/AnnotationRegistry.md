# `AnnotationRegistry`

| 项 | 值 |
| --- | --- |
| 类型 | `class AnnotationRegistry` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | `AnnotationInfo`、`AnnotationSet`、`AnnotationTarget`、`Map`、`List`、`String`、`Int` |

---

## 1. 定位

编译器生成的只读注解元数据注册表。按目标种类和规范名查询 `AnnotationSet`，并提供带注解类型名列表。

不做：不做运行时反射、不做类路径扫描、不做动态代理、不做注解类加载、不做全局可变注册、不做插件发现。

---

## 2. 设计逻辑

- 注册表由编译器生成代码构造；构造参数是扁平的 `AnnotationInfo` 列表，注册表在构造时按 `target + targetName` 分组。
- 运行时查询只访问生成表，不访问类文件、不调用 `Class.forName`、不扫描模块/包。
- 所有查询返回 `AnnotationSet`；未命中返回空集合，不返回 null，避免调用方分支与空指针。
- `ofType`/`ofField`/`ofMethod`/`ofConstructor`/`ofParameter`/`ofPackage`/`ofEnumItem` 用规范名拼装查询键；`ofTarget` 接受任意目标种类与生成名，覆盖 `TypeParameter`/`TypeUse`。
- `types()` 只返回注册表中实际带注解的类型名，按字典序排序；不返回未注解类型，也不枚举运行时类。
- 注册表只应包含编译器选中的 `Runtime` 保留注解；保留策略过滤在生成阶段完成，注册表不重新判断。
- 构造后不可变；映射和集合都不再修改；可跨任务只读共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_targets` | `Map<String, AnnotationSet>` | 键为 `targetKey(target, targetName)`；值为非空同目标集合 |

不变量：

- `_targets` 非 null；构造后不再修改。
- 每个键都来自 `targetKey`；每个值非空，且其元素的 `target`/`targetName` 与键一致。
- 同一键只对应一个 `AnnotationSet`；重复注解由 `AnnotationSet` 的 `typeName + repeatIndex` 规则处理。
- 只包含 `Runtime` 保留的注解（由生成器保证）。
- 查询未命中返回 `AnnotationSet.empty()`；空集合不携带目标。
- 不持有编译期可变状态；不依赖反射缓存。

---

## 4. 生命周期

由生成的静态初始化代码构造；进程内长期有效；无 close；无资源；不可变；可跨任务共享；进程退出时随普通对象回收。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AnnotationRegistry(List<AnnotationInfo> annotations)` | annotations | 非 null；元素非 null；目标名符合规范；同目标同类型同 repeatIndex 不重复 | null/含 null/非法目标名/重复 → panic |

说明：

- 构造参数是生成器输出的扁平列表；注册表不读取源码、不读取类文件。
- 分组顺序不影响查询；`types()` 会排序。
- 空列表合法，生成空注册表。
- 不校验注解保留策略；生成器必须只传入 `Runtime` 项。
- 不校验 `AnnotationInfo` 的 `targetName` 是否符合 §2 的拼装规则；不符合时对应查询不会命中。

---

## 6. 字段表

见 §3；字段私有、`final`。`_targets` 保存构造期建立的内部映射，之后只读。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `ofTarget` | 任意目标查询 | `AnnotationTarget target, String targetName` | `AnnotationSet` | null/空名 → panic；未命中 → 空集合 |
| `ofType` | 类型注解 | `String typeName` | `AnnotationSet` | null/空名 → panic；未命中 → 空集合 |
| `ofField` | 字段注解 | `String ownerName, String fieldName` | `AnnotationSet` | null/空名 → panic；未命中 → 空集合 |
| `ofMethod` | 方法注解 | `String ownerName, String methodName, List<String> parameterTypeNames` | `AnnotationSet` | null/空名/含 null 参数类型 → panic；未命中 → 空集合 |
| `ofConstructor` | 构造器注解 | `String ownerName, List<String> parameterTypeNames` | `AnnotationSet` | null/空名/含 null 参数类型 → panic；未命中 → 空集合 |
| `ofParameter` | 参数注解 | `String memberTargetName, Int parameterIndex` | `AnnotationSet` | null/空名/负下标 → panic；未命中 → 空集合 |
| `ofPackage` | 包注解 | `String packageName` | `AnnotationSet` | null/空名 → panic；未命中 → 空集合 |
| `ofEnumItem` | 枚举项注解 | `String enumTypeName, String enumItemName` | `AnnotationSet` | null/空名 → panic；未命中 → 空集合 |
| `types` | 带注解类型名列表 | 无 | `List<String>` | 无 |

说明：

- `ofField` 的规范名是 `ownerName + "#" + fieldName`。
- `ofMethod` 的规范名是 `ownerName + "#" + methodName + "(" + 参数类型全限定名逗号连接 + ")"`。
- `ofConstructor` 的规范名是 `ownerName + "#<init>(" + 参数类型全限定名逗号连接 + ")"`。
- `ofParameter` 的 `memberTargetName` 是所属方法/构造器的规范名；参数下标从 0 开始。
- `ofEnumItem` 的规范名是 `enumTypeName + "#" + enumItemName`。
- `Deinit` 没有专用便捷方法；使用 `ofTarget(AnnotationTarget.Deinit, "owner#deinit()")`。
- `ofPackage` 的规范名就是包名。
- `types()` 只列 `AnnotationTarget.Type` 的非空集合，按字典序排序；不包含包、成员、参数、枚举项。
- 所有查询都不修改注册表；`AnnotationSet` 本身不可变，调用方无需再复制。

私有辅助（不属于公开 API）：

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `targetKey` | 生成目标映射键 | `AnnotationTarget target, String targetName` | `String` | null/空名 → panic |
| `parameterKey` | 拼接参数类型列表 | `List<String> parameterTypeNames` | `String` | null/含 null/空名 → panic |

---

## 8. 使用的技术

- 生成式静态元数据；
- 不可变映射；
- 规范目标名；
- 防御性分组；
- 线性/哈希查询；
- 无反射运行时。

---

## 9. 需要的支撑

- 语言：class、final 字段、Map、List、String、Int；
- 编译器/生成器：生成扁平 `AnnotationInfo` 列表、保留策略过滤、确定性排序；
- 运行时：只读容器与普通对象，无反射、无类加载。

---

## 10. 依赖的特性/接口/类

`AnnotationInfo`、`AnnotationSet`、`AnnotationTarget`、`Map`、`List`、`String`、`Int`。

被应用代码、框架运行时元数据面、IDE/文档工具读取；不被编译器前端反向依赖。

---

## 11. 所有权与并发

- 引用语义对象，但构造后不可变。
- 可跨任务只读共享；`_targets` 构造后不再修改，读取无需同步。
- 查询返回内部 `AnnotationSet` 引用；由于其不可变，不需要复制。
- `types()` 每次返回新列表；修改返回值不影响注册表。
- 相等：没有值相等实现；`==` 是引用身份。注册表身份由生成代码持有。

---

## 12. 示例与反例

正确：

```xnull
AnnotationInfo readOnly = new AnnotationInfo(
    "app.ReadOnly",
    AnnotationTarget.Field,
    "app.Device#name",
    [:],
    1
)
AnnotationInfo marker = new AnnotationInfo(
    "app.Marker",
    AnnotationTarget.Type,
    "app.Device",
    ["name": AnnotationValue.ofString("device")],
    1
)
AnnotationRegistry registry = new AnnotationRegistry([readOnly, marker])
AnnotationSet typeAnnotations = registry.ofType("app.Device")
AnnotationInfo? markerInfo = typeAnnotations.first("app.Marker")
AnnotationSet fieldAnnotations = registry.ofField("app.Device", "name")
Bool readOnlyField = fieldAnnotations.has("app.ReadOnly")
List<String> annotatedTypes = registry.types()
```

反例：期望 `ofType` 对未知类型返回 null；期望 `types()` 枚举所有已知类型（包括未注解类型）；用简单名查询；把注册表当可变注册中心；在查询时反射读取类文件；把 `Source`/`Binary` 注解放进注册表；在运行时把新注解追加到已生成注册表。

---

## 13. 测试/场景义务

- 空注册表的所有查询返回空集合；
- `ofType` 命中/未命中；
- `ofField`/`ofMethod`/`ofConstructor` 规范名命中；
- 方法重载通过参数类型列表区分；
- `ofParameter` 下标 0/1/越界未命中；
- `ofPackage`/`ofEnumItem`；
- `ofTarget` 覆盖 `TypeParameter`/`TypeUse`/`Deinit`；
- `types()` 只含类型、排序、副本独立；
- 重复 `repeatIndex` 被拒绝；
- 生成器只传入 `Runtime` 项；
- 并发只读；
- 无反射/类加载调用。

---

## 14. XNull 伪代码

```xnull
class AnnotationRegistry {
    final Map<String, AnnotationSet> _targets

    AnnotationRegistry(List<AnnotationInfo> annotations) {
        if annotations == null {
            throw "AnnotationRegistry: null annotations"
        }
        Map<String, List<AnnotationInfo>> grouped = [:]
        List<String> order = []
        Int index = 0
        while index < annotations.length() {
            AnnotationInfo annotation = annotations.get(index)
            if annotation == null {
                throw "AnnotationRegistry: null annotation"
            }
            String key = targetKey(annotation.target(), annotation.targetName())
            if !grouped.has(key) {
                grouped.put(key, [])
                order.push(key)
            }
            grouped.get(key).push(annotation)
            index = index + 1
        }
        _targets = [:]
        Int orderIndex = 0
        while orderIndex < order.length() {
            String key = order.get(orderIndex)
            _targets.put(key, new AnnotationSet(grouped.get(key)))
            orderIndex = orderIndex + 1
        }
    }

    AnnotationSet ofTarget(AnnotationTarget target, String targetName) {
        String key = targetKey(target, targetName)
        if _targets.has(key) {
            return _targets.get(key)
        }
        return AnnotationSet.empty()
    }

    AnnotationSet ofType(String typeName) {
        return self.ofTarget(AnnotationTarget.Type, typeName)
    }

    AnnotationSet ofField(String ownerName, String fieldName) {
        if ownerName == null || ownerName == "" {
            throw "AnnotationRegistry.ofField: empty owner name"
        }
        if fieldName == null || fieldName == "" {
            throw "AnnotationRegistry.ofField: empty field name"
        }
        return self.ofTarget(AnnotationTarget.Field, ownerName + "#" + fieldName)
    }

    AnnotationSet ofMethod(String ownerName, String methodName,
                           List<String> parameterTypeNames) {
        if ownerName == null || ownerName == "" {
            throw "AnnotationRegistry.ofMethod: empty owner name"
        }
        if methodName == null || methodName == "" {
            throw "AnnotationRegistry.ofMethod: empty method name"
        }
        String targetName = ownerName + "#" + methodName
            + "(" + parameterKey(parameterTypeNames) + ")"
        return self.ofTarget(AnnotationTarget.Method, targetName)
    }

    AnnotationSet ofConstructor(String ownerName, List<String> parameterTypeNames) {
        if ownerName == null || ownerName == "" {
            throw "AnnotationRegistry.ofConstructor: empty owner name"
        }
        String targetName = ownerName + "#<init>("
            + parameterKey(parameterTypeNames) + ")"
        return self.ofTarget(AnnotationTarget.Constructor, targetName)
    }

    AnnotationSet ofParameter(String memberTargetName, Int parameterIndex) {
        if memberTargetName == null || memberTargetName == "" {
            throw "AnnotationRegistry.ofParameter: empty member target name"
        }
        if parameterIndex < 0 {
            throw "AnnotationRegistry.ofParameter: negative parameter index"
        }
        String targetName = memberTargetName + "#" + parameterIndex
        return self.ofTarget(AnnotationTarget.Parameter, targetName)
    }

    AnnotationSet ofPackage(String packageName) {
        return self.ofTarget(AnnotationTarget.Package, packageName)
    }

    AnnotationSet ofEnumItem(String enumTypeName, String enumItemName) {
        if enumTypeName == null || enumTypeName == "" {
            throw "AnnotationRegistry.ofEnumItem: empty enum type name"
        }
        if enumItemName == null || enumItemName == "" {
            throw "AnnotationRegistry.ofEnumItem: empty enum item name"
        }
        String targetName = enumTypeName + "#" + enumItemName
        return self.ofTarget(AnnotationTarget.EnumItem, targetName)
    }

    List<String> types() {
        List<String> result = []
        List<String> keys = _targets.keys()
        Int index = 0
        while index < keys.length() {
            AnnotationSet set = _targets.get(keys.get(index))
            AnnotationInfo head = set.toList().get(0)
            if head.target() == AnnotationTarget.Type {
                result.push(head.targetName())
            }
            index = index + 1
        }
        result.sortBy((String left, String right) -> left < right)
        return result
    }

    private static String targetKey(AnnotationTarget target, String targetName) {
        if target == null {
            throw "AnnotationRegistry.targetKey: null target"
        }
        if targetName == null || targetName == "" {
            throw "AnnotationRegistry.targetKey: empty target name"
        }
        if target == AnnotationTarget.Package {
            return "package:" + targetName
        }
        if target == AnnotationTarget.Type {
            return "type:" + targetName
        }
        if target == AnnotationTarget.TypeParameter {
            return "type_parameter:" + targetName
        }
        if target == AnnotationTarget.Field {
            return "field:" + targetName
        }
        if target == AnnotationTarget.Method {
            return "method:" + targetName
        }
        if target == AnnotationTarget.Constructor {
            return "constructor:" + targetName
        }
        if target == AnnotationTarget.Deinit {
            return "deinit:" + targetName
        }
        if target == AnnotationTarget.Parameter {
            return "parameter:" + targetName
        }
        if target == AnnotationTarget.TypeUse {
            return "type_use:" + targetName
        }
        return "enum_item:" + targetName
    }

    private static String parameterKey(List<String> parameterTypeNames) {
        if parameterTypeNames == null {
            throw "AnnotationRegistry.parameterKey: null parameter types"
        }
        String result = ""
        Int index = 0
        while index < parameterTypeNames.length() {
            String typeName = parameterTypeNames.get(index)
            if typeName == null || typeName == "" {
                throw "AnnotationRegistry.parameterKey: empty parameter type"
            }
            if index > 0 {
                result = result + ","
            }
            result = result + typeName
            index = index + 1
        }
        return result
    }
}
```
