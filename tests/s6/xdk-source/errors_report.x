import xdk.errors

static Int main() {
    Result<Int, Error> ok = Ok(7)
    Result<Int, Error> same = report(ok)
    print(same.unwrapOr(0))
    Result<Int, Error> bad = Err(new CauseError(ErrorKind.Io, "disk", null))
    Result<Int, Error> returned = report(bad)
    print(returned.isErr())
    return 0
}
