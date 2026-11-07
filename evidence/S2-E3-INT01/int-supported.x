class Res {
    Int v;
    Res(Int v) { self.v = v }
    Result<Int, String> get(Bool ok) {
        defer print("m-defer")
        errdefer print("m-err")
        if !ok { return Err("bad") }
        return Ok(self.v)
    }
    void deinit() { print("dR") }
}
static Result<Int, String> run() {
    errdefer print("outer-err")
    defer print("outer-defer")
    if true {
        Res r = new Res(7)
        Int v = try r.get(false)
        print(v)
    }
    return Ok(0)
}
static Int main() {
    Result<Int, String> r = run()
    if r.isErr() { print("caught:" + r.error()) }
    return 0
}
