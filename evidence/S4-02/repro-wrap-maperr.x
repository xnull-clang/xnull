import xdk.errors
class E1 implements Error {
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return "e1" }
}
class E2 implements Error {
    ErrorKind kind() { return ErrorKind.NotFound }
    String describe() { return "e2" }
}
static E2 conv(E1 e) { return new E2() }
static Result<Int, E2> chained() {
    Result<Int, E1> r = Err(new E1())
    Result<Int, E2> mapped = mapErr(r, conv)
    report(mapped)
    return mapped
}
static Result<Int, E2> wrapit() {
    Result<Int, E2> r = Err(new E2())
    return wrap(r, new E2())
}
static Int main() {
    Result<Int, E2> a = chained()
    print(a.isErr())
    Result<Int, E2> b = wrapit()
    print(b.isErr())
    Result<Int, E2> c = Ok(3)
    Result<Int, E2> d = mapErr(c, conv)
    print(d.unwrapOr(0))
    return 0
}
