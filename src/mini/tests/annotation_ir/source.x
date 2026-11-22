package app
import xdk.annotations

@Target(Annotation)
@annotation Nested {
    final String label = ""
}

@Retention(Runtime)
@Target(Type, Field, Method, Parameter)
@Repeatable
@annotation Audit {
    final String name = "default"
    final Int level = 1
    final String[] tags = []
    final Nested nested = @Nested("default")
}

@Retention(Runtime)
@Target(TypeUse)
@annotation TU {
}

@Audit("device", 2, ["a", "b"], @Nested("inner"))
@Audit("second")
class Device {
    @ReadOnly Int count = 0
    @Audit("field") String name
    @TU String typed
    @Deprecated
    @Override
    String old() {
        return "old"
    }
}

static Int main() {
    return 0
}
