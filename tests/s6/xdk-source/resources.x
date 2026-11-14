// XDK 源码层：内嵌资源（S6 §4.8）
import xdk.sys

static Int main() {
    print(resourceExists("a.txt"))
    print(resourceExists("nope.txt"))
    print(resourceSize("a.txt") != null)
    Result<Bytes, Error> b = readResource(null, "a.txt")
    print(b.value().length())
    Result<Text, Error> t = readResourceText(null, "a.txt")
    print(t.value().toString())
    Result<List<String>, Error> all = listResources(null, "")
    print(all.value().length())
    Result<List<String>, Error> sub = listResources(null, "sub")
    print(sub.value().length())
    print(readResource(null, "/abs").isErr())
    return 0
}
