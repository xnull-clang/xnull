import xdk.errors
class IoError implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "disk" }
}
static Int main() {
    Result<Int, IoError> ok = Ok(1)
    report(ok)
    Result<Int, IoError> bad = Err(new IoError())
    report(bad)
    print(bad.isErr())
    return 0
}
