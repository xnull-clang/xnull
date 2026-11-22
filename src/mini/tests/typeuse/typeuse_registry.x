package app
import xdk.annotations

@Retention(Runtime)
@Target(TypeUse)
@annotation TU {
    final String note = ""
}

@Retention(Runtime)
@Target(Field)
@annotation FieldTag { }

@Retention(Runtime)
@Target(Method)
@annotation MethodTag { }

@Retention(Runtime)
@Target(Parameter)
@annotation ParamTag { }

class Payload { }

class Box {
    @TU("field") Payload field
    @TU("string") String label
    @FieldTag String name

    @TU("return") @MethodTag Payload make(@TU("param") @ParamTag Payload p) {
        @TU("local") Payload local = p
        return local
    }
}

static String firstType(AnnotationSet set) {
    AnnotationInfo? head = set.first("app.Payload")
    if head == null {
        return "missing"
    }
    AnnotationInfo actual = head as AnnotationInfo
    return actual.typeName()
}

static Int main() {
    Box b = new Box()
    AnnotationRegistry reg = xdkAnnotationRegistry()
    print(firstType(reg.ofTarget(AnnotationTarget.TypeUse, "app.Box#field")))
    AnnotationInfo? labelInfo = reg.ofTarget(AnnotationTarget.TypeUse, "app.Box#label").first("String")
    if labelInfo == null {
        print("missing")
    } else {
        AnnotationInfo actualLabel = labelInfo as AnnotationInfo
        print(actualLabel.typeName())
    }
    print(firstType(reg.ofTarget(AnnotationTarget.TypeUse, "app.Box#make(Payload)#return")))
    print(firstType(reg.ofTarget(AnnotationTarget.TypeUse, "app.Box#make(Payload)#0")))
    print(firstType(reg.ofTarget(AnnotationTarget.TypeUse, "app.Box#make(Payload)#local:local")))
    print(reg.ofTarget(AnnotationTarget.Field, "app.Box#name").has("app.FieldTag"))
    print(reg.ofTarget(AnnotationTarget.Method, "app.Box#make(Payload)").has("app.MethodTag"))
    print(reg.ofTarget(AnnotationTarget.Parameter, "app.Box#make(Payload)#0").has("app.ParamTag"))
    return 0
}
