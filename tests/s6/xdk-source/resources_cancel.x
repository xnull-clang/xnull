import xdk.sys

static Int main() {
    Context context = Context.background()
    print(context.isCancelled())
    context.cancel()
    print(context.isCancelled())

    Result<Bytes, Error> bytes = readResource(context, "a.txt")
    print(bytes.isErr())
    print(bytes.error().kind() == ErrorKind.Cancelled)

    Result<Text, Error> text = readResourceText(context, "a.txt")
    print(text.isErr())
    print(text.error().kind() == ErrorKind.Cancelled)

    Result<List<String>, Error> list = listResources(context, "")
    print(list.isErr())
    print(list.error().kind() == ErrorKind.Cancelled)
    return 0
}
