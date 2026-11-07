import xdk.errors

class IoError implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "disk" }
}
static Int main() {
    Result<Int, Error> r = Err(new IoError())
    report(r)
    print(r.isErr())
    return 0
}
