import xdk.errors
class E { ErrorKind kind() { return ErrorKind.Io } String describe() { return "x" } }
static Int main() {
    Result<Int, E> bad = Err(new E())
    Result<Int, E> again = report(bad)
    return 0
}
