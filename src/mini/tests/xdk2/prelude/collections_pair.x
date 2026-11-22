// B3.3 泛型 Pair<A,B>/Entry<K,V> 与 1.x 固定 Pair/IntPair 兼容；B3.4 List.copy。
import xdk.collections

class Box {
    Int value
    Box(Int value) { self.value = value }
}

static Int main() {
    // 1.x 兼容：Map.entries 仍返回固定 Pair/IntPair。
    Map<String, Int> names = [:]
    names.put("a", 1)
    names.put("b", 2)
    List<Pair> legacy = names.entries()
    print(legacy.length())
    print(legacy.get(0).first)
    print(legacy.get(0).second)

    Map<Int, Int> numbers = [:]
    numbers.put(7, 70)
    List<IntPair> ints = numbers.entries()
    print(ints.get(0).first)
    print(ints.get(0).second)

    // 2.x 泛型 Pair<A,B>。
    Pair<Int, String> pair = new Pair<Int, String>(7, "seven")
    print(pair.first())
    print(pair.second())
    Pair<Int, String> changed = pair.withFirst(8)
    print(changed.first())
    print(changed.second())
    print(pair.first())
    Pair<Int, String> same = new Pair<Int, String>(7, "seven")
    print(pair.equals(same))
    print(pair.equals(new Pair<Int, String>(7, "other")))
    print(pair.toString())
    Pair<String, Double> mixed = new Pair<String, Double>("pi", 3.5)
    print(mixed.first())
    print(mixed.second())

    // 2.x 泛型 Entry<K,V>。
    Entry<String, Long> entry = new Entry<String, Long>("count", 9)
    print(entry.key)
    print(entry.value)

    // B3.4 List.copy：浅复制，副本独立。
    List<Int> source = [1, 2, 3]
    List<Int> copy = source.copy()
    copy.set(0, 9)
    copy.push(4)
    print(source.length())
    print(source.get(0))
    print(copy.length())
    print(copy.get(0))
    List<String> words = ["x", "y"]
    List<String> wordsCopy = words.copy()
    wordsCopy.set(1, "z")
    print(words.get(1))
    print(wordsCopy.get(1))
    Box box = new Box(5)
    List<Box> boxes = [box]
    List<Box> boxesCopy = boxes.copy()
    print(boxesCopy.get(0) == box)
    print(boxesCopy.length())
    List<Int> empty = []
    print(empty.copy().length())
    return 0
}
