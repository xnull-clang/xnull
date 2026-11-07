static Int main() {
    Result<Int, String> r = Ok(1)
    print(r.error())
    return 0
}
