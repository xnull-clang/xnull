# `AnnotationElement`

| 项 | 值 |
| --- | --- |
| 类型 | `class AnnotationElement` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | `AnnotationTarget`、`AnnotationSet`、`String`、`Bool` |

---

## 1. 定位

处理器眼中的目标元素不可变视图：目标种类、所有者名、元素名、相关类型名、注解集合、源码名。

不做：不做符号表、不做类型检查、不做声明修改、不做运行时反射、不做源码解析。

---

## 2. 设计逻辑

- 编译器在构建期把已解析声明投影成 `AnnotationElement`，处理器只读该投影。
- 一个元素对应一个注解目标；字段、方法、构造器、参数、枚举项分别投影，不合并。
- `ownerName` 是所属包或所属类型的全限定名；`Package` 元素允许为空（根包）。
- `name` 是元素简单名；构造器使用 `<init>`；`TypeUse` 使用编译器生成的源码角色标签。
- `typeName` 是该元素相关的类型全限定名；不同目标含义见 §3。
- `annotations` 是该元素上的注解集合；构造时校验集合的 `target` 与元素一致。
- `sourceName` 是源码文件名/路径，只用于诊断与生成来源标注，不保证绝对路径。
- 元素不持有 AST、不持有编译器可变句柄；处理器不能通过它修改声明。
- 不可变；可跨阶段/任务只读共享。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_target` | `AnnotationTarget` | 元素种类，final，非 null |
| `_ownerName` | `String` | 所属包/类型全限定名；Package 可为空 |
| `_name` | `String` | 元素简单名或编译器角色标签，非空 |
| `_typeName` | `String` | 相关类型名（全限定名，或 `void`），非空 |
| `_annotations` | `AnnotationSet` | 该元素的注解集合，非 null |
| `_sourceName` | `String` | 源码名，非空 |

各目标的字段含义：

| 目标 | ownerName | name | typeName |
| --- | --- | --- | --- |
| `Package` | 父包名或空串 | 包名 | 包名 |
| `Type` | 包名 | 简单类型名 | 类型全限定名 |
| `TypeParameter` | 所属类型全限定名 | 参数名 | 所属类型全限定名 |
| `Field` | 所属类型全限定名 | 字段名 | 字段类型全限定名 |
| `Method` | 所属类型全限定名 | 方法名 | 返回类型全限定名或 `void` |
| `Constructor` | 所属类型全限定名 | `<init>` | 所属类型全限定名 |
| `Deinit` | 所属类型全限定名 | `deinit` | `void` |
| `Parameter` | 所属类型全限定名 | 参数名 | 参数类型全限定名 |
| `TypeUse` | 所属声明名 | 编译器角色标签 | 被使用类型全限定名 |
| `EnumItem` | 枚举类型全限定名 | 枚举项名 | 枚举类型全限定名 |

不变量：

- `target` 非 null；`name`/`typeName`/`sourceName` 非空。
- 非 `Package` 元素的 `ownerName` 非空。
- `annotations` 非 null；非空时其元素的 `target` 与 `_target` 一致。
- `annotations` 的 `targetName` 与元素规范名的一致性由编译器保证，本类不重新拼装。
- 元素不可变；不暴露内部可变集合。

---

## 4. 生命周期

由编译器在解析/语义分析阶段创建；在一次构建内长期有效；无 close；无资源；构建结束后随编译器上下文回收；不进入运行时。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AnnotationElement(AnnotationTarget target, String ownerName, String name, String typeName, AnnotationSet annotations, String sourceName)` | 全部 | target 是枚举成员（枚举不可为 null）；ownerName 非 null；name/typeName/sourceName 非空；annotations 非 null 且目标一致 | null/空名/目标不一致 → panic |

说明：

- `Package` 元素允许 `ownerName == ""`；其他目标拒绝空所有者。
- `annotations` 可以为空集合；空集合不携带目标，不做目标一致性检查。
- 构造时只保存传入的不可变 `AnnotationSet`，不复制集合内部数据。
- 不校验 `sourceName` 是否为真实路径；构建系统负责路径规范化。
- 不提供公开构造以外的工厂；编译器直接构造。

---

## 6. 字段表

见 §3；字段私有、`final`。`_annotations` 引用不可变 `AnnotationSet`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `target` | 元素种类 | 无 | `AnnotationTarget` | 无 |
| `ownerName` | 所属包/类型名 | 无 | `String` | 无 |
| `name` | 元素名 | 无 | `String` | 无 |
| `typeName` | 相关类型名 | 无 | `String` | 无 |
| `annotations` | 注解集合 | 无 | `AnnotationSet` | 无 |
| `sourceName` | 源码名 | 无 | `String` | 无 |
| `hasAnnotation` | 是否有指定注解 | `String typeName` | `Bool` | null/空名 → panic |
| `firstAnnotation` | 首个指定注解 | `String typeName` | `AnnotationInfo?` | null/空名 → panic；缺失 → null |
| `describe` | 稳定诊断文本 | 无 | `String` | 无 |

