static Int bad() {
    throw "init-boom"
}
Int g = bad()
static Int main() {
    print("SHOULD-NOT-RUN")
    return 0
}
