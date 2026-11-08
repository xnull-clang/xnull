import xdk.sys
import xdk.tasks
import xdk.errors
@tasks
static Int main() {
    Context c = Context.background()
    print(resourceExists("a.txt"))
    Int? sz = resourceSize("a.txt")
    if (sz != null) { print("size-ok") }
    Result<Bytes, Error> rb = readResource(c, "a.txt")
    if (rb.isOk()) { print("rb-ok") }
    Result<Text, Error> rt = readResourceText(c, "a.txt")
    if (rt.isOk()) { print("rt-ok") }
    Result<List<String>, Error> rl = listResources(c, "")
    if (rl.isOk()) { print("rl-ok") }
    return 0
}
