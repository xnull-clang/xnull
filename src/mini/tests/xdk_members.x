static Int main() {
    List<Int> items = [1, 2, 3]
    items.clear()
    print(items.length())

    Set<Int> seen = Set.of(1, 2, 3)
    print(seen.remove(2))
    print(seen.length())
    seen.clear()
    print(seen.length())

    Map<String, Int> map = [:]
    print(map.put("a", 1))
    print(map.put("a", 2))
    print(map.tryGet("a").value())
    print(map.tryGet("z").isErr())
    print(map.keys().length())
    print(map.values().length())
    print(map.remove("z"))
    print(map.remove("a"))
    print(map.removeOr("q", 9))
    map.put("a", 1)
    map.clear()
    print(map.length())

    List<Int> checked = [1, 2, 3]
    print(checked.tryGet(1).value())
    print(checked.tryGet(9).isErr())
    print(checked.trySet(0, 9).isOk())
    print(checked.get(0))
    print(checked.tryInsert(checked.length(), 7).isOk())
    print(checked.length())
    print(checked.tryRemove(0).value())
    print(checked.length())
    return 0
}
