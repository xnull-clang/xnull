# `AnnotationInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class AnnotationInfo` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | `AnnotationTarget`、`AnnotationValue`、`Map`、`List`、`String`、`Int`、`Bool` |

---

## 1. 定位

单个注解使用点的不可变快照：注解类型名、目标种类、目标规范名、参数值映射、重复序号。

不做：不做注解声明、不做目标校验、不做常量求值、不做重复策略判定、不做运行时反射、不做注解继承。

---

## 2. 设计逻辑

- 一个 `AnnotationInfo` 对应源码中的一次 `@Name(args)` 使用，不对应注解类型声明。
- `typeName` 是注解类型的全限定名，例如 `app.Marker`；不使用简单名，避免不同包同名冲突。
- `target` 是注解放置的位置种类；`targetName` 是该位置的编译器规范名，供注册表索引与诊断定位。
- `values` 只包含已绑定参数；未提供的尾部字段不放入映射，不用 `AnnotationValue.nullValue()` 冒充缺失。
- `repeatIndex` 从 1 开始；首次/唯一使用为 1，可重复注解的后续使用依次递增。它不是数组下标。
- 参数只支持位置绑定；`values` 的键是注解字段名，不保留源码参数位置。
- 构造时复制映射；读取时复制映射；值树不可变，因此不需要深拷贝。
- `targetName` 的规范格式由编译器生成；本类只保存，不解析。注册表可寻址目标的格式见 §3。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_typeName` | `String` | 注解类型全限定名，final，非空 |
| `_target` | `AnnotationTarget` | 目标种类，final，非 null |
| `_targetName` | `String` | 目标规范名，final，非空 |
| `_values` | `Map<String, AnnotationValue>` | 参数名到常量的映射；内部副本 |
| `_repeatIndex` | `Int` | 从 1 开始的重复序号，final |

`targetName` 的注册表可寻址格式：

| 目标 | 规范名格式 | 示例 |
| --- | --- | --- |
| `Package` | 包名 | `app.device` |
| `Type` | 类型全限定名 | `app.Device` |
| `Annotation` | 注解类型全限定名 | `app.Marker` |
| `Field` | `owner#field` | `app.Device#name` |
| `Method` | `owner#method(parameterTypes)` | `app.Device#open(app.Text,Int)` |
| `Constructor` | `owner#<init>(parameterTypes)` | `app.Device#<init>(app.Text)` |
| `Deinit` | `owner#deinit()` | `app.Device#deinit()` |
| `Parameter` | `memberTargetName#index` | `app.Device#open(app.Text,Int)#0` |
| `EnumItem` | `enumTypeName#item` | `app.Color#Red` |

`TypeParameter`/`TypeUse` 的规范名由编译器生成；`Deinit` 使用 `owner#deinit()`。 不为这三者提供专用注册表便捷查询；需要时用 `AnnotationRegistry.ofTarget` 传入生成名。

不变量：

- `typeName` 非空；按约定为全限定名。
- `target` 非 null；`targetName` 非空。
- `values` 非 null；键非空、值非 null；键唯一。
- `repeatIndex >= 1`。
- 构造后映射不可变；`values()` 返回副本。
- 值的 `kind` 与注解字段声明类型匹配由编译器保证，本类不做二次类型检查。

---

## 4. 生命周期

由编译器/处理器在构建期构造；构造后不可变；无 close；无资源；可放入 `AnnotationSet`、`AnnotationElement`、`AnnotationRegistry`；可跨任务只读共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `AnnotationInfo(String typeName, AnnotationTarget target, String targetName, Map<String, AnnotationValue> values, Int repeatIndex)` | 全部 | typeName 非空；target 是枚举成员（枚举不可为 null）；targetName 非空；values 非 null、键非空、值非 null；repeatIndex ≥ 1 | 空名/空键/null 值/非法 repeatIndex → panic |

说明：

- 映射在构造时逐项复制；调用方之后修改原映射不影响 `AnnotationInfo`。
- 不做 `@Repeatable` 合法性判断；是否允许重复由编译器在构造 `AnnotationInfo` 之前完成。
- 不校验 `targetName` 是否符合 §3 格式；格式是编译器合同，注册表查询依赖它。
- 不校验参数名是否属于注解类型字段；字段绑定由编译器完成。

---

## 6. 字段表

见 §3；字段私有、`final`。`_values` 保存内部副本，`values()` 返回新的 `Map` 副本。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `typeName` | 注解类型全限定名 | 无 | `String` | 无 |
| `target` | 目标种类 | 无 | `AnnotationTarget` | 无 |
| `targetName` | 目标规范名 | 无 | `String` | 无 |
| `values` | 参数映射快照 | 无 | `Map<String, AnnotationValue>` | 无 |
| `valueOrNull` | 按字段名取参数 | `String name` | `AnnotationValue?` | null/空 name → panic；缺失 → null |
| `hasValue` | 是否有该参数 | `String name` | `Bool` | null/空 name → panic |
| `repeatIndex` | 重复序号 | 无 | `Int` | 无 |
| `describe` | 稳定诊断文本 | 无 | `String` | 无 |

说明：

