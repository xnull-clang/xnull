import xdk.errors
class IoError implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "user=alice\npassword=secret" }
}
static Int main() {
    Result<Int, IoError> bad = Err(new IoError())
    report(bad)
    return 0
}
