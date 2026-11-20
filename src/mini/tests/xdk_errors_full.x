import xdk.errors

static Result<Int, Error> okOne() {
    return Ok(1)
}

static Result<Int, Error> badResult() {
    return Err(new BasicError(ErrorKind.InvalidArgument, "bad"))
}

static Result<Result<Int, Error>, Error> nestedOkResult() {
    return Ok(okOne())
}

static Int main() {
    BasicError error = new BasicError(ErrorKind.NotFound, "missing")
    print(error.kind() == ErrorKind.NotFound)
    print(error.code() == "")
    print(error.describe())
    BasicError detailed = error.withCode("cfg.missing").withDetail("path", "a.conf")
    print(detailed.describe())
    print(detailed.details().length())

    ErrorReport report = annotate(detailed, "parse")
    report = report.withStep("load")
    print(report.describe())
    print(report.steps().length())

    ErrorGroup group = new ErrorGroup()
    group.add(detailed)
    group.add(new BasicError(ErrorKind.Cancelled, "stop"))
    print(group.length())
    print(group.kind() == ErrorKind.Cancelled)
    print(group.details().length())

    Result<Int, Error> ok = okOne()
    print(mapOk(ok, (Int value) -> value + 1).value())
    Result<Int, Error> bad = badResult()
    print(mapErr(bad, (Error failure) -> failure).isErr())
    print(unwrapOr(bad, 7))

    print(check(true, ErrorKind.InvalidArgument, "x").isOk())
    print(check(false, ErrorKind.InvalidArgument, "x").isErr())
    print(isRetryable(ErrorKind.Timeout))
    print(isRetryableError(badResult().error()))
    print(report.causes().length())
    print(group.causes().length())
    print(errorKindName(ErrorKind.NotFound))
    print(errorKindFromName("NOT_FOUND").value() == ErrorKind.NotFound)
    print(errorKindCode(ErrorKind.Timeout))
    print(errorKindFromCode(7) == ErrorKind.Cancelled)
    print(tryErrorDetail("path", "a.conf").isOk())
    print(tryErrorDetail("bad:key", "a.conf").isErr())

    List<Result<Int, Error>> results = []
    results.push(okOne())
    results.push(badResult())
    Result<List<Int>, ErrorGroup> collected = collectOk(results)
    print(collected.isErr())
    print(collected.error().length())
    print(collected.error().kind() == ErrorKind.InvalidArgument)

    Result<Int, Error> flat = flatten(nestedOkResult())
    print(flat.isOk())
    print(flat.value())

    Result<String, Error> text = mapOk(okOne(), (Int value) -> "n=" + str(value))
    print(text.value())
    Result<Int, String> mappedError = mapErr(badResult(), (Error failure) -> "bad")
    print(mappedError.isErr())
    print(mappedError.error())
    return 0
}
