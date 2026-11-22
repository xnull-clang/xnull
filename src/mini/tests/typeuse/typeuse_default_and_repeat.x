package app
import xdk.annotations

@Retention(Runtime)
@annotation Meta { }

@Retention(Runtime)
@Target(TypeUse)
@Repeatable
@annotation Tag {
    final String note = ""
}

class Payload { }

class Box {
    @Meta String name
    @Tag("a") @Tag("b") Payload field
}

static Int main() {
    AnnotationRegistry reg = xdkAnnotationRegistry()
    print(reg.ofTarget(AnnotationTarget.Field, "app.Box#name").has("app.Meta"))
    print(reg.ofTarget(AnnotationTarget.TypeUse, "app.Box#name").length())
    print(reg.ofTarget(AnnotationTarget.TypeUse, "app.Box#field").length())
    return 0
}
