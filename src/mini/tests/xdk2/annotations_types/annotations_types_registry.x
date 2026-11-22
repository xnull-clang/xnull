// B2.2 场景：只读注册表按类型/目标查询、缺失返回空集合、类型列表排序。
import annotations.Annotations

static Map<String, AnnotationValue> emptyValues() {
    Map<String, AnnotationValue> values = [:]
    return values
}

static AnnotationInfo annotation(String typeName, AnnotationTarget target,
                                 String targetName, Int repeatIndex) {
    return new AnnotationInfo(typeName, target, targetName, emptyValues(), repeatIndex)
}

static String firstType(AnnotationSet set) {
    AnnotationInfo? head = set.first("app.Marker")
    if head == null {
        return "missing"
    }
    AnnotationInfo actual = head as AnnotationInfo
    return actual.targetName()
}

static Int main() {
    List<AnnotationInfo> annotations = []
    annotations.push(annotation("app.Marker", AnnotationTarget.Type, "app.Device", 1))
    annotations.push(annotation("app.Marker", AnnotationTarget.Type, "app.Device", 2))
    annotations.push(annotation("app.Tag", AnnotationTarget.Type, "app.Alpha", 1))
    annotations.push(annotation("app.FieldTag", AnnotationTarget.Field, "app.Device#name", 1))
    annotations.push(annotation("app.MethodTag", AnnotationTarget.Method, "app.Device#open(app.Text,Int)", 1))
    annotations.push(annotation("app.MethodTag", AnnotationTarget.Method, "app.Device#open(app.Text)", 1))
    annotations.push(annotation("app.CtorTag", AnnotationTarget.Constructor, "app.Device#<init>(app.Text)", 1))
    annotations.push(annotation("app.ParamTag", AnnotationTarget.Parameter, "app.Device#open(app.Text,Int)#0", 1))
    annotations.push(annotation("app.PackageTag", AnnotationTarget.Package, "app.device", 1))
    annotations.push(annotation("app.ItemTag", AnnotationTarget.EnumItem, "app.Color#Red", 1))
    annotations.push(annotation("app.DeinitTag", AnnotationTarget.Deinit, "app.Device#deinit()", 1))
    annotations.push(annotation("app.TypeParamTag", AnnotationTarget.TypeParameter, "app.Box#T", 1))
    annotations.push(annotation("app.TypeUseTag", AnnotationTarget.TypeUse, "app.Device#value:app.Text", 1))
    annotations.push(annotation("app.MetaTag", AnnotationTarget.Annotation, "app.Marker", 1))

    AnnotationRegistry registry = new AnnotationRegistry(annotations)

    // 按类型查询；重复项保序；缺失返回空集合。
    AnnotationSet device = registry.ofType("app.Device")
    print(device.length())
    print(firstType(device))
    print(device.all("app.Marker").get(0).repeatIndex())
    print(device.all("app.Marker").get(1).repeatIndex())
    print(registry.ofType("app.Missing").isEmpty())
    print(registry.ofType("app.Missing").first("app.Marker") == null)
    print(registry.ofType("app.Alpha").has("app.Tag"))

    // ofTarget 与便利查询一致。
    print(registry.ofTarget(AnnotationTarget.Type, "app.Device").length())
    print(registry.ofTarget(AnnotationTarget.Type, "app.Missing").isEmpty())
    print(registry.ofField("app.Device", "name").has("app.FieldTag"))
    print(registry.ofField("app.Device", "missing").isEmpty())

    List<String> openIntParams = []
    openIntParams.push("app.Text")
    openIntParams.push("Int")
    print(registry.ofMethod("app.Device", "open", openIntParams).has("app.MethodTag"))
    List<String> openTextParams = []
    openTextParams.push("app.Text")
    print(registry.ofMethod("app.Device", "open", openTextParams).has("app.MethodTag"))
    print(registry.ofMethod("app.Device", "close", openTextParams).isEmpty())

    List<String> ctorParams = []
    ctorParams.push("app.Text")
    print(registry.ofConstructor("app.Device", ctorParams).has("app.CtorTag"))
    List<String> noParams = []
    print(registry.ofConstructor("app.Device", noParams).isEmpty())

    print(registry.ofParameter("app.Device#open(app.Text,Int)", 0).has("app.ParamTag"))
    print(registry.ofParameter("app.Device#open(app.Text,Int)", 1).isEmpty())
    print(registry.ofPackage("app.device").has("app.PackageTag"))
    print(registry.ofEnumItem("app.Color", "Red").has("app.ItemTag"))
    print(registry.ofEnumItem("app.Color", "Blue").isEmpty())

    // 通用入口覆盖 Deinit/TypeParameter/TypeUse/Annotation。
    print(registry.ofTarget(AnnotationTarget.Deinit, "app.Device#deinit()").has("app.DeinitTag"))
    print(registry.ofTarget(AnnotationTarget.TypeParameter, "app.Box#T").has("app.TypeParamTag"))
    print(registry.ofTarget(AnnotationTarget.TypeUse, "app.Device#value:app.Text").has("app.TypeUseTag"))
    print(registry.ofTarget(AnnotationTarget.Annotation, "app.Marker").has("app.MetaTag"))

    // types 只列类型目标，按字典序排序，返回副本。
    List<String> types = registry.types()
    print(types.length())
    print(types.get(0))
    print(types.get(1))
    types.push("app.Fake")
    print(registry.types().length())
    print(registry.types().get(1))

    // 空注册表所有查询返回空集合。
    List<AnnotationInfo> none = []
    AnnotationRegistry empty = new AnnotationRegistry(none)
    print(empty.ofType("app.Device").isEmpty())
    print(empty.ofTarget(AnnotationTarget.Package, "app.device").isEmpty())
    print(empty.ofField("app.Device", "name").isEmpty())
    List<String> anyParams = []
    print(empty.ofMethod("app.Device", "open", anyParams).isEmpty())
    print(empty.ofConstructor("app.Device", anyParams).isEmpty())
    print(empty.ofParameter("app.Device#open()", 0).isEmpty())
    print(empty.ofPackage("app.device").isEmpty())
    print(empty.ofEnumItem("app.Color", "Red").isEmpty())
    print(empty.types().length())
    return 0
}
