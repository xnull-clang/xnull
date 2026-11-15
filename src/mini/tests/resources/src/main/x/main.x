import xdk.sys

static Int main() {
    print(resourceExists("greeting.txt"))
    print(readResourceText("greeting.txt"))
    print(resourceCount())
    return 0
}
