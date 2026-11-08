static Result<Int, String> g() { return Ok(1) }
static Int main() {
    defer g()
    return 0
}
