import xdk.collections

static Int main() {
    RingBuffer<Int> rb = new RingBuffer<Int>(2)
    print(rb.isEmpty())
    print(rb.isFull())
    print(rb.push(1))
    print(rb.push(2))
    print(rb.isFull())
    print(rb.push(3))
    print(rb.pop())
    print(rb.length())

    OrderedMap<Int> om = new OrderedMap<Int>()
    om.put(2, 20)
    om.put(1, 10)
    print(om.get(1))
    print(om.indexOf(2))
    print(om.length())

    BTreeMap<Int> bt = new BTreeMap<Int>()
    bt.put(3, 30)
    bt.put(1, 10)
    bt.put(2, 20)
    print(bt.lowerBound(2))
    print(bt.getOr(2, 0))
    Int[] ks = bt.keysArray()
    print(ks[0])
    print(ks[2])

    PriorityQueue<Int> pq = new PriorityQueue<Int>((Int a, Int b) -> a < b)
    pq.push(3)
    pq.push(1)
    pq.push(2)
    print(pq.isEmpty())
    print(pq.pop())
    print(pq.pop())
    print(pq.pop())
    return 0
}
