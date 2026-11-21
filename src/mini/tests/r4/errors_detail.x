// R4 evidence: DetailedError aggregation through the documented T0 path
// (custom DetailedError -> BasicError -> ErrorGroup), plus the checked
// helpers used instead of blocked BasicError.tryWith* methods.
import xdk.errors

class CustomFailure implements Error, DetailedError {
    ErrorKind _kind
    String _code
    String _message

    CustomFailure(ErrorKind kind, String code, String message) {
        self._kind = kind
        self._code = code
        self._message = message
    }

    ErrorKind kind() {
        return self._kind
    }

    String message() {
        return self._message
    }

    String code() {
        return self._code
    }

    String describe() {
        return "[" + self._code + "] " + errorKindName(self._kind) + ": " + self._message
    }
}

static Int main() {
    CustomFailure custom = new CustomFailure(ErrorKind.InvalidArgument, "cfg.bad", "bad setting")
    BasicError base = new BasicError(custom.kind(), custom.message())
    base = base.withCode(custom.code())
    base = base.withDetail("origin", "custom")
    ErrorGroup group = new ErrorGroup()
    group.add(base)
    BasicError missing = new BasicError(ErrorKind.NotFound, "missing")
    missing = missing.withDetail("path", "a.conf")
    group.add(missing)
    print(group.length())
    print(group.details().length())
    print(group.details().get(0).key)
    print(group.details().get(0).value)
    print(group.details().get(1).key)
    print(group.kind() == ErrorKind.InvalidArgument)
    print(group.causes().length())
    print(group.causes().get(0).describe())
    print(group.describe())

    BasicError cancelled = new BasicError(ErrorKind.Cancelled, "stop")
    ErrorGroup mixed = new ErrorGroup()
    mixed.add(base)
    mixed.add(cancelled)
    print(mixed.kind() == ErrorKind.Cancelled)

    // Direct T0 aggregation: ErrorGroup converts arbitrary DetailedError.
    ErrorGroup direct = new ErrorGroup()
    direct.addDetailed(custom)
    print(direct.length())
    print(direct.causes().get(0).describe())
    print(direct.kind() == ErrorKind.InvalidArgument)

    // Direct BasicError.tryWith* methods: checked, no silent drop.
    Result<BasicError, Error> triedCode = base.tryWithCode("cfg.checked")
    print(triedCode.isOk())
    print(triedCode.value().code())
    print(base.tryWithCode("Cfg.Bad").isErr())
    Result<BasicError, Error> triedDetail = base.tryWithDetail("phase", "load")
    print(triedDetail.isOk())
    print(triedDetail.value().details().length())
    print(base.tryWithDetail("bad:key", "x").isErr())
    BasicError cause = new BasicError(ErrorKind.Io, "disk")
    Result<BasicError, Error> triedCause = base.tryWithCause(cause)
    print(triedCause.isOk())
    print(triedCause.value().causes().length())
    print(base.tryWithCause(base).isErr())
    print(base.tryWithCause(null).isErr())
    BasicError capped = new BasicError(ErrorKind.Io, "root")
    Int causeIndex = 0
    while causeIndex < 8 {
        capped = capped.withCause(new BasicError(ErrorKind.Io, "c" + str(causeIndex)))
        causeIndex = causeIndex + 1
    }
    print(capped.tryWithCause(new BasicError(ErrorKind.Io, "over")).isErr())

    print(isValidErrorCode("cfg.bad"))
    print(isValidErrorCode(""))
    print(isValidErrorCode("Cfg.Bad"))
    print(isValidErrorCode("cfg/bad"))
    print(tryErrorDetail("path", "a.conf").isOk())
    print(tryErrorDetail("bad:key", "a.conf").isErr())
    print(tryErrorDetail("path", "a\nconf").isErr())

    ErrorReport report = toErrorReport(new BasicError(ErrorKind.NotFound, "root"))
    print(report.tryWithStep("load").isOk())
    print(report.tryWithStep("").isErr())
    print(report.tryWithStep("bad\nstep").isErr())
    ErrorReport full = report
    Int index = 0
    while index < 16 {
        full = full.withStep("s" + str(index))
        index = index + 1
    }
    print(full.steps().length())
    print(full.tryWithStep("over").isErr())
    return 0
}
