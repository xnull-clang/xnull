// xdk.collections —— T0 专用容器
package xdk.collections

// RingBuffer<T>：固定容量环形缓冲（首版用 List 承载，容量语义不变）。
class RingBuffer<T> {
    final Int _capacity
    List<T> data = []

    RingBuffer(Int capacity) {
        if capacity <= 0 {
            throw "RingBuffer: capacity must be positive"
        }
        self._capacity = capacity
    }

    Int length() { return self.data.length() }

    Int capacity() { return self._capacity }

    Bool isEmpty() { return self.data.length() == 0 }

    Bool isFull() { return self.data.length() >= self._capacity }

    Bool push(T value) {
        if self.isFull() {
            return false
        }
        self.data.push(value)
        return true
    }

    T? pop() {
        if self.isEmpty() {
            return null
        }
        T value = self.data.get(0)
        self.data.remove(0)
        return value
    }

    T? peek() {
        if self.isEmpty() {
            return null
        }
        return self.data.get(0)
    }

    void clear() { self.data = [] }
}
