package app.registry
import xdk.annotations

@Retention(Runtime)
@Target(Type)
@annotation Mark {
}

@Mark
class Widget {
}

static Int main() {
    print("version=" + str(xdkAnnotationRegistryVersion()))
    print("version2=" + str(xdkAnnotationRegistryVersion() == 2))
    AnnotationRegistry registry = xdkAnnotationRegistry()
    print("same=" + str(registry == xdkAnnotationRegistry()))
    List<AnnotationDeclaration> declarations = registry.declarations()
    print("count=" + str(declarations.length()))
    List<String> names = []
    Int index = 0
    while index < declarations.length() {
        names.push(declarations.get(index).name())
        index = index + 1
    }
    print("has-target=" + str(annotationsHas(names, "Target")) + "," + str(annotationsHas(names, "MustUse")) + "," + str(annotationsHas(names, "Mark")))
    AnnotationDeclaration targetDecl = annotationsFindDeclaration(declarations, "Target")
    print("target=" + targetDecl.describe())
    print("target-values=" + str(targetDecl.targets().length()) + "," + annotationTargetName(targetDecl.targets().get(0)) + "," + annotationRetentionName(targetDecl.retention()) + "," + str(targetDecl.parameterNames().length()))
    AnnotationDeclaration readonly = annotationsFindDeclaration(declarations, "ReadOnly")
    print("readonly=" + annotationTargetName(readonly.targets().get(0)))
    print("mark-type=" + str(registry.ofType("app.registry.Widget").length()))

    List<AnnotationInfo> manual = []
    Map<String, AnnotationValue> values = [:]
    manual.push(new AnnotationInfo("app.registry.Mark", AnnotationTarget.Type, "app.T", values, 1))
    manual.push(new AnnotationInfo("app.registry.Mark", AnnotationTarget.Field, "app.T#name", values, 1))
    manual.push(new AnnotationInfo("app.registry.Mark", AnnotationTarget.Method, "app.T#run()", values, 1))
    AnnotationRegistry old = new AnnotationRegistry(manual)
    List<String> noParams = []
    print("old=" + str(old.ofType("app.T").length()) + "," + str(old.ofField("app.T", "name").length()) + "," + str(old.ofMethod("app.T", "run", noParams).length()))
    print("old-declarations=" + str(old.declarations().length()))
    return 0
}

static Bool annotationsHas(List<String> names, String wanted) {
    Int index = 0
    while index < names.length() {
        if names.get(index) == wanted { return true }
        index = index + 1
    }
    return false
}

static AnnotationDeclaration annotationsFindDeclaration(List<AnnotationDeclaration> declarations, String name) {
    Int index = 0
    while index < declarations.length() {
        if declarations.get(index).name() == name { return declarations.get(index) }
        index = index + 1
    }
    return declarations.get(0)
}
