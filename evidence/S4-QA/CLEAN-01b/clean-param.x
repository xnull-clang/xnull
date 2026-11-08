class R { void deinit() { print("dR") } }
static Result<Int, String> g(R r) { return Err("x") }
static Int main() {
    Result<Int, String> r = g(new R())
    print("err:" + r.error())
    return 0
}
