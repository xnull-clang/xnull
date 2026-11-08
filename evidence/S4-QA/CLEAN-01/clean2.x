class Comp {
    Result<Int, String> close() { return Err("comp-fail") }
}
class R {
    void deinit() { print("dR") }
}
static Result<Int, String> f(Comp c, R r) {
    errdefer {
        Result<Int, String> cr = c.close()
        if (cr.isErr()) { print("comp:" + cr.error()) }
    }
    return Err("orig")
}
static Int main() {
    Result<Int, String> r = f(new Comp(), new R())
    print("err:" + r.error())
    return 0
}
