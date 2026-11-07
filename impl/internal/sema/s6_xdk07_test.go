package sema

import "testing"

// XDK-07：collections 特化容器的成员签名（编译路径 QA 回归）。
// 覆盖 RingBuffer/OrderedMap/BTreeMap/PriorityQueue 的公开方法，以及
// PriorityQueue 的函数类型字段 `less` 的调用。
func TestXDK07CollectionsMembers(t *testing.T) {
	expectNone(t, `import xdk.collections

class RingBuffer<T> {
    List<T> data = []
    Int length() { return self.data.length() }
    Bool isEmpty() { return self.data.length() == 0 }
    Bool isFull() { return false }
    Bool push(T v) { self.data.push(v); return true }
    T? pop() { return null }
    void clear() { self.data.clear() }
}

class OrderedMap<V> {
    List<Int> keys = []
    Int indexOf(Int k) { return -1 }
    Int length() { return self.keys.length() }
    void put(Int k, V v) {}
    V? get(Int k) { return null }
}

class BTreeMap<V> {
    Int lowerBound(Int k) { return 0 }
    void put(Int k, V v) {}
    V? get(Int k) { return null }
}

class PriorityQueue<T> {
    List<T> heap = []
    Bool(T, T) less;
    PriorityQueue(Bool(T, T) less) { self.less = less }
    Bool isEmpty() { return self.heap.length() == 0 }
    void swap(Int i, Int j) {}
    void siftUp(Int i) {
        if self.less(self.heap.get(i), self.heap.get(0)) {
            self.swap(i, 0)
        }
    }
    void siftDown(Int i) {}
    void push(T v) { self.heap.push(v) }
    T? pop() { return null }
}

static Int main() {
    RingBuffer<Int> rb = new RingBuffer<Int>()
    Bool f = rb.isFull()
    Bool e = rb.isEmpty()
    Int n = rb.length()
    Bool p = rb.push(1)
    Int? rv = rb.pop()
    rb.clear()

    OrderedMap<Int> om = new OrderedMap<Int>()
    Int oi = om.indexOf(1)
    om.put(1, 10)
    Int? og = om.get(1)

    BTreeMap<Int> bt = new BTreeMap<Int>()
    Int lb = bt.lowerBound(1)
    bt.put(1, 10)
    Int? bg = bt.get(1)

    PriorityQueue<Int> pq = new PriorityQueue<Int>((Int a, Int b) -> a < b)
    Bool pe = pq.isEmpty()
    pq.push(1)
    pq.swap(0, 0)
    pq.siftUp(0)
    pq.siftDown(0)
    Int? pp = pq.pop()
    return n + oi + lb
}`)

	// 成员实参仍必须按声明检查。
	expectCode(t, `import xdk.collections
class RingBuffer<T> {
    List<T> data = []
    Bool push(T v) { self.data.push(v); return true }
}
static Int main() {
    RingBuffer<Int> rb = new RingBuffer<Int>()
    rb.push("x")
    return 0
}`, TyAssignability)

	// 函数类型字段（less）的实参也必须按声明检查；不能只“放行未知返回”。
	expectCode(t, `import xdk.collections
class PriorityQueue<T> {
    Bool(T, T) less;
    PriorityQueue(Bool(T, T) less) { self.less = less }
}
static Int main() {
    PriorityQueue<Int> pq = new PriorityQueue<Int>((Int a, Int b) -> a < b)
    Bool b = pq.less(1, "x")
    return 0
}`, TyAssignability)
}
