// B2.3 场景：编译器为 Runtime 注解生成静态 AnnotationRegistry，
// 覆盖版本、目标索引、排序、重复项保序与 Source/Binary 过滤。
import xdk.annotations

@Retention(Runtime)
@Repeatable
@annotation Meta {
    final String name = ""
    final Int level = 0
    final Bool enabled = true
    final Float ratio = 1.0
    final Long big = 0
    final String[] tags = []
    final Nested nested = @Nested("default-nested")
}

@Retention(Source)
@annotation SourceTag {
    final String name = ""
}

@Retention(Binary)
@annotation BinaryTag {
    final String name = ""
}

@annotation DefaultTag {
    final String name = ""
}

@annotation Nested {
    final String label = ""
}

@Meta("package-meta", 1)
@SourceTag("package-source")
package app

@Meta("device", 2, true, 2.5, 9000000000, ["core"], @Nested("nested-device"))
@Meta("device-2", 13)
@BinaryTag("device-binary")
@DefaultTag("device-default")
class Device {
    @Meta("name-field", 3)
    String name

    @Meta("open-method", 4)
    Void open(@Meta("text-param", 5) String text, @SourceTag("ignored-param") Int count) {
    }

    @Meta("constructor", 6)
    Device(@Meta("constructor-param", 7) String initial) {
        self.name = initial
    }
}

@Meta("box", 8)
class Box<@Meta("type-param", 9) T> {
}

@Meta("color-enum", 10)
enum Color {
    @Meta("red", 11)
    Red,
    Blue,
}

@Meta("marker-meta", 12)
@annotation Marker {
    final String value = ""
}

static AnnotationValue valueOf(AnnotationInfo info, String name) {
    AnnotationValue? value = info.valueOrNull(name)
    if value == null {
        return AnnotationValue.nullValue()
    }
    return value as AnnotationValue
}

static String stringOf(AnnotationInfo info, String name) {
    String? value = valueOf(info, name).asString()
    if value == null {
        return "missing"
    }
    return value as String
}

static Int intOf(AnnotationInfo info, String name) {
    Int? value = valueOf(info, name).asInt()
    if value == null {
        return -1
    }
    return value as Int
}

static Long longOf(AnnotationInfo info, String name) {
    Long? value = valueOf(info, name).asLong()
    if value == null {
        return -1
    }
    return value as Long
}

static Bool boolOf(AnnotationInfo info, String name) {
    Bool? value = valueOf(info, name).asBool()
    if value == null {
        return false
    }
    return value as Bool
}

static Float floatOf(AnnotationInfo info, String name) {
    Float? value = valueOf(info, name).asFloat()
    if value == null {
        return -1.0
    }
    return value as Float
}

static Int arrayLengthOf(AnnotationInfo info, String name) {
    AnnotationValue value = valueOf(info, name)
    if value.kind() != AnnotationValueKind.Array {
        return -1
    }
    List<AnnotationValue> items = value.asArray() as List<AnnotationValue>
    return items.length()
}

static String nestedLabelOf(AnnotationInfo info, String name) {
    AnnotationInfo? value = valueOf(info, name).asAnnotation()
    if value == null {
        return "missing"
    }
    return stringOf(value as AnnotationInfo, "label")
}

static AnnotationInfo? firstMeta(AnnotationSet set) {
    return set.first("app.Meta")
}

static Int main() {
    print(xdkAnnotationRegistryVersion())
    AnnotationRegistry registry = xdkAnnotationRegistry()

    // 类型目标：Runtime 项存在，Source/Binary/默认 Binary 被过滤；重复项保序。
    AnnotationSet device = registry.ofType("app.Device")
    print(device.length())
    print(device.has("app.Meta"))
    print(device.has("app.SourceTag"))
    print(device.has("app.BinaryTag"))
    print(device.has("app.DefaultTag"))
    print(device.all("app.Meta").get(0).repeatIndex())
    print(device.all("app.Meta").get(1).repeatIndex())

    AnnotationInfo? firstValue = firstMeta(device)
    AnnotationInfo first = firstValue as AnnotationInfo
    print(stringOf(first, "name"))
    print(intOf(first, "level"))
    print(boolOf(first, "enabled"))
    print(floatOf(first, "ratio"))
    print(longOf(first, "big"))
    print(valueOf(first, "ratio").kind() == AnnotationValueKind.Float)
    print(valueOf(first, "ratio").describe())
    print(arrayLengthOf(first, "tags"))
    print(nestedLabelOf(first, "nested"))

    AnnotationInfo? secondValue = device.all("app.Meta").get(1)
    AnnotationInfo second = secondValue as AnnotationInfo
    print(stringOf(second, "name"))
    print(boolOf(second, "enabled"))
    print(arrayLengthOf(second, "tags"))
    print(nestedLabelOf(second, "nested"))

    // 字段/方法/构造器/参数目标索引。
    print(registry.ofField("app.Device", "name").length())
    print(stringOf(registry.ofField("app.Device", "name").first("app.Meta") as AnnotationInfo, "name"))

    List<String> openParams = []
    openParams.push("String")
    openParams.push("Int")
    print(registry.ofMethod("app.Device", "open", openParams).has("app.Meta"))
    print(registry.ofParameter("app.Device#open(String,Int)", 0).has("app.Meta"))
    print(registry.ofParameter("app.Device#open(String,Int)", 1).isEmpty())

    List<String> ctorParams = []
    ctorParams.push("String")
    print(registry.ofConstructor("app.Device", ctorParams).has("app.Meta"))
    print(registry.ofParameter("app.Device#<init>(String)", 0).has("app.Meta"))

    // 包、枚举项、类型参数、注解目标。
    print(registry.ofPackage("app").has("app.Meta"))
    print(registry.ofPackage("app").has("app.SourceTag"))
    print(registry.ofEnumItem("app.Color", "Red").has("app.Meta"))
    print(registry.ofEnumItem("app.Color", "Blue").isEmpty())
    print(registry.ofTarget(AnnotationTarget.TypeParameter, "app.Box#T").has("app.Meta"))
    print(registry.ofTarget(AnnotationTarget.Annotation, "app.Marker").has("app.Meta"))

    // 类型列表只含 Type 目标，按字典序排序；缺失查询返回空集合。
    List<String> types = registry.types()
    print(types.length())
    print(types.get(0))
    print(types.get(1))
    print(types.get(2))
    print(registry.ofType("app.Missing").isEmpty())
    print(registry.ofTarget(AnnotationTarget.Field, "app.Missing#x").isEmpty())
    return 0
}
