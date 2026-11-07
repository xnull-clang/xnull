class Res {
    String name;
    Res(String n) { self.name = n }
    void close() { print("close:" + self.name) }
}
class State {
    Int n = 0;
    void inc() { self.n = self.n + 1 }
    void dec() { self.n = self.n - 1 }
}
static Result<Int, String> tx(State s) {
    s.inc()
    errdefer s.dec()
    s.inc()
    errdefer s.dec()
    return Err("fail")
}
static Result<Int, String> inner() {
    errdefer print("inner-e")
    return Err("x")
}
static Result<Int, String> outer() {
    errdefer print("outer-e")
    Int v = try inner()
    return Ok(v)
}
static Result<Int, String> work(Res a, Res b) {
    errdefer a.close()
    print("work")
    errdefer b.close()
    return Err("boom")
}
static Result<Int, String> ok(Res a) {
    errdefer a.close()
    return Ok(1)
}
static Int main() {
    Res a = new Res("a")
    Res b = new Res("b")
    Result<Int, String> r = work(a, b)
    if (r.isErr()) { print("err:" + r.error()) }
    Result<Int, String> s = ok(a)
    print(s.unwrapOr(0))
    State st = new State()
    Result<Int, String> t = tx(st)
    print(st.n)
    print(t.error())
    Result<Int, String> o = outer()
    print(o.isErr())
    return 0
}
