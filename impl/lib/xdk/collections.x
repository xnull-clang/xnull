// xdk.collections —— S6-07 源码单元（算法 + 4 个特化容器）
// 设计口径：
//   - 算法用比较/相等/键提取回调表达，不要求 T 可比较；
//   - 容器为纯 XNull 值类型封装（内部用 List），语义优先、复杂度为首版实现；
//   - 不改变内建容器语义（S1 §9）。

// sortBy：按 less(a,b) 升序插入排序，原地修改并返回。
List<T> sortBy<T>(List<T> xs, Bool(T, T) less) {
    Int i = 1
    while i < xs.length() {
        T v = xs.get(i)
        Int j = i - 1
        while j >= 0 {
            if less(v, xs.get(j)) {
                xs.set(j + 1, xs.get(j))
                j = j - 1
            } else {
                break
            }
        }
        xs.set(j + 1, v)
        i = i + 1
    }
    return xs
}

// dedup：按 eq 去重，保留首次出现顺序。
List<T> dedup<T>(List<T> xs, Bool(T, T) eq) {
    List<T> res = []
    for x in xs {
        Bool seen = false
        for y in res {
            if eq(x, y) {
                seen = true
                break
            }
        }
        if !seen {
            res.push(x)
        }
    }
    return res
}

// find：返回首个满足 pred 的元素；不存在返回 null。
T? find<T>(List<T> xs, Bool(T) pred) {
    for x in xs {
        if pred(x) {
            return x
        }
    }
    return null
}

// groupByInt：按 Int 键分组，保持元素相对顺序。
Map<Int, List<T>> groupByInt<T>(List<T> xs, Int(T) key) {
    Map<Int, List<T>> groups = [:]
    for x in xs {
        Int k = key(x)
        List<T> bucket = groups.getOr(k, [])
        bucket.push(x)
        groups.put(k, bucket)
    }
    return groups
}

// RingBuffer<T>：固定容量环形缓冲（首版用 List 承载，容量语义不变）。
class RingBuffer<T> {
    final Int capacity;
    List<T> data = []

    RingBuffer(Int capacity) {
        self.capacity = capacity
    }

    Int length() { return self.data.length() }

    Bool isEmpty() { return self.data.length() == 0 }

    Bool isFull() { return self.data.length() >= self.capacity }

    Bool push(T v) {
        if self.isFull() {
            return false
        }
        self.data.push(v)
        return true
    }

    T? pop() {
        if self.isEmpty() {
            return null
        }
        return self.data.remove(0)
    }

    T? peek() {
        if self.isEmpty() {
            return null
        }
        return self.data.get(0)
    }

    void clear() { self.data.clear() }
}

// OrderedMap<V>：插入序映射（Int 键；键序即插入序）。
class OrderedMap<V> {
    List<Int> keys = []
    List<V> vals = []

    Int length() { return self.keys.length() }

    Bool has(Int k) { return self.indexOf(k) >= 0 }

    Int indexOf(Int k) {
        Int i = 0
        while i < self.keys.length() {
            if self.keys.get(i) == k {
                return i
            }
            i = i + 1
        }
        return -1
    }

    void put(Int k, V v) {
        Int i = self.indexOf(k)
        if i >= 0 {
            self.vals.set(i, v)
            return
        }
        self.keys.push(k)
        self.vals.push(v)
    }

    V? get(Int k) {
        Int i = self.indexOf(k)
        if i < 0 {
            return null
        }
        return self.vals.get(i)
    }

    V getOr(Int k, V fallback) {
        Int i = self.indexOf(k)
        if i < 0 {
            return fallback
        }
        return self.vals.get(i)
    }

    Bool remove(Int k) {
        Int i = self.indexOf(k)
        if i < 0 {
            return false
        }
        self.keys.remove(i)
        self.vals.remove(i)
        return true
    }

