// xdk.collections —— S6-07 源码单元（算法 + 4 个特化容器）
// 设计口径：
//   - 算法用比较/相等/键提取回调表达，不要求 T 可比较；
//   - 容器为纯 XNull 值类型封装（内部用 List），语义优先、复杂度为首版实现；
//   - 不改变内建容器语义（S1 §9）。
package xdk.collections
// sortBy：按 less(a,b) 升序插入排序，原地修改并返回。





















































































































































































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

    V? put(Int k, V v) {
        Int i = self.lowerBound(k)
        if i < self.keys.length() && self.keys.get(i) == k {
            V old = self.vals.get(i)
            self.vals.set(i, v)
            return old
        }
        self.keys.insert(i, k)
        self.vals.insert(i, v)
        return null
    }

    V? get(Int k) {
        Int i = self.lowerBound(k)
        if i >= self.keys.length() || self.keys.get(i) != k {
            return null
        }
        return self.vals.get(i)
    }

    V getOr(Int k, V fallback) {
        Int i = self.lowerBound(k)
        if i >= self.keys.length() || self.keys.get(i) != k {
            return fallback
        }
        return self.vals.get(i)
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

    List<Int> keys() {
        List<Int> res = []
        Int i = 0
        while i < self.keys.length() {
            res.push(self.keys.get(i))
            i = i + 1
        }
        return res
    }

    List<V> values() {
        List<V> res = []
        Int i = 0
        while i < self.vals.length() {
            res.push(self.vals.get(i))
            i = i + 1
        }
        return res
    }

    void clear() {
        self.keys.clear()
        self.vals.clear()
    }
}
