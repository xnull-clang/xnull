import xdk.sys

static Int main() {
    print(resourceExists("greeting.txt"))
    print(resourceExists("missing.txt"))
    print(resourceExists("../secret.txt"))
    print(resourceSize("greeting.txt"))
    print(resourceSize("missing.txt") == null)
    Result<Bytes, Error> b = readResource(null, "bytes.bin")
    print(b.isOk())
    print(b.value().length())
    Result<Bytes, Error> missing = readResource(null, "missing.txt")
    print(missing.isErr())
    Result<Bytes, Error> bad = readResource(null, "../secret.txt")
    print(bad.isErr())
    Result<String, Error> t = readResourceText(null, "greeting.txt")
    print(t.isOk())
    print(t.value())
    Result<String, Error> corrupt = readResourceText(null, "bytes.bin")
    print(corrupt.isErr())
    Result<List<String>, Error> ls = listResources(null, "")
    print(ls.value().length())
    Result<List<String>, Error> sub = listResources(null, "nested")
    print(sub.value().length())
    return 0
}
