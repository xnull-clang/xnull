// R4 evidence: full layout parsing with the same tokens as format.
import xdk.time

static Int main() {
    Result<DateTime, Error> full = parseDateTimeLayout("2024-01-31 23:59:59.250", "yyyy-MM-dd HH:mm:ss.SSS")
    print(full.isOk())
    print(full.value().format("yyyy-MM-dd HH:mm:ss.SSS"))
    Result<DateTime, Error> named = parseDateTimeLayout("Wed, 31 Jan 2024 23:59:59", "EEE, dd MMM yyyy HH:mm:ss")
    print(named.isOk())
    print(named.value().format("EEEE, MMMM dd yyyy"))
    Result<DateTime, Error> longNames = parseDateTimeLayout("Wednesday, January 31 2024", "EEEE, MMMM dd yyyy")
    print(longNames.isOk())
    print(longNames.value().timestamp())
    Result<DateTime, Error> iso = parseDateTime("2024-01-31T23:59:59.250Z")
    print(iso.isOk())
    print(iso.value().timestamp())
    print(parseDateTime("2024-01-31 23:59:59").isOk())
    print(parseDateTime("2024-01-31T23:59:59").value().format("yyyy-MM-dd HH:mm:ss"))
    print(parseDateTimeLayout("2024-02-30", "yyyy-MM-dd").isErr())
    print(parseDateTimeLayout("Wed, 31 Jan 2024", "EEE, dd MMM yyyy").isOk())
    print(parseDateTimeLayout("Thu, 31 Jan 2024", "EEE, dd MMM yyyy").isErr())
    print(parseDateTimeLayout("2024-01-31x", "yyyy-MM-dd").isErr())
    print(parseDateTimeLayout("2024-01-31", "yyyy-MM-dd").value().timestamp())
    return 0
}
