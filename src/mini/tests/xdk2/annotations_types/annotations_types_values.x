// B2.1 场景：14 类型中的值树、目标/保留/值标签枚举、注解信息与集合。
import annotations.Annotations

static Map<String, AnnotationValue> markerValues(String name, Int priority) {
    Map<String, AnnotationValue> values = [:]
    values.put("name", AnnotationValue.ofString(name))
    values.put("priority", AnnotationValue.ofInt(priority))
    return values
}

static Map<String, AnnotationValue> emptyValues() {
    Map<String, AnnotationValue> values = [:]
    return values
}

static AnnotationInfo marker(String name, Int repeatIndex) {
    return new AnnotationInfo(
        "app.Marker",
        AnnotationTarget.Type,
        "app.Device",
        markerValues(name, repeatIndex),
        repeatIndex
    )
}

static String valueName(AnnotationInfo info) {
    AnnotationValue? value = info.valueOrNull("name")
    if value == null {
        return "missing"
    }
    AnnotationValue actual = value as AnnotationValue
    return actual.asString() as String
}

static Int main() {
    // 目标枚举：11 个成员全部可比较。
    print(AnnotationTarget.Package == AnnotationTarget.Package)
    print(AnnotationTarget.Type == AnnotationTarget.Type)
    print(AnnotationTarget.Annotation == AnnotationTarget.Annotation)
    print(AnnotationTarget.TypeParameter == AnnotationTarget.TypeParameter)
    print(AnnotationTarget.Field == AnnotationTarget.Field)
    print(AnnotationTarget.Method == AnnotationTarget.Method)
    print(AnnotationTarget.Constructor == AnnotationTarget.Constructor)
    print(AnnotationTarget.Deinit == AnnotationTarget.Deinit)
    print(AnnotationTarget.Parameter == AnnotationTarget.Parameter)
    print(AnnotationTarget.TypeUse == AnnotationTarget.TypeUse)
    print(AnnotationTarget.EnumItem == AnnotationTarget.EnumItem)
    print(AnnotationTarget.Type != AnnotationTarget.TypeUse)

    // 保留枚举：3 个成员。
    print(AnnotationRetention.Source == AnnotationRetention.Source)
    print(AnnotationRetention.Binary == AnnotationRetention.Binary)
    print(AnnotationRetention.Runtime == AnnotationRetention.Runtime)
    print(AnnotationRetention.Binary != AnnotationRetention.Runtime)

    // 值标签枚举：12 个成员。
    print(AnnotationValueKind.Bool == AnnotationValueKind.Bool)
    print(AnnotationValueKind.Int == AnnotationValueKind.Int)
    print(AnnotationValueKind.Long == AnnotationValueKind.Long)
    print(AnnotationValueKind.Float == AnnotationValueKind.Float)
    print(AnnotationValueKind.Double == AnnotationValueKind.Double)
    print(AnnotationValueKind.Char == AnnotationValueKind.Char)
    print(AnnotationValueKind.String == AnnotationValueKind.String)
    print(AnnotationValueKind.Enum == AnnotationValueKind.Enum)
    print(AnnotationValueKind.Type == AnnotationValueKind.Type)
    print(AnnotationValueKind.Array == AnnotationValueKind.Array)
    print(AnnotationValueKind.Annotation == AnnotationValueKind.Annotation)
    print(AnnotationValueKind.Null == AnnotationValueKind.Null)

    // 标量工厂与访问器。
    AnnotationValue boolValue = AnnotationValue.ofBool(true)
    print(boolValue.kind() == AnnotationValueKind.Bool)
    print(boolValue.asBool())
    print(boolValue.asInt() == null)
    print(boolValue.describe())

    AnnotationValue intValue = AnnotationValue.ofInt(42)
    print(intValue.kind() == AnnotationValueKind.Int)
    print(intValue.asInt())
    print(intValue.asString() == null)
    print(intValue.describe())

    AnnotationValue longValue = AnnotationValue.ofLong(9000000000)
    print(longValue.kind() == AnnotationValueKind.Long)
    print(longValue.asLong())
    print(longValue.asInt() == null)
    print(longValue.describe())

    AnnotationValue floatValue = AnnotationValue.ofFloat(1.5)
    print(floatValue.kind() == AnnotationValueKind.Float)
    print(floatValue.asFloat())
    print(floatValue.asDouble() == null)
    print(floatValue.describe())

    AnnotationValue doubleValue = AnnotationValue.ofDouble(2.25)
    print(doubleValue.kind() == AnnotationValueKind.Double)
    print(doubleValue.asDouble())
    print(doubleValue.asFloat() == null)
    print(doubleValue.describe())

    AnnotationValue charValue = AnnotationValue.ofChar('Q')
    print(charValue.kind() == AnnotationValueKind.Char)
    print(charValue.asChar())
    print(charValue.asString() == null)
    print(charValue.describe())

    AnnotationValue emptyString = AnnotationValue.ofString("")
    AnnotationValue textValue = AnnotationValue.ofString("hello")
    print(emptyString.kind() == AnnotationValueKind.String)
    String emptyText = emptyString.asString() as String
    print(emptyText.length())
    print(textValue.asString())
    print(textValue.asInt() == null)
    print(textValue.describe())

    AnnotationValue enumValue = AnnotationValue.ofEnum("app.Mode", "Fast")
    print(enumValue.kind() == AnnotationValueKind.Enum)
    print(enumValue.enumTypeName())
    print(enumValue.enumItemName())
    print(enumValue.asString() == null)
    print(enumValue.describe())

    AnnotationValue typeValue = AnnotationValue.ofType("app.Device")
    print(typeValue.kind() == AnnotationValueKind.Type)
    print(typeValue.asTypeName())
    print(typeValue.asString() == null)
    print(typeValue.describe())

    AnnotationValue nullValue = AnnotationValue.nullValue()
    print(nullValue.kind() == AnnotationValueKind.Null)
    print(nullValue.isNull())
    print(nullValue.asString() == null)
    print(nullValue.describe())

    // 数组：空数组、嵌套、输入/输出副本独立。
    List<AnnotationValue> emptyItems = []
    AnnotationValue emptyArray = AnnotationValue.ofArray(emptyItems)
    print(emptyArray.kind() == AnnotationValueKind.Array)
    List<AnnotationValue> emptyReadBack = emptyArray.asArray() as List<AnnotationValue>
    print(emptyReadBack.length())
    print(emptyArray.describe())

    List<AnnotationValue> items = []
    items.push(AnnotationValue.ofInt(1))
    items.push(AnnotationValue.ofInt(2))
    AnnotationValue arrayValue = AnnotationValue.ofArray(items)
    print(items.length())
    items.push(AnnotationValue.ofInt(3))
    List<AnnotationValue> afterInputMutation = arrayValue.asArray() as List<AnnotationValue>
    print(afterInputMutation.length())
    List<AnnotationValue> readBack = arrayValue.asArray() as List<AnnotationValue>
    readBack.push(AnnotationValue.ofInt(4))
    List<AnnotationValue> afterOutputMutation = arrayValue.asArray() as List<AnnotationValue>
    print(afterOutputMutation.length())
    print(arrayValue.describe())

    List<AnnotationValue> nestedItems = []
    nestedItems.push(AnnotationValue.ofInt(7))
    List<AnnotationValue> outerItems = []
    outerItems.push(AnnotationValue.ofString("x"))
    outerItems.push(AnnotationValue.ofArray(nestedItems))
    AnnotationValue nestedArray = AnnotationValue.ofArray(outerItems)
    print(nestedArray.describe())

    // 嵌套注解值。
    Map<String, AnnotationValue> metaValues = [:]
    metaValues.put("owner", AnnotationValue.ofString("team"))
    AnnotationInfo meta = new AnnotationInfo(
        "app.Meta",
        AnnotationTarget.Annotation,
        "app.Meta",
        metaValues,
        1
    )
    AnnotationValue annotationValue = AnnotationValue.ofAnnotation(meta)
    print(annotationValue.kind() == AnnotationValueKind.Annotation)
    print(annotationValue.asAnnotation() != null)
    print(annotationValue.describe())

    // AnnotationInfo：字段读回、值快照、缺失与显式 Null、describe 排序。
    AnnotationInfo primary = marker("device", 1)
    print(primary.typeName())
    print(primary.target() == AnnotationTarget.Type)
    print(primary.targetName())
    print(primary.repeatIndex())
    print(primary.hasValue("name"))
    print(primary.hasValue("missing"))
    print(primary.valueOrNull("missing") == null)
    print(valueName(primary))

    Map<String, AnnotationValue> copied = primary.values()
    copied.put("name", AnnotationValue.ofString("changed"))
    print(valueName(primary))

    AnnotationInfo noParams = new AnnotationInfo(
        "app.Empty",
        AnnotationTarget.Type,
        "app.Device",
        emptyValues(),
        1
    )
    print(noParams.describe())
    print(noParams.repeatIndex())

    Map<String, AnnotationValue> nullValues = [:]
    nullValues.put("optional", AnnotationValue.nullValue())
    AnnotationInfo explicitNull = new AnnotationInfo(
        "app.Optional",
        AnnotationTarget.Type,
        "app.Device",
        nullValues,
        1
    )
    print(explicitNull.hasValue("optional"))
    AnnotationValue? optional = explicitNull.valueOrNull("optional")
    print(optional != null)
    AnnotationValue optionalValue = optional as AnnotationValue
    print(optionalValue.isNull())

    Map<String, AnnotationValue> orderedValues = [:]
    orderedValues.put("zeta", AnnotationValue.ofInt(1))
    orderedValues.put("alpha", AnnotationValue.ofInt(2))
    orderedValues.put("middle", AnnotationValue.ofInt(3))
    AnnotationInfo ordered = new AnnotationInfo(
        "app.Ordered",
        AnnotationTarget.Type,
        "app.Device",
        orderedValues,
        1
    )
    print(ordered.describe())

    // AnnotationSet：空集合、顺序、可重复项、查询与合并。
    AnnotationSet emptySet = AnnotationSet.empty()
    print(emptySet.length())
    print(emptySet.isEmpty())
    print(emptySet.first("app.Marker") == null)
    print(emptySet.all("app.Marker").length())
    print(emptySet.has("app.Marker"))
    print(emptySet.describe() == "")

    AnnotationInfo secondMarker = marker("device-2", 2)
    List<AnnotationInfo> setItems = []
    setItems.push(primary)
    setItems.push(secondMarker)
    AnnotationSet set = new AnnotationSet(setItems)
    print(set.length())
    print(set.isEmpty())
    print(valueName(set.first("app.Marker") as AnnotationInfo))
    print(set.all("app.Marker").length())
    print(set.all("app.Marker").get(1).repeatIndex())
    print(set.has("app.Marker"))
    print(set.has("app.Other"))
    print(set.describe())

    setItems.push(marker("device-3", 3))
    print(set.length())

    AnnotationSet subset = set.byTypeName("app.Marker")
    print(subset.length())
    print(subset.all("app.Other").length())

    AnnotationInfo thirdMarker = marker("device-3", 3)
    List<AnnotationInfo> otherItems = []
    otherItems.push(marker("conflict", 2))
    otherItems.push(thirdMarker)
    AnnotationSet other = new AnnotationSet(otherItems)
    AnnotationSet merged = set.merge(other)
    print(merged.length())
    print(valueName(merged.first("app.Marker") as AnnotationInfo))
    print(merged.all("app.Marker").get(2).repeatIndex())

    AnnotationSet mergedEmpty = set.merge(AnnotationSet.empty())
    print(mergedEmpty.length())
    return 0
}
