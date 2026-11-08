import xdk.errors
class E implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "io" }
}
static Int main() {
    E e = new E()
    print(e.kind())
    print(e.kind())
    print(e.kind() == ErrorKind.Io)
    print(e.describe())
    return 0
}
