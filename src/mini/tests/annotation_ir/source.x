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


class Base {
}

protocol Ready {
    Bool ready();
}

class Widget : Base implements Ready {
    private String _name
    final Int count
    Widget(String name, Int count) {
        self._name = name
        self.count = count
    }
    static Int make() {
        return 1
    }
    Bool ready() {
        return true
    }
}

struct PointS {
    Int x
    Int y
    PointS(Int x, Int y) {
        self.x = x
        self.y = y
    }
}

enum Color {
    Red,
    Green,
}

class Box<T> {
    T value
    Box(T value) {
        self.value = value
    }
}

static Int main() {
    return 0
}