说明：

- `hasAnnotation`/`firstAnnotation` 委托给 `_annotations`；`typeName` 是注解类型全限定名。
- `annotations()` 返回内部不可变集合引用；调用方无法修改。
- `describe()` 对 Package 输出 `package <name>`；其他目标输出 `<ownerName>#<name>:<typeName>`。
- 元素不提供 `targetName()`；需要规范名时从注解的 `targetName` 或编译器上下文获取。
- 不提供 `modifiers`/`visibility`/`isStatic` 等符号信息；本类只服务注解处理。

---

## 8. 使用的技术

- 不可变投影；
- 编译期符号视图；
- 目标种类分派；
- 委托查询；
- 源码来源标注。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool；
- 编译器：符号表投影、目标规范名、注解挂接；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

`AnnotationTarget`、`AnnotationSet`、`AnnotationInfo`、`String`、`Bool`。

被 `AnnotationProcessorContext` 持有；处理器通过它读取注解。

---

## 11. 所有权与并发

- 引用语义对象，但构造后不可变。
- 可跨任务只读共享；无同步需求。
- `annotations()` 返回不可变集合，不需要复制。
- 不持有编译器可变状态；不提供回写声明的方法。
- 相等：没有值相等实现；`==` 是引用身份。

---

## 12. 示例与反例

正确：

```xnull
AnnotationSet annotations = new AnnotationSet([
    new AnnotationInfo(
        "app.Marker",
        AnnotationTarget.Type,
        "app.Device",
        ["name": AnnotationValue.ofString("device")],
        1
    )
])
AnnotationElement device = new AnnotationElement(
    AnnotationTarget.Type,
    "app",
    "Device",
    "app.Device",
    annotations,
    "app/Device.x"
)
Bool marked = device.hasAnnotation("app.Marker")
AnnotationInfo? marker = device.firstAnnotation("app.Marker")
String text = device.describe()
```

反例：在运行时构造元素并假装来自编译器；把字段注解挂到类型元素；`Package` 之外传空 `ownerName`；用元素修改声明；把 `sourceName` 当绝对路径或安全边界；把 `typeName` 当注解类型名。

---

## 13. 测试/场景义务

- 10 种目标的字段投影；
- `Package` 空 owner 与其他目标空 owner 拒绝；
- 注解目标不一致拒绝；
- 空注解集合；
- `hasAnnotation`/`firstAnnotation` 命中/缺失；
- `describe()` 各目标形态；
- `sourceName` 原样读回；
- 不可变/并发只读；
- 处理器不能通过元素修改声明。

---

## 14. XNull 伪代码

```xnull
class AnnotationElement {
    final AnnotationTarget _target
    final String _ownerName
    final String _name
    final String _typeName
    final AnnotationSet _annotations
    final String _sourceName

    AnnotationElement(AnnotationTarget target, String ownerName, String name,
                      String typeName, AnnotationSet annotations, String sourceName) {
        // target 是枚举成员；枚举是值类型，不存在 null。
        if ownerName == null {
            throw "AnnotationElement: null owner name"
        }
        if name == null || name == "" {
            throw "AnnotationElement: empty name"
        }
        if typeName == null || typeName == "" {
            throw "AnnotationElement: empty type name"
        }
        if annotations == null {
            throw "AnnotationElement: null annotations"
        }
        if sourceName == null || sourceName == "" {
            throw "AnnotationElement: empty source name"
        }
        if target != AnnotationTarget.Package && ownerName == "" {
            throw "AnnotationElement: empty owner name"
        }
        if !annotations.isEmpty() {
            AnnotationInfo head = annotations.toList().get(0)
            if head.target() != target {
                throw "AnnotationElement: annotation target mismatch"
            }
        }
        _target = target
        _ownerName = ownerName
        _name = name
        _typeName = typeName
        _annotations = annotations
        _sourceName = sourceName
    }

    AnnotationTarget target() {
        return _target
    }

    String ownerName() {
        return _ownerName
    }

    String name() {
        return _name
    }

    String typeName() {
        return _typeName
    }

    AnnotationSet annotations() {
        return _annotations
    }

    String sourceName() {
        return _sourceName
    }

    Bool hasAnnotation(String typeName) {
        return _annotations.has(typeName)
    }

    AnnotationInfo? firstAnnotation(String typeName) {
        return _annotations.first(typeName)
    }

    String describe() {
        if _target == AnnotationTarget.Package {
            return "package " + _name
        }
        return _ownerName + "#" + _name + ":" + _typeName
    }
}
```