    Int[] keysArray() {
        Int[] res = new Int[self.keys.length()]
        Int i = 0
        while i < self.keys.length() {
            res[i] = self.keys.get(i)
            i = i + 1
        }
        return res
    }

    V[] valuesArray() {
        V[] res = new V[self.vals.length()]
        Int i = 0
        while i < self.vals.length() {
            res[i] = self.vals.get(i)
            i = i + 1
        }
        return res
    }

    void clear() {
        self.keys.clear()
        self.vals.clear()
    }
}

// BTreeMap<V>：按键升序维护的有序映射（首版为有序关联表，接口与有序语义优先）。
class BTreeMap<V> {
    List<Int> keys = []
    List<V> vals = []

    Int length() { return self.keys.length() }

    Int lowerBound(Int k) {
        Int lo = 0
        Int hi = self.keys.length()
        while lo < hi {
            Int mid = (lo + hi) / 2
            if self.keys.get(mid) < k {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    Bool has(Int k) {
        Int i = self.lowerBound(k)
        return i < self.keys.length() && self.keys.get(i) == k
    }

    void put(Int k, V v) {
        Int i = self.lowerBound(k)
        if i < self.keys.length() && self.keys.get(i) == k {
            self.vals.set(i, v)
            return
        }
        self.keys.insert(i, k)
        self.vals.insert(i, v)
    }

    V? get(Int k) {
        Int i = self.lowerBound(k)
        if i >= self.keys.length() || self.keys.get(i) != k {
            return null
        }
        return self.vals.get(i)
    }

    V getOr(Int k, V fallback) {
        V? v = self.get(k)
        if v == null {
            return fallback
        }
        return v
    }

    Bool remove(Int k) {
        Int i = self.lowerBound(k)
        if i >= self.keys.length() || self.keys.get(i) != k {
            return false
        }
        self.keys.remove(i)
        self.vals.remove(i)
        return true
    }

    Int[] keysArray() {
        Int[] res = new Int[self.keys.length()]
        Int i = 0
        while i < self.keys.length() {
            res[i] = self.keys.get(i)
            i = i + 1
        }
        return res
    }

    void clear() {
        self.keys.clear()
        self.vals.clear()
    }
}

// PriorityQueue<T>：以 less 定义优先级的二叉堆最小堆。
class PriorityQueue<T> {
    List<T> heap = []
    Bool(T, T) less;

    PriorityQueue(Bool(T, T) less) {
        self.less = less
    }

    Int length() { return self.heap.length() }

    Bool isEmpty() { return self.heap.length() == 0 }

    void swap(Int i, Int j) {
        T tmp = self.heap.get(i)
        self.heap.set(i, self.heap.get(j))
        self.heap.set(j, tmp)
    }

    void siftUp(Int i) {
        while i > 0 {
            Int p = (i - 1) / 2
            if self.less(self.heap.get(i), self.heap.get(p)) {
                self.swap(i, p)
                i = p
            } else {
                break
            }
        }
    }

    void siftDown(Int i) {
        Int n = self.heap.length()
        while true {
            Int l = i * 2 + 1
            Int r = l + 1
            Int best = i
            if l < n && self.less(self.heap.get(l), self.heap.get(best)) {
                best = l
            }
            if r < n && self.less(self.heap.get(r), self.heap.get(best)) {
                best = r
            }
            if best == i {
                break
            }
            self.swap(i, best)
            i = best
        }
    }

    void push(T v) {
        self.heap.push(v)
        self.siftUp(self.heap.length() - 1)
    }

    T? peek() {
        if self.isEmpty() {
            return null
        }
        return self.heap.get(0)
    }

    T? pop() {
        if self.isEmpty() {
            return null
        }
        T top = self.heap.get(0)
        Int last = self.heap.length() - 1
        self.heap.set(0, self.heap.get(last))
        self.heap.remove(last)
        if !self.isEmpty() {
            self.siftDown(0)
        }
        return top
    }

    void clear() { self.heap.clear() }
}
