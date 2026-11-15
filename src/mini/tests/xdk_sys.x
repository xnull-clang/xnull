import xdk.sys

static Int main() {
    print(fileExists("src/examples/hello.x"))
    print(fileExists("no-such-file"))
    return 0
}
