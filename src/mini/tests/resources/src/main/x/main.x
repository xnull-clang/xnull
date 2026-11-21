import xdk.sys

static Int main() {
    print(resourceExists("greeting.txt"))
    print(readResourceText(null, "greeting.txt").value())
    print(resourceCount())
    return 0
}
