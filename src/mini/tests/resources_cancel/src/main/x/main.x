import xdk.sys

static Int main() {
    Context ctx = Context.background()
    Result<Bytes, Error> pre = readResource(ctx, "greeting.txt")
    print(pre.isOk())
    ctx.cancel()
    Result<Bytes, Error> r = readResource(ctx, "greeting.txt")
    print(r.isErr())
    Result<String, Error> t = readResourceText(ctx, "greeting.txt")
    print(t.isErr())
    Result<List<String>, Error> l = listResources(ctx, "")
    print(l.isErr())
    print(ctx.isCancelled())
    return 0
}
