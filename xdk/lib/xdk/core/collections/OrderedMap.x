// xdk.collections —— S6-07 源码单元（算法 + 4 个特化容器）
// 设计口径：
//   - 算法用比较/相等/键提取回调表达，不要求 T 可比较；
//   - 容器为纯 XNull 值类型封装（内部用 List），语义优先、复杂度为首版实现；
//   - 不改变内建容器语义（S1 §9）。
package xdk.collections
// sortBy：按 less(a,b) 升序插入排序，原地修改并返回。



































































































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
