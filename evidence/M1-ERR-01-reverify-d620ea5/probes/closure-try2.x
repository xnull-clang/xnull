static Result<Int, String> g(Int x) { return Err("bad") }
static Result<Int, String> f() {
    Result<Int, String>(Int) h = (Int x) -> { Int v = try g(x); return Ok(v); };
    Result<Int, String> r = h(-1);
    if r.isErr() { print("closure-err:" + r.error()); }
    print("after-call");
    return Ok(1);
}
static Int main() { Result<Int, String> r = f(); if r.isOk() { print("outer-ok") } else { print("outer-err:" + r.error()) }; return 0; }
