import xdk.runtime
static Int main() {
    defer print("defer-ran")
    print("before")
    exit(7)
    return 0
}
