import xdk.text
import xdk.sys
import xdk.errors

static Int main() {
    String raw = "  Hello  "
    print("[" + raw.trim() + "]")
    print(raw.trim().toLower())
    print(padLeft("7", 3, "0"))
    print(parseInt("42").value())
    print(fileExists("."))
    print(resourceExists("no/such/resource"))
    if ErrorKind.NotFound == ErrorKind.NotFound {
        print("errors-ok")
    }
    return 0
}
