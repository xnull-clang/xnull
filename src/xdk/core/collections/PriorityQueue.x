// xdk.collections —— S6-07 源码单元（算法 + 4 个特化容器）
// 设计口径：
//   - 算法用比较/相等/键提取回调表达，不要求 T 可比较；
//   - 容器为纯 XNull 值类型封装（内部用 List），语义优先、复杂度为首版实现；
//   - 不改变内建容器语义（S1 §9）。
package xdk.collections
// sortBy：按 less(a,b) 升序插入排序，原地修改并返回。



































































































































































































































































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
