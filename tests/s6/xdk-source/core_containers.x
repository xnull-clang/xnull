import xdk.collections

static Bool containsString(String[] values, String wanted) {
    for value in values {
        if value == wanted { return true }
    }
    return false
}

static Int main() {
    Int[] numbers = [1, 2, 3]
    print(numbers.join("-"))
    String[] words = ["a", "b"]
    print(words.join(","))

    Map<String, Int> table = ["a": 1, "b": 2]
    String[] keys = table.keys()
    Int[] values = table.values()
    print(keys.length())
    print(values[0] + values[1])
    print(containsString(keys, "a"))
    print(containsString(keys, "b"))
    table.remove("a")
    print(table.length())
    print(table.has("a"))
    table.clear()
    print(table.length())

    Set<Int> tags = [7, 9]
    print(tags.at(0) + tags.at(1))
    print(tags.remove(7))
    print(tags.remove(7))
    tags.clear()
    print(tags.length())

    List<String> list = ["first", "second"]
    String removed = list.remove(0)
    print(removed)
    print(list.length())
    return 0
}
