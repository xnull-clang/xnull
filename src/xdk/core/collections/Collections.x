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
List<T> sortedBy<T>(List<T> items, Bool(T, T) lessThan) {
    List<T> result = []
    Int index = 0
    while index < items.length() {
        result.push(items.get(index))
        index = index + 1
    }
    return sortBy(result, lessThan)
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

// IntPair：Map<Int,Int>.entries 的值对象。
class IntPair {
    Int first
    Int second

    IntPair(Int first, Int second) {
        self.first = first
        self.second = second
    }
}
