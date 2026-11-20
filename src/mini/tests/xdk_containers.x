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
    return 0
}
