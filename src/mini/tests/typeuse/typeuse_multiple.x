package app
import xdk.annotations

@Retention(Runtime)
@Target(TypeUse)
@annotation A { }

@Retention(Runtime)
@Target(TypeUse)
@annotation B { }

class Payload { }

class Box {
    @A @B Payload field
}

static Int main() {
    AnnotationRegistry reg = xdkAnnotationRegistry()
    print(reg.ofTarget(AnnotationTarget.TypeUse, "app.Box#field").length())
    return 0
}
