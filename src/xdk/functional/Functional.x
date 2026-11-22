// xdk.functional — eager sequence pipelines, generators, and lazy values.
// Tier: L4；依赖：xdk.collections；稳定性：preview。
package xdk.functional
import xdk.collections

class Seq<T> {
    final List<T> _items

    Seq(List<T> items) {
        if items == null {
            throw "Seq: null items"
        }
        self._items = items.copy()
    }

    Int length() { return self._items.length() }
    Bool isEmpty() { return self._items.length() == 0 }
    T get(Int index) {
        if index < 0 || index >= self._items.length() {
            throw "Seq.get: index out of range"
        }
        return self._items.get(index)
    }

    Seq<T> map(T(T) transform) {
        List<T> result = []
        Int index = 0
        while index < self._items.length() {
            result.push(transform(self._items.get(index)))
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<String> mapToString(String(T) transform) {
        List<String> result = []
        Int index = 0
        while index < self._items.length() {
            result.push(transform(self._items.get(index)))
            index = index + 1
        }
        return new Seq<String>(result)
    }

    Seq<Int> mapToInt(Int(T) transform) {
        List<Int> result = []
        Int index = 0
        while index < self._items.length() {
            result.push(transform(self._items.get(index)))
            index = index + 1
        }
        return new Seq<Int>(result)
    }

    Seq<T> filter(Bool(T) predicate) {
        List<T> result = []
        Int index = 0
        while index < self._items.length() {
            T item = self._items.get(index)
            if predicate(item) { result.push(item) }
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> flatMap(List<T>(T) transform) {
        List<T> result = []
        Int index = 0
        while index < self._items.length() {
            List<T> part = transform(self._items.get(index))
            if part == null { throw "Seq.flatMap: null result" }
            Int inner = 0
            while inner < part.length() {
                result.push(part.get(inner))
                inner = inner + 1
            }
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> distinct() {
        List<T> result = []
        Int index = 0
        while index < self._items.length() {
            T item = self._items.get(index)
            Bool seen = false
            Int existing = 0
            while existing < result.length() {
                if item == result.get(existing) {
                    seen = true
                    break
                }
                existing = existing + 1
            }
            if !seen { result.push(item) }
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> sorted(Int(T, T) comparator) {
        List<T> result = self._items.copy()
        Int current = 1
        while current < result.length() {
            T value = result.get(current)
            Int previous = current - 1
            while previous >= 0 {
                if comparator(value, result.get(previous)) < 0 {
                    result.set(previous + 1, result.get(previous))
                    previous = previous - 1
                } else {
                    break
                }
            }
            result.set(previous + 1, value)
            current = current + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> reversed() {
        List<T> result = []
        Int index = self._items.length() - 1
        while index >= 0 {
            result.push(self._items.get(index))
            index = index - 1
        }
        return new Seq<T>(result)
    }

    Seq<T> take(Int count) {
        if count < 0 { throw "Seq.take: negative count" }
        List<T> result = []
        Int index = 0
        while index < self._items.length() && index < count {
            result.push(self._items.get(index))
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> skip(Int count) {
        if count < 0 { throw "Seq.skip: negative count" }
        List<T> result = []
        Int index = count
        while index < self._items.length() {
            result.push(self._items.get(index))
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> takeWhile(Bool(T) predicate) {
        List<T> result = []
        Int index = 0
        while index < self._items.length() {
            T item = self._items.get(index)
            if !predicate(item) { break }
            result.push(item)
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<T> dropWhile(Bool(T) predicate) {
        List<T> result = []
        Bool dropping = true
        Int index = 0
        while index < self._items.length() {
            T item = self._items.get(index)
            if dropping && predicate(item) {
                index = index + 1
                continue
            }
            dropping = false
            result.push(item)
            index = index + 1
        }
        return new Seq<T>(result)
    }

    Seq<List<T>> chunk(Int size) {
        if size <= 0 { throw "Seq.chunk: size must be positive" }
        List<List<T>> result = []
        Int index = 0
        while index < self._items.length() {
            List<T> block = []
            Int inner = 0
            while inner < size && index < self._items.length() {
                block.push(self._items.get(index))
                index = index + 1
                inner = inner + 1
            }
            result.push(block)
        }
        return new Seq<List<T>>(result)
    }

    Seq<List<T>> window(Int size) {
        if size <= 0 { throw "Seq.window: size must be positive" }
        List<List<T>> result = []
        if size > self._items.length() { return new Seq<List<T>>(result) }
        Int index = 0
        while index + size <= self._items.length() {
            List<T> block = []
            Int inner = 0
            while inner < size {
                block.push(self._items.get(index + inner))
                inner = inner + 1
            }
            result.push(block)
            index = index + 1
        }
        return new Seq<List<T>>(result)
    }

    Seq<Pair<T, T>> zip(Seq<T> other) {
        if other == null { throw "Seq.zip: null other" }
        List<Pair<T, T>> result = []
        Int limit = self._items.length()
        if other.length() < limit { limit = other.length() }
        Int index = 0
        while index < limit {
            result.push(new Pair<T, T>(self._items.get(index), other.get(index)))
            index = index + 1
        }
        return new Seq<Pair<T, T>>(result)
    }

    Map<String, List<T>> groupBy(String(T) keySelector) {
        Map<String, List<T>> result = [:]
        Int index = 0
        while index < self._items.length() {
            T item = self._items.get(index)
            String key = keySelector(item)
            if key == null { throw "Seq.groupBy: null key" }
            List<T> empty = []
            List<T> bucket = result.getOr(key, empty)
            bucket.push(item)
            result.put(key, bucket)
            index = index + 1
        }
        return result
    }

    Pair<List<T>, List<T>> partition(Bool(T) predicate) {
        List<T> yes = []
        List<T> no = []
        Int index = 0
        while index < self._items.length() {
            T item = self._items.get(index)
            if predicate(item) { yes.push(item) } else { no.push(item) }
            index = index + 1
        }
        return new Pair<List<T>, List<T>>(yes, no)
    }

    Void forEach(Void(T) action) {
        Int index = 0
        while index < self._items.length() {
            action(self._items.get(index))
            index = index + 1
        }
    }

    T reduce(T initial, T(T, T) accumulator) {
        T result = initial
        Int index = 0
        while index < self._items.length() {
            result = accumulator(result, self._items.get(index))
            index = index + 1
        }
        return result
    }

    Bool anyMatch(Bool(T) predicate) {
        Int index = 0
        while index < self._items.length() {
            if predicate(self._items.get(index)) { return true }
            index = index + 1
        }
        return false
    }

    Bool allMatch(Bool(T) predicate) {
        Int index = 0
        while index < self._items.length() {
            if !predicate(self._items.get(index)) { return false }
            index = index + 1
        }
        return true
    }

    Bool noneMatch(Bool(T) predicate) {
        return !self.anyMatch(predicate)
    }

    T? firstOrNull() {
        if self._items.length() == 0 { return null }
        return self._items.get(0)
    }

    Int count(Bool(T) predicate) {
        Int total = 0
        Int index = 0
        while index < self._items.length() {
            if predicate(self._items.get(index)) { total = total + 1 }
            index = index + 1
        }
        return total
    }

    List<T> toList() { return self._items.copy() }

    Set<T> toSet() {
        Set<T> result = []
        Int index = 0
        while index < self._items.length() {
            result.add(self._items.get(index))
            index = index + 1
        }
        return result
    }

    String join(String separator, String(T) stringify) {
        String result = ""
        Int index = 0
        while index < self._items.length() {
            if index > 0 { result = result + separator }
            result = result + stringify(self._items.get(index))
            index = index + 1
        }
        return result
    }
}


class Sequences {
    static List<Int> range(Int start, Int endExclusive) {
        List<Int> result = []
        Int value = start
        while value < endExclusive { result.push(value); value = value + 1 }
        return result
    }
    static List<Int> rangeStep(Int start, Int endExclusive, Int step) {
        if step == 0 { throw "Sequences.rangeStep: step must not be zero" }
        List<Int> result = []
        Int value = start
        if step > 0 { while value < endExclusive { result.push(value); value = value + step } }
        else { while value > endExclusive { result.push(value); value = value + step } }
        return result
    }
    static List<Int> repeatValue(Int value, Int count) {
        if count < 0 { throw "Sequences.repeatValue: negative count" }
        List<Int> result = []
        Int index = 0
        while index < count { result.push(value); index = index + 1 }
        return result
    }
    static List<Int> generate(Int count, Int() supplier) {
        List<Int> result = []
        Int index = 0
        while index < count { result.push(supplier()); index = index + 1 }
        return result
    }
    static List<Int> iterate(Int seed, Int count, Int(Int) next) {
        List<Int> result = []
        Int value = seed
        Int index = 0
        while index < count { result.push(value); value = next(value); index = index + 1 }
        return result
    }
    static List<Int> concat(List<Int> left, List<Int> right) {
        if left == null || right == null { throw "Sequences.concat: null list" }
        List<Int> result = left.copy()
        Int index = 0
        while index < right.length() { result.push(right.get(index)); index = index + 1 }
        return result
    }
    static List<Int> flatten(List<List<Int>> nested) {
        if nested == null { throw "Sequences.flatten: null input" }
        List<Int> result = []
        Int index = 0
        while index < nested.length() {
            List<Int> inner = nested.get(index)
            Int innerIndex = 0
            while innerIndex < inner.length() { result.push(inner.get(innerIndex)); innerIndex = innerIndex + 1 }
            index = index + 1
        }
        return result
    }
    static List<Int> fromNullable(Int? value) {
        List<Int> result = []
        if value != null { result.push(value) }
        return result
    }
}
