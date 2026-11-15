import xdk.errors

static Int main() {
    if ErrorKind.NotFound == ErrorKind.NotFound {
        print("errors ok")
    }
    print(isRetryable(ErrorKind.Network))
    return 0
}
