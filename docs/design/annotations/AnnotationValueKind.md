# `AnnotationValueKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum AnnotationValueKind` |
| 包 | `xdk.annotations` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

注解常量值树的类型标签。每个 `AnnotationValue` 恰好携带一个标签和对应负载，用于编译期求值结果、处理器读取和运行时注册表查询。

不做：不做通用表达式求值，不做运算，不做类型转换，不做 JSON/YAML 值模型，不做运行时反射值。

---

## 2. 设计逻辑

- 标签集合固定为语言允许的注解常量类型：`Bool`、`Int`、`Long`、`Float`、`Double`、`Char`、`String`、`Enum`、`Type`、`Array`、`Annotation`、`Null`。
- `Enum` 用“枚举类型名 + 枚举项名”表示，避免在元数据中保存运行时枚举对象。
- `Type` 用全限定类型名字符串表示，避免类加载和反射。
- `Array` 的元素仍是 `AnnotationValue`，允许嵌套数组和嵌套注解。
- `Annotation` 的负载是 `AnnotationInfo`，形成有限递归值树。
- `Null` 只表示显式的空值；不能让 `null` 同时表示“缺失”和“合法空值”。
- 标签决定哪个访问器有效；不匹配的访问器返回 null，不抛异常。

---

## 3. 表示与不变量

| 序号 | 成员 | 负载 | 工厂 | 访问器 |
| --- | --- | --- | --- | --- |
| 0 | `Bool` | `Bool` | `AnnotationValue.ofBool` | `asBool` |
| 1 | `Int` | `Int` | `AnnotationValue.ofInt` | `asInt` |
| 2 | `Long` | `Long` | `AnnotationValue.ofLong` | `asLong` |
| 3 | `Float` | `Float` | `AnnotationValue.ofFloat` | `asFloat` |
| 4 | `Double` | `Double` | `AnnotationValue.ofDouble` | `asDouble` |
| 5 | `Char` | `Char` | `AnnotationValue.ofChar` | `asChar` |
| 6 | `String` | `String` | `AnnotationValue.ofString` | `asString` |
| 7 | `Enum` | 枚举类型名 + 枚举项名 | `AnnotationValue.ofEnum` | `enumTypeName`/`enumItemName` |
| 8 | `Type` | 全限定类型名 | `AnnotationValue.ofType` | `asTypeName` |
| 9 | `Array` | `List<AnnotationValue>` | `AnnotationValue.ofArray` | `asArray` |
| 10 | `Annotation` | `AnnotationInfo` | `AnnotationValue.ofAnnotation` | `asAnnotation` |
| 11 | `Null` | 无 | `AnnotationValue.nullValue` | `isNull` |

不变量：成员固定为 12 项；序号稳定；值语义；可作 `Map` 键；标签与负载一一对应；不存在“有负载但标签为 Null”的值。

---

## 4. 生命周期

值类型；无 close；无资源；编译期和运行时只读；可跨任务共享。

---

## 5. 构造契约

枚举成员直接使用，无构造器。`AnnotationValue` 的工厂负责检查负载是否与标签匹配。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

`AnnotationValueKind` 没有实例方法。

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| 无 | 枚举只提供成员 | 无 | 无 | 无 |

说明：

- 工厂/访问器映射见 §3；具体契约在 `AnnotationValue`。
- 不为枚举添加 `isNumeric`/`isReference` 等分类方法；分类由调用方按业务需要判断，避免把注解值模型扩大成通用类型系统。

---

## 8. 使用的技术

- 简单枚举；
- 标签联合；
- 稳定序号；
- 常量值树。

---

## 9. 需要的支撑

- 语言：enum、String、List、Map 键；
- 运行时：无；
- 接口：`AnnotationValue`、`AnnotationInfo`。

---

## 10. 依赖的特性/接口/类

无。`AnnotationValue` 依赖本枚举，本枚举不反向依赖 `AnnotationValue`。

---

## 11. 所有权与并发

值语义；可跨任务共享；无同步需求；相等按枚举值。

---

## 12. 示例与反例

正确：

```xnull
AnnotationValue count = AnnotationValue.ofInt(3)
Bool isInt = count.kind() == AnnotationValueKind.Int
```

反例：用 `Int` 标签承载 `Long` 值；用 `Null` 表示“字段未提供”（缺失应由 `values` 中不存在表达）；把 `Type` 存成简单类名；把 `Enum` 存成序号；用 `AnnotationValueKind` 替代完整类型系统。

---

## 13. 测试/场景义务

- 12 个成员逐一存在且序号稳定；
- 每个工厂产生对应标签；
- 每个访问器在标签匹配时返回值、不匹配时返回 null；
- `Enum` 的类型名/项名可读回；
- `Type` 保存全限定名；
- `Array`/`Annotation` 递归值树；
- `Null` 无负载；
- 标签作为 `Map` 键的相等行为。

---

## 14. XNull 伪代码

```xnull
enum AnnotationValueKind {
    Bool,
    Int,
    Long,
    Float,
    Double,
    Char,
    String,
    Enum,
    Type,
    Array,
    Annotation,
    Null,
}
```
