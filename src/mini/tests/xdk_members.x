import xdk.collections

class RefItem {
    Int id

    RefItem(Int id) {
        self.id = id
    }
}

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
    map.put("b", 2)
    List<Pair> entries = map.entries()
    print(entries.length())
    print(entries.get(0).first)
    print(entries.get(0).second)
    map.remove("b")
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

    Map<Int, Int> intMap = [:]
    print(intMap.put(1, 10))
    print(intMap.put(2, 20))
    List<IntPair> intEntries = intMap.entries()
    print(intEntries.length())
    print(intEntries.get(0).first)
    print(intEntries.get(0).second)
    print(intEntries.get(1).first)
    print(intEntries.get(1).second)
    print(intMap.getOr(1, 0))
    print(intMap.remove(2))
    print(intMap.length())
    print(intMap.keys().length())
    print(intMap.values().length())

    Set<String> strings = Set.of("a", "b", "a")
    print(strings.length())
    print(strings.has("a"))
    print(strings.add("c"))
    print(strings.remove("b"))
    strings.clear()
    print(strings.length())

    Map<String, String> names = [:]
    print(names.put("a", "alpha"))
    print(names.getOr("a", "none"))
    print(names.getOr("z", "none"))
    print(names.keys().get(0))
    print(names.values().get(0))
    print(names.tryGet("a").isOk())
    print(names.remove("a"))
    print(names.length())

    Map<String, Long> sizes = [:]
    sizes.put("big", 9000000000)
    print(sizes.getOr("big", 0))
    print(sizes.values().get(0))

    Set<Long> longs = Set.of(9000000000, 4, 4)
    print(longs.length())
    print(longs.has(9000000000))
    print(longs.add(5))
    print(longs.remove(4))
    print(longs.length())

    Set<Double> doubles = Set.of(1.5, 2.5, 1.5)
    print(doubles.length())
    print(doubles.has(2.5))

    Map<String, Long> generic = [:]
    generic.put("first", 11)
    generic.put("second", 22)
    List<Entry<String, Long>> genericEntries = generic.entries()
    print(genericEntries.length())
    print(genericEntries.get(0).key)
    print(genericEntries.get(0).value)
    print(genericEntries.get(1).value)

    Map<Int, String> byId = [:]
    byId.put(7, "seven")
    List<Entry<Int, String>> idEntries = byId.entries()
    print(idEntries.get(0).key)
    print(idEntries.get(0).value)
    print(byId.entries().get(0).key)

    RefItem firstItem = new RefItem(1)
    RefItem secondItem = new RefItem(2)
    Set<RefItem> refs = Set.of(firstItem, secondItem, firstItem)
    print(refs.length())
    print(refs.has(secondItem))
    print(refs.remove(firstItem))
    print(refs.length())
    return 0
}
