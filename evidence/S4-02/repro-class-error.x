import xdk.errors
class E implements Error {
    String msg;
    E(String m) { self.msg = m }
    ErrorKind kind() { return ErrorKind.Io }
    String describe() { return self.msg }
}
static Result<Int, E> fail() {
    return Err(new E("disk full"))
}
static Int main() {
    Result<Int, E> r = fail()
    report(r)
    Result<Int, E> r2 = Ok(5)
    report(r2)
    print(r2.unwrapOr(0))
    return 0
}
