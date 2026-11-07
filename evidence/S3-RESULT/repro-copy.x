static Int main() {
    Result<Int, String> a = Ok(5)
    Result<Int, String> b = a
    print(b.unwrapOr(0))
    return 0
}
