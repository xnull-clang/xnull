import xdk.collections

static Int main() {
    PriorityQueue<Int> queue = new PriorityQueue<Int>((Int left, Int right) -> left < right)
    queue.push(3)
    queue.push(1)
    queue.push(2)
    print(queue.pop())
    print(queue.pop())
    print(queue.length())

    RingBuffer<Int> buffer = new RingBuffer<Int>(2)
    print(buffer.push(1))
    print(buffer.push(2))
    print(buffer.push(3))
    print(buffer.pop())
    print(buffer.length())
    print(buffer.capacity())

    OrderedMap<String> ordered = new OrderedMap<String>()
    print(ordered.put(2, "two") == null)
    print(ordered.put(1, "one") == null)
    print(ordered.put(2, "TWO"))
    print(ordered.getOr(1, "?"))
    print(ordered.keys().get(0))
    print(ordered.values().get(0))
    print(ordered.remove(2))
    print(ordered.length())

    BTreeMap<String> tree = new BTreeMap<String>()
    print(tree.put(5, "five") == null)
    tree.put(1, "one")
    tree.put(3, "three")
    print(tree.keys().get(0))
    print(tree.keys().get(1))
    print(tree.keys().get(2))
    print(tree.values().get(1))
    print(tree.getOr(3, "?"))
    print(tree.put(3, "THREE"))
    print(tree.remove(5))
    print(tree.length())
    return 0
}
