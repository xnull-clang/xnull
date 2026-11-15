// xdk.collections —— S6-07 源码单元（算法 + 4 个特化容器）
// 设计口径：
//   - 算法用比较/相等/键提取回调表达，不要求 T 可比较；
//   - 容器为纯 XNull 值类型封装（内部用 List），语义优先、复杂度为首版实现；
//   - 不改变内建容器语义（S1 §9）。
package xdk.collections
// sortBy：按 less(a,b) 升序插入排序，原地修改并返回。



























































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