- `values()` 返回新映射；键顺序不承诺，`describe()` 会排序后输出。
- `valueOrNull` 的“缺失”只表示映射中没有该键；显式 `Null` 注解值返回 `AnnotationValue`，不是 null。
- `hasValue` 与 `valueOrNull(name) != null` 等价，但避免创建临时值。
- `describe()` 输出 `@TypeName(name=Value, other=Value)`；参数名按字典序排列；无参数时只输出 `@TypeName`。
- `describe()` 不包含 `targetName`/`repeatIndex`；诊断定位由 `AnnotationDiagnostic.elementName` 或调用方拼接。
- 本类不提供 `equals`；值比较需要逐字段判断或由后续比较器承担。

---

## 8. 使用的技术

- 不可变对象；
- 防御性复制；
- 全限定名；
- 规范目标名；
- 稳定排序输出；
- 显式缺失语义。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Bool、Map、List；
- 运行时：无；
- 接口：`AnnotationTarget`、`AnnotationValue`、`Map.keys`、`List.sortBy`。

---

## 10. 依赖的特性/接口/类

`AnnotationTarget`、`AnnotationValue`、`Map`、`List`、`String`、`Int`、`Bool`。

与 `AnnotationValue` 形成递归值树对；`AnnotationSet`、`AnnotationRegistry`、`AnnotationElement` 依赖本类。

---

## 11. 所有权与并发

- 引用语义对象，但构造后不可变。
- 可跨任务只读共享；无同步需求。
- `values()` 返回副本；修改副本不影响本对象。
- `valueOrNull`/`hasValue`/`describe` 无副作用，可并发调用。
- 相等：没有值相等实现；`==` 是引用身份。重复项识别使用 `typeName + repeatIndex`，由 `AnnotationSet` 维护。

---

## 12. 示例与反例

正确：

```xnull
AnnotationInfo marker = new AnnotationInfo(
    "app.Marker",
    AnnotationTarget.Type,
    "app.Device",
    [
        "name": AnnotationValue.ofString("device"),
        "priority": AnnotationValue.ofInt(2)
    ],
    1
)
String typeName = marker.typeName()
AnnotationValue? name = marker.valueOrNull("name")
Bool hasName = marker.hasValue("name")
String text = marker.describe()
```

反例：用简单名 `Marker` 作为 `typeName`；用 `null` 表示未提供参数；把 `repeatIndex` 从 0 开始；把 `targetName` 当注解类型名；修改 `values()` 返回值期望影响原对象；把 `describe()` 当可解析的序列化格式。

---

## 13. 测试/场景义务

- `typeName` 全限定名与非空校验；
- `target`/`targetName` 保存与读回；
- `values` 复制、键非空、值非 null；
- `valueOrNull` 命中/缺失/显式 Null 值；
- `hasValue` 与缺失语义；
- `repeatIndex` 1、2、更大值；0 与负数拒绝；
- `describe()` 参数排序、空参数、嵌套值；
- 不同 target 的 `targetName` 格式；
- 并发只读。

---

## 14. XNull 伪代码

```xnull
class AnnotationInfo {
    final String _typeName
    final AnnotationTarget _target
    final String _targetName
    final Map<String, AnnotationValue> _values
    final Int _repeatIndex

    AnnotationInfo(String typeName, AnnotationTarget target, String targetName,
                   Map<String, AnnotationValue> values, Int repeatIndex) {
        if typeName == null || typeName == "" {
            throw "AnnotationInfo: empty type name"
        }
        // target 是枚举成员；枚举是值类型，不存在 null。
        if targetName == null || targetName == "" {
            throw "AnnotationInfo: empty target name"
        }
        if values == null {
            throw "AnnotationInfo: null values"
        }
        if repeatIndex < 1 {
            throw "AnnotationInfo: invalid repeat index"
        }
        _typeName = typeName
        _target = target
        _targetName = targetName
        _repeatIndex = repeatIndex
        _values = [:]
        List<String> names = values.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            if name == null || name == "" {
                throw "AnnotationInfo: empty value name"
            }
            AnnotationValue value = values.get(name)
            if value == null {
                throw "AnnotationInfo: null value"
            }
            _values.put(name, value)
            index = index + 1
        }
    }

    String typeName() {
        return _typeName
    }

    AnnotationTarget target() {
        return _target
    }

    String targetName() {
        return _targetName
    }

    Map<String, AnnotationValue> values() {
        Map<String, AnnotationValue> result = [:]
        List<String> names = _values.keys()
        Int index = 0
        while index < names.length() {
            String name = names.get(index)
            result.put(name, _values.get(name))
            index = index + 1
        }
        return result
    }

    AnnotationValue? valueOrNull(String name) {
        if name == null || name == "" {
            throw "AnnotationInfo.valueOrNull: empty name"
        }
        if !_values.has(name) {
            return null
        }
        return _values.get(name)
    }

    Bool hasValue(String name) {
        if name == null || name == "" {
            throw "AnnotationInfo.hasValue: empty name"
        }
        return _values.has(name)
    }

    Int repeatIndex() {
        return _repeatIndex
    }

    String describe() {
        List<String> names = _values.keys()
        names.sortBy((String left, String right) -> left < right)
        String result = "@" + _typeName
        if names.length() == 0 {
            return result
        }
        result = result + "("
        Int index = 0
        while index < names.length() {
            if index > 0 {
                result = result + ","
            }
            String name = names.get(index)
            result = result + name + "=" + _values.get(name).describe()
            index = index + 1
        }
        return result + ")"
    }
}
```
