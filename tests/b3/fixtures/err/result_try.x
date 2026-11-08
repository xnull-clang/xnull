static Result<Int, String> maybe(Int n) {
    if n < 0 {
        return Err("neg")
    }
    return Ok(n * 2)
}

static Result<Int, String> run(Int n) {
    Int v = try maybe(n)
    return Ok(v + 1)
}

static Int main() {
    Result<Int, String> a = run(3)
    print(a.isOk())
    print(a.value())
    Result<Int, String> b = run(-1)
    print(b.isErr())
    print(b.error())
    print(b.unwrapOr(0))
    return 0
}
