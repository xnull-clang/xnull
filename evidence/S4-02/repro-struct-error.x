import xdk.errors
struct Err2 {
    Int code;
    Err2(Int c) { self.code = c }
    ErrorKind kind() { return ErrorKind.PermissionDenied }
    String describe() { return "no access" }
}
static Result<Int, Err2> go() {
    return Err(new Err2(7))
}
static Int main() {
    Result<Int, Err2> r = go()
    report(r)
    print(r.isErr())
    return 0
}
