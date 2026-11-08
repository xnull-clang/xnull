static Result<Int, String> run(Int n) {
    defer print("defer")
    errdefer print("errdefer")
    if n < 0 {
        return Err("neg")
    }
    return Ok(n)
}

static Int main() {
    Result<Int, String> a = run(1)
    print(a.isOk())
    Result<Int, String> b = run(-1)
    print(b.isErr())
    print(b.unwrapOr(0))
    return 0
}
