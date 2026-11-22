// Tier: T0；依赖：xdk.errors；稳定性：preview。
// xdk.collections —— T0 算法面（List / Map<String,Int> / Set<Int>）。
// 设计口径：
//   - 算法用比较/相等/键提取回调表达，不要求 T 可比较；
//   - 首版以语义正确为先，排序用稳定插入排序；
//   - 不改变内建容器语义（S1 §9）。
package xdk.collections

// sortBy：按 lessThan 升序插入排序，原地修改并返回同一列表。
List<T> sortBy<T>(List<T> items, Bool(T, T) lessThan) {
    Int index = 1
    while index < items.length() {
        T value = items.get(index)
        Int previous = index - 1
        while previous >= 0 {
            if lessThan(value, items.get(previous)) {
                items.set(previous + 1, items.get(previous))
                previous = previous - 1
            } else {
                break
            }
        }
        items.set(previous + 1, value)
        index = index + 1
    }
    return items
}

// sortedBy：返回新列表，不修改入参。
// 内联排序循环：mini 暂不支持在泛型函数体内调用另一个泛型函数。
List<T> sortedBy<T>(List<T> items, Bool(T, T) lessThan) {
    List<T> result = []
    Int index = 0
    while index < items.length() {
        result.push(items.get(index))
        index = index + 1
    }
    Int current = 1
    while current < result.length() {
        T value = result.get(current)
        Int previous = current - 1
        while previous >= 0 {
            if lessThan(value, result.get(previous)) {
                result.set(previous + 1, result.get(previous))
                previous = previous - 1
            } else {
                break
            }
        }
        result.set(previous + 1, value)
        current = current + 1
    }
    return result
}

// dedup：按 equals 去重，保留首次出现顺序。
List<T> dedup<T>(List<T> items, Bool(T, T) equals) {
    List<T> result = []
    for item in items {
        Bool seen = false
        for existing in result {
            if equals(item, existing) {
                seen = true
                break
            }
        }
        if !seen {
            result.push(item)
        }
    }
    return result
}

// find：返回首个满足 predicate 的元素；不存在返回 null。
T? find<T>(List<T> items, Bool(T) predicate) {
    for item in items {
        if predicate(item) {
            return item
        }
    }
    return null
}

// joinWith：用 separator 拼接任意 List<T>，元素由 format 转成文本。
String joinWith<T>(List<T> items, String separator, String(T) format) {
    String result = ""
    Int index = 0
    while index < items.length() {
        if index > 0 {
            result = result + separator
        }
        result = result + format(items.get(index))
        index = index + 1
    }
    return result
}

// groupByInt：按 Int 键分组，保留首次出现顺序和组内原始顺序。
Map<Int,List<T>> groupByInt<T>(List<T> items, Int(T) keyOf) {
    Map<Int,List<T>> result = [:]
    for item in items {
        Int key = keyOf(item)
        if result.has(key) {
            List<T> bucket = result.getOr(key, items)
            bucket.push(item)
        } else {
            List<T> bucket = []
            bucket.push(item)
            result.put(key, bucket)
        }
    }
    return result
}

// groupBy：按任意受支持 K 分组；组内与组间均按首次出现顺序。
Map<K,List<T>> groupBy<T, K>(List<T> items, K(T) keyOf) {
    Map<K,List<T>> result = [:]
    for item in items {
        K key = keyOf(item)
        if result.has(key) {
            List<T> bucket = result.getOr(key, items)
            bucket.push(item)
        } else {
            List<T> bucket = []
            bucket.push(item)
            result.put(key, bucket)
        }
    }
    return result
}

// join：用 separator 拼接 List<String>；空列表返回空串。
String join(List<String> items, String separator) {
    String result = ""
    Int index = 0
    while index < items.length() {
        if index > 0 {
            result = result + separator
        }
        result = result + items.get(index)
        index = index + 1
    }
    return result
}

// Pair：Map<String,Int>.entries 的值对象。
class Pair {
    String first
    Int second

    Pair(String first, Int second) {
        self.first = first
        self.second = second
    }
}

// Pair<A,B>：2.x 泛型二元组（值语义）。
// 1.x 的固定 Pair 保留在上方作为兼容适配；两者使用不同形态：
//   - 固定 Pair：公共字段 first/second（Map<String,Int>.entries）；
//   - 泛型 Pair：私有字段 + first()/second()/with*/equals/toString。
class Pair<A, B> {
    final A _first
    final B _second

    Pair(A first, B second) {
        self._first = first
        self._second = second
    }

    A first() {
        return self._first
    }

    B second() {
        return self._second
    }

    Pair<A, B> withFirst(A value) {
        return new Pair<A, B>(value, self._second)
    }

    Pair<A, B> withSecond(B value) {
        return new Pair<A, B>(self._first, value)
    }

    Bool equals(Pair<A, B> other) {
        if other == null {
            return false
        }
        return self._first == other._first && self._second == other._second
    }

    String toString() {
        return "(" + str(self._first) + ", " + str(self._second) + ")"
    }
}

// IntPair：Map<Int,Int>.entries 的值对象。
class IntPair {
    Int first
    Int second

    IntPair(Int first, Int second) {
        self.first = first
        self.second = second
    }
}

// Entry<K,V>：通用 Map<K,V>.entries 的值对象。
// 快速路径 Map<String,Int>/Map<Int,Int> 仍分别返回 Pair/IntPair。
class Entry<K, V> {
    K key
    V value

    Entry(K key, V value) {
        self.key = key
        self.value = value
    }
}
