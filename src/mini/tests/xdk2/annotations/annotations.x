package app
import xdk.annotations

@Retention(Runtime)
@Target(Type)
@annotation Mark {
    final String name = ""
}

@Mark("canonical")
class Device {
}

static Int main() {
    print(AnnotationTarget.Type == AnnotationTarget.Type)
    print(AnnotationRetention.Runtime == AnnotationRetention.Runtime)
    AnnotationValue intValue = AnnotationValue.ofInt(7)
    Int? maybeInt = intValue.asInt()
    if maybeInt == null {
        print("missing")
    } else {
        print(maybeInt as Int)
    }
    AnnotationValue stringValue = AnnotationValue.ofString("ok")
    String? maybeString = stringValue.asString()
    if maybeString == null {
        print("missing")
    } else {
        print(maybeString as String)
    }
    print(xdkAnnotationRegistryVersion())
    AnnotationRegistry reg = xdkAnnotationRegistry()
    print(reg.types().length())
    AnnotationSet set = reg.ofType("app.Device")
    print(set.has("app.Mark"))
    print(set.length())
    return 0
}
