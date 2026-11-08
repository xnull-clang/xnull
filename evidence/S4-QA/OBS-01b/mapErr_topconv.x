import xdk.errors
class E1 { ErrorKind kind() { return ErrorKind.Io } String describe() { return "e1" } }
class E2 { ErrorKind kind() { return ErrorKind.Internal } String describe() { return "e2" } }
static E2 conv(E1 e) { return new E2() }
static Int main() {
    Result<Int, E1> bad = Err(new E1())
    Result<Int, E2> mapped = mapErr(bad, conv)
    print(mapped.isErr())
    return 0
}
