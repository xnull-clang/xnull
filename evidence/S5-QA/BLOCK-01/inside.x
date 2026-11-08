import xdk.tasks
@tasks
static Int main() {
    Context c = Context.background()
    print(c.isCancelled())
    return 0
}
