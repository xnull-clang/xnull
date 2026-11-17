import xdk.collections

static Int main() {
    Map<String, Int> empty = [:]
    empty.put("one", 1)
    print(empty.getOr("one", 0))
    print(empty.has("missing"))

    Map<String, Int> explicit = ["two": 2]
    print(explicit.getOr("two", 0))
    return 0
}
