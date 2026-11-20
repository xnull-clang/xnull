// xdk.collections —— T0 专用容器
package xdk.collections

// PriorityQueue<T>：以 lessThan 定义优先级的二叉堆最小堆。
class PriorityQueue<T> {
    List<T> heap = []
    Bool(T, T) _lessThan

    PriorityQueue(Bool(T, T) lessThan) {
        self._lessThan = lessThan
    }

    Int length() { return self.heap.length() }

    Bool isEmpty() { return self.heap.length() == 0 }

    void swap(Int index, Int otherIndex) {
        T temporary = self.heap.get(index)
        self.heap.set(index, self.heap.get(otherIndex))
        self.heap.set(otherIndex, temporary)
    }

    void siftUp(Int index) {
        while index > 0 {
            Int parent = (index - 1) / 2
            if self._lessThan(self.heap.get(index), self.heap.get(parent)) {
                self.swap(index, parent)
                index = parent
            } else {
                break
            }
        }
    }

    void siftDown(Int index) {
        Int count = self.heap.length()
        while true {
            Int left = index * 2 + 1
            Int right = left + 1
            Int best = index
            if left < count && self._lessThan(self.heap.get(left), self.heap.get(best)) {
                best = left
            }
            if right < count && self._lessThan(self.heap.get(right), self.heap.get(best)) {
                best = right
            }
            if best == index {
                break
            }
            self.swap(index, best)
            index = best
        }
    }

    void push(T value) {
        self.heap.push(value)
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

    void clear() { self.heap = [] }
}
