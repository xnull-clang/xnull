import xdk.errors
static Result<Int, String> g() { return Err("disk") }
static Int main() {
    defer {
        Result<Int, String> r = g()
        if (r.isErr()) { report(r) }
    }
    return 0
}
