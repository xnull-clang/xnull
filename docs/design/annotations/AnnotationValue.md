# `AnnotationValue`

| 项 | 值 |
| --- | --- |
| 类型 | `class AnnotationValue` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | `AnnotationValueKind`、`AnnotationInfo`、`List`、`String`、`Bool`、`Int`、`Long`、`Float`、`Double`、`Char` |

---

## 1. 定位

不可变注解常量值树节点：标签 + 对应负载。用于编译器常量求值结果、处理器读取注解参数、运行时注册表查询。

不做：不做表达式求值、不做类型转换、不做运算、不做 JSON/YAML 值、不做运行时反射值、不做可变容器。

---

## 2. 设计逻辑

- 单一 `class` + `AnnotationValueKind` 标签，避免为 12 种值建立继承层级；XNull 类没有动态覆盖，标签分派更直接。
- 每种 `kind` 只使用自己的负载字段；其他负载字段为 null。访问器不匹配时返回 null，不抛异常。
- `Type` 只保存全限定类型名字符串；不加载类，不保存 `Class` 对象。
- `Enum` 保存枚举类型全限定名与枚举项名；不保存运行时枚举对象。
- `Array` 保存 `List<AnnotationValue>`；构造时复制，读取时再复制，保证不可变。
- `Annotation` 保存不可变 `AnnotationInfo`；允许有限递归，不允许无限自引用。
- `Null` 表示显式空值；字段缺失用 `AnnotationInfo.values()` 中不存在表达，不用 `null` 混淆。
- 工厂是唯一构造入口；私有构造器只接受工厂已经检查过的负载。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_kind` | `AnnotationValueKind` | 标签，final，非 null |
| `_boolValue` | `Bool?` | `Bool` 负载 |
| `_intValue` | `Int?` | `Int` 负载 |
| `_longValue` | `Long?` | `Long` 负载 |
| `_floatValue` | `Float?` | `Float` 负载 |
| `_doubleValue` | `Double?` | `Double` 负载 |
| `_charValue` | `Char?` | `Char` 负载 |
| `_stringValue` | `String?` | `String` 负载 |
| `_enumTypeName` | `String?` | 枚举类型全限定名 |
| `_enumItemName` | `String?` | 枚举项名 |
| `_typeName` | `String?` | `Type` 的全限定名 |
| `_arrayValue` | `List<AnnotationValue>?` | 数组负载；内部副本 |
| `_annotationValue` | `AnnotationInfo?` | 嵌套注解负载 |

不变量：

- `_kind` 与负载严格对应；`Null` 没有任何负载。
- `Enum` 同时有非空 `_enumTypeName` 与非空 `_enumItemName`。
- `Type` 的 `_typeName` 是非空全限定名。
- `Array` 的列表与元素均非 null；构造后列表不再被外部修改。
- `Annotation` 的嵌套 `AnnotationInfo` 非 null 且不可变。
- 对象构造后不可变；`asArray()` 返回副本。
- 不存在“字段缺失”的 `AnnotationValue`；缺失由外层映射表达。

---

## 4. 生命周期

构造后不可变；无 close；无资源；GC 管理；可跨任务只读共享；嵌套注解与数组在构造时形成稳定的值树。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| 私有构造器 | 标签 + 12 个负载槽 | 由工厂独占调用；标签非 null；数组负载元素非 null | 内部不变量破坏 → panic |
| `ofBool` | `Bool value` | 任意 Bool | 无 |
| `ofInt` | `Int value` | 任意 Int | 无 |
| `ofLong` | `Long value` | 任意 Long | 无 |
| `ofFloat` | `Float value` | 任意 Float | 无 |
| `ofDouble` | `Double value` | 任意 Double | 无 |
| `ofChar` | `Char value` | 任意 Char | 无 |
| `ofString` | `String value` | 非 null | null → panic |
| `ofEnum` | `String enumTypeName, String enumItemName` | 两者非空全名 | null/空 → panic |
| `ofType` | `String typeName` | 非空全限定名 | null/空 → panic |
| `ofArray` | `List<AnnotationValue> values` | 非 null；元素非 null | null/含 null → panic |
| `ofAnnotation` | `AnnotationInfo annotation` | 非 null | null → panic |
| `nullValue` | 无 | 无 | 无 |

说明：

- 工厂是唯一公开构造入口；私有构造器不对外暴露。
- `ofArray` 复制输入列表；调用方之后修改原列表不影响值。
- `ofString` 允许空字符串；空字符串是合法注解常量，不是“缺失”。
- `ofType` 不检查包是否存在；类型解析是编译器职责。

---

## 6. 字段表

见 §3；字段全部私有、`final`。数组字段保存内部副本，嵌套注解字段引用不可变 `AnnotationInfo`。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `ofBool` | 构造 Bool 值 | `Bool value` | `AnnotationValue` | 无 |
| `ofInt` | 构造 Int 值 | `Int value` | `AnnotationValue` | 无 |
| `ofLong` | 构造 Long 值 | `Long value` | `AnnotationValue` | 无 |
| `ofFloat` | 构造 Float 值 | `Float value` | `AnnotationValue` | 无 |
| `ofDouble` | 构造 Double 值 | `Double value` | `AnnotationValue` | 无 |
| `ofChar` | 构造 Char 值 | `Char value` | `AnnotationValue` | 无 |
| `ofString` | 构造 String 值 | `String value` | `AnnotationValue` | null → panic |
| `ofEnum` | 构造枚举值 | `String enumTypeName, String enumItemName` | `AnnotationValue` | null/空 → panic |
| `ofType` | 构造类型引用值 | `String typeName` | `AnnotationValue` | null/空 → panic |
| `ofArray` | 构造数组值 | `List<AnnotationValue> values` | `AnnotationValue` | null/含 null → panic |
| `ofAnnotation` | 构造嵌套注解值 | `AnnotationInfo annotation` | `AnnotationValue` | null → panic |
| `nullValue` | 构造显式空值 | 无 | `AnnotationValue` | 无 |
| `kind` | 读取标签 | 无 | `AnnotationValueKind` | 无 |
| `isNull` | 是否显式空值 | 无 | `Bool` | 无 |
| `asBool` | 读取 Bool 负载 | 无 | `Bool?` | 不匹配 → null |
| `asInt` | 读取 Int 负载 | 无 | `Int?` | 不匹配 → null |
| `asLong` | 读取 Long 负载 | 无 | `Long?` | 不匹配 → null |
| `asFloat` | 读取 Float 负载 | 无 | `Float?` | 不匹配 → null |
| `asDouble` | 读取 Double 负载 | 无 | `Double?` | 不匹配 → null |
| `asChar` | 读取 Char 负载 | 无 | `Char?` | 不匹配 → null |
| `asString` | 读取 String 负载 | 无 | `String?` | 不匹配 → null |
| `enumTypeName` | 读取枚举类型名 | 无 | `String?` | 不匹配 → null |
| `enumItemName` | 读取枚举项名 | 无 | `String?` | 不匹配 → null |
| `asTypeName` | 读取类型全限定名 | 无 | `String?` | 不匹配 → null |
| `asArray` | 读取数组快照 | 无 | `List<AnnotationValue>?` | 不匹配 → null |
| `asAnnotation` | 读取嵌套注解 | 无 | `AnnotationInfo?` | 不匹配 → null |
| `describe` | 稳定诊断文本 | 无 | `String` | 无 |

说明：

- 访问器不做隐式转换：`Int` 值不能通过 `asLong` 读取，`Type` 值不能通过 `asString` 读取。
- `asArray()` 每次返回新列表；修改返回值不影响值树。
- `describe()` 只用于诊断/文档，不是序列化格式；字符串不做转义承诺。
- `describe()` 对 `Array` 输出 `Array[` 加逗号分隔元素再加 `]`；对嵌套注解输出 `Annotation(` + 嵌套注解文本 + `)`；对 `Null` 输出 `Null`。
- 本类不提供 `equals`；值树比较需要调用方按 `kind` 与负载逐项判断，或由后续版本引入专用比较器。

---

## 8. 使用的技术

- 标签联合；
- 工厂方法；
- 不可变对象；
- 防御性复制；
- 递归值树；
- 空值显式建模。

---

## 9. 需要的支撑

- 语言：class、final 字段、Bool、Int、Long、Float、Double、Char、String、List、Map（间接）、可空类型；
- 运行时：无；
- 接口：`AnnotationValueKind`、`AnnotationInfo`、`AnnotationInfo.describe`。

---

## 10. 依赖的特性/接口/类

`AnnotationValueKind`、`AnnotationInfo`、`List`、`String`、`Bool`、`Int`、`Long`、`Float`、`Double`、`Char`。

`AnnotationValue` 与 `AnnotationInfo` 是刻意互相引用的值树对：`AnnotationInfo` 的 `values` 含 `AnnotationValue`，`AnnotationValue` 的 `Annotation` 负载含 `AnnotationInfo`。两者必须一起冻结。

---

## 11. 所有权与并发

- 引用语义对象，但构造后不可变。
- 可跨任务只读共享；无同步需求。
- `ofArray` 复制输入，`asArray` 复制输出；嵌套 `AnnotationInfo` 不可变，因此无需深拷贝。
- `describe` 不修改状态；可并发调用。
- 相等：没有值相等实现；`==` 是引用身份。不要把本类当 `Map` 键做值比较。

---

## 12. 示例与反例

正确：

```xnull
AnnotationValue message = AnnotationValue.ofString("hello")
AnnotationValue limit = AnnotationValue.ofLong(9000000000)
AnnotationValue mode = AnnotationValue.ofEnum("app.Mode", "Fast")
AnnotationValue type = AnnotationValue.ofType("app.Device")
AnnotationValue sizes = AnnotationValue.ofArray([
    AnnotationValue.ofInt(1),
    AnnotationValue.ofInt(2)
])
AnnotationValue nested = AnnotationValue.ofAnnotation(new AnnotationInfo(
    "app.Meta",
    AnnotationTarget.Type,
    "app.Device",
    ["owner": AnnotationValue.ofString("team")],
    1
))
```

反例：用 `ofInt` 存 `Long`；把 `Type` 存成 `"Device"` 而非全限定名；不检查 `kind` 就调用 `asString`；修改 `asArray()` 返回值期望改变值树；用 `null` 表示缺失；构造无限嵌套注解；把 `describe()` 当稳定序列化格式。

---

## 13. 测试/场景义务

- 12 种 `kind` 的工厂与访问器逐项覆盖；
- 不匹配访问器返回 null；
- `Int`/`Long`/`Float`/`Double` 边界值；
- `String` 空串与普通串；
- `Char` 特殊字符；
- `Enum` 类型名/项名；
- `Type` 全限定名；
- `Array` 空数组、嵌套数组、元素 null、输入/输出副本独立性；
- `Annotation` 嵌套与递归深度限制；
- `Null` 无负载；
- `describe()` 稳定性；
- 并发只读共享。

---

## 14. XNull 伪代码

```xnull
class AnnotationValue {
    final AnnotationValueKind _kind
    final Bool? _boolValue
    final Int? _intValue
    final Long? _longValue
    final Float? _floatValue
    final Double? _doubleValue
    final Char? _charValue
    final String? _stringValue
    final String? _enumTypeName
    final String? _enumItemName
    final String? _typeName
    final List<AnnotationValue>? _arrayValue
    final AnnotationInfo? _annotationValue

