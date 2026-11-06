static Int main() {
    Result<Int, String> r = Err("x")
    print(r.value())
    return 0
}
