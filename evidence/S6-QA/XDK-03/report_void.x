import xdk.errors
class E implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "disk" }
}
static Int main() {
    Result<Int, Error> r = Err(new E())
    report(r)
    return 0
}