    private AnnotationValue(AnnotationValueKind kind, Bool? boolValue, Int? intValue,
                            Long? longValue, Float? floatValue, Double? doubleValue,
                            Char? charValue, String? stringValue, String? enumTypeName,
                            String? enumItemName, String? typeName,
                            List<AnnotationValue>? arrayValue,
                            AnnotationInfo? annotationValue) {
        if kind == null {
            throw "AnnotationValue: null kind"
        }
        _kind = kind
        _boolValue = boolValue
        _intValue = intValue
        _longValue = longValue
        _floatValue = floatValue
        _doubleValue = doubleValue
        _charValue = charValue
        _stringValue = stringValue
        _enumTypeName = enumTypeName
        _enumItemName = enumItemName
        _typeName = typeName
        if arrayValue == null {
            _arrayValue = null
        } else {
            _arrayValue = []
            Int index = 0
            while index < arrayValue.length() {
                AnnotationValue item = arrayValue.get(index)
                if item == null {
                    throw "AnnotationValue: null array item"
                }
                _arrayValue.push(item)
                index = index + 1
            }
        }
        _annotationValue = annotationValue
    }

    static AnnotationValue ofBool(Bool value) {
        return new AnnotationValue(
            AnnotationValueKind.Bool,
            value, null, null, null, null, null, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofInt(Int value) {
        return new AnnotationValue(
            AnnotationValueKind.Int,
            null, value, null, null, null, null, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofLong(Long value) {
        return new AnnotationValue(
            AnnotationValueKind.Long,
            null, null, value, null, null, null, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofFloat(Float value) {
        return new AnnotationValue(
            AnnotationValueKind.Float,
            null, null, null, value, null, null, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofDouble(Double value) {
        return new AnnotationValue(
            AnnotationValueKind.Double,
            null, null, null, null, value, null, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofChar(Char value) {
        return new AnnotationValue(
            AnnotationValueKind.Char,
            null, null, null, null, null, value, null, null, null, null, null, null
        )
    }

    static AnnotationValue ofString(String value) {
        if value == null {
            throw "AnnotationValue.ofString: null value"
        }
        return new AnnotationValue(
            AnnotationValueKind.String,
            null, null, null, null, null, null, value, null, null, null, null, null
        )
    }

    static AnnotationValue ofEnum(String enumTypeName, String enumItemName) {
        if enumTypeName == null || enumTypeName == "" {
            throw "AnnotationValue.ofEnum: empty enum type name"
        }
        if enumItemName == null || enumItemName == "" {
            throw "AnnotationValue.ofEnum: empty enum item name"
        }
        return new AnnotationValue(
            AnnotationValueKind.Enum,
            null, null, null, null, null, null, null,
            enumTypeName, enumItemName, null, null, null
        )
    }

    static AnnotationValue ofType(String typeName) {
        if typeName == null || typeName == "" {
            throw "AnnotationValue.ofType: empty type name"
        }
        return new AnnotationValue(
            AnnotationValueKind.Type,
            null, null, null, null, null, null, null,
            null, null, typeName, null, null
        )
    }

    static AnnotationValue ofArray(List<AnnotationValue> values) {
        if values == null {
            throw "AnnotationValue.ofArray: null values"
        }
        return new AnnotationValue(
            AnnotationValueKind.Array,
            null, null, null, null, null, null, null,
            null, null, null, values, null
        )
    }

    static AnnotationValue ofAnnotation(AnnotationInfo annotation) {
        if annotation == null {
            throw "AnnotationValue.ofAnnotation: null annotation"
        }
        return new AnnotationValue(
            AnnotationValueKind.Annotation,
            null, null, null, null, null, null, null,
            null, null, null, null, annotation
        )
    }

    static AnnotationValue nullValue() {
        return new AnnotationValue(
            AnnotationValueKind.Null,
            null, null, null, null, null, null, null,
            null, null, null, null, null
        )
    }

    AnnotationValueKind kind() {
        return _kind
    }

    Bool isNull() {
        return _kind == AnnotationValueKind.Null
    }

    Bool? asBool() {
        return _boolValue
    }

    Int? asInt() {
        return _intValue
    }

    Long? asLong() {
        return _longValue
    }

    Float? asFloat() {
        return _floatValue
    }

    Double? asDouble() {
        return _doubleValue
    }

    Char? asChar() {
        return _charValue
    }

    String? asString() {
        return _stringValue
    }

    String? enumTypeName() {
        return _enumTypeName
    }

    String? enumItemName() {
        return _enumItemName
    }

    String? asTypeName() {
        return _typeName
    }

    List<AnnotationValue>? asArray() {
        if _arrayValue == null {
            return null
        }
        return _arrayValue.copy()
    }

    AnnotationInfo? asAnnotation() {
        return _annotationValue
    }

    String describe() {
        if _kind == AnnotationValueKind.Bool {
            return "Bool(" + _boolValue + ")"
        }
        if _kind == AnnotationValueKind.Int {
            return "Int(" + _intValue + ")"
        }
        if _kind == AnnotationValueKind.Long {
            return "Long(" + _longValue + ")"
        }
        if _kind == AnnotationValueKind.Float {
            return "Float(" + _floatValue + ")"
        }
        if _kind == AnnotationValueKind.Double {
            return "Double(" + _doubleValue + ")"
        }
        if _kind == AnnotationValueKind.Char {
            return "Char(" + _charValue + ")"
        }
        if _kind == AnnotationValueKind.String {
            return "String(\"" + _stringValue + "\")"
        }
        if _kind == AnnotationValueKind.Enum {
            return "Enum(" + _enumTypeName + "." + _enumItemName + ")"
        }
        if _kind == AnnotationValueKind.Type {
            return "Type(" + _typeName + ")"
        }
        if _kind == AnnotationValueKind.Array {
            String result = "Array["
            Int index = 0
            while index < _arrayValue.length() {
                if index > 0 {
                    result = result + ","
                }
                result = result + _arrayValue.get(index).describe()
                index = index + 1
            }
            return result + "]"
        }
        if _kind == AnnotationValueKind.Annotation {
            return "Annotation(" + _annotationValue.describe() + ")"
        }
        return "Null"
    }
}
```
