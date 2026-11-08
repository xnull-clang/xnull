import xdk.runtime
static Int main() {
    defer print("should-not-run")
    exit(7)
    return 0
}
