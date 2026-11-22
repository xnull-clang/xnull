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

    static Seq<R> of<R>(List<R> items) {
        return new Seq<R>(items)
    }

    static Seq<R> empty<R>() {
        List<R> emptyItems = []
        return new Seq<R>(emptyItems)
    }

    Int length() { return self._items.length() }
    Bool isEmpty() { return self._items.length() == 0 }
    T get(Int index) {
        if index < 0 || index >= self._items.length() {
            throw "Seq.get: index out of range"
        }
        return self._items.get(index)
    }

    Seq<R> map<R>(R(T) transform) {
        List<R> result = []
        Int index = 0
        while index < self._items.length() {
            result.push(transform(self._items.get(index)))
            index = index + 1
        }
        return new Seq<R>(result)
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

    Seq<R> flatMap<R>(List<R>(T) transform) {
        List<R> result = []
        Int index = 0
        while index < self._items.length() {
            List<R> part = transform(self._items.get(index))
            if part == null { throw "Seq.flatMap: null result" }
            Int inner = 0
            while inner < part.length() {
                result.push(part.get(inner))
                inner = inner + 1
            }
            index = index + 1
        }
        return new Seq<R>(result)
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

    Seq<Pair<T, R>> zip<R>(Seq<R> other) {
        List<Pair<T, R>> result = []
        Int limit = self._items.length()
        if other.length() < limit { limit = other.length() }
        Int index = 0
        while index < limit {
            result.push(new Pair<T, R>(self._items.get(index), other.get(index)))
            index = index + 1
        }
        return new Seq<Pair<T, R>>(result)
    }

    Map<K, List<T>> groupBy<K>(K(T) keySelector) {
        Map<K, List<T>> result = [:]
        Int index = 0
        while index < self._items.length() {
            T item = self._items.get(index)
            K key = keySelector(item)
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
    static Seq<Int> range(Int start, Int endExclusive) {
        List<Int> result = []
        Int value = start
        while value < endExclusive { result.push(value); value = value + 1 }
        return new Seq<Int>(result)
    }

    static Seq<Int> rangeStep(Int start, Int endExclusive, Int step) {
        if step == 0 { throw "Sequences.rangeStep: step must not be zero" }
        List<Int> result = []
        Int value = start
        if step > 0 {
            while value < endExclusive { result.push(value); value = value + step }
        } else {
            while value > endExclusive { result.push(value); value = value + step }
        }
        return new Seq<Int>(result)
    }

    static Seq<T> repeatValue<T>(T value, Int count) {
        if count < 0 { throw "Sequences.repeatValue: negative count" }
        List<T> result = []
        Int index = 0
        while index < count { result.push(value); index = index + 1 }
        return new Seq<T>(result)
    }

    static Seq<T> generate<T>(Int count, T() supplier) {
        if count < 0 { throw "Sequences.generate: negative count" }
        List<T> result = []
        Int index = 0
        while index < count { result.push(supplier()); index = index + 1 }
        return new Seq<T>(result)
    }

    static Seq<T> iterate<T>(T seed, Int count, T(T) next) {
        if count < 0 { throw "Sequences.iterate: negative count" }
        List<T> result = []
        T value = seed
        Int index = 0
        while index < count { result.push(value); value = next(value); index = index + 1 }
        return new Seq<T>(result)
    }

    static Seq<T> concat<T>(Seq<T> left, Seq<T> right) {
        if left == null || right == null { throw "Sequences.concat: null sequence" }
        List<T> result = []
        Int index = 0
        while index < left.length() { result.push(left.get(index)); index = index + 1 }
        index = 0
        while index < right.length() { result.push(right.get(index)); index = index + 1 }
        return new Seq<T>(result)
    }

    static Seq<T> flatten<T>(List<List<T>> nested) {
        if nested == null { throw "Sequences.flatten: null input" }
        List<T> result = []
        Int index = 0
        while index < nested.length() {
            List<T> inner = nested.get(index)
            if inner == null { throw "Sequences.flatten: null inner list" }
            Int innerIndex = 0
            while innerIndex < inner.length() { result.push(inner.get(innerIndex)); innerIndex = innerIndex + 1 }
            index = index + 1
        }
        return new Seq<T>(result)
    }

    static Seq<T> fromNullable<T>(T? value) {
        List<T> result = []
        if value != null { result.push(value) }
        return new Seq<T>(result)
    }
}

class Lazy<T> {
    final T() _supplier
    final List<T> _cache
    Bool _computing

    Lazy(T() supplier) {
        self._supplier = supplier
        self._cache = []
        self._computing = false
    }

    static Lazy<R> ready<R>(R value) {
        Lazy<R> result = new Lazy<R>(() -> value)
        result._cache.push(value)
        return result
    }

    T get() {
        if self._cache.length() > 0 { return self._cache.get(0) }
        if self._computing { throw "Lazy.get: recursive evaluation" }
        self._computing = true
        T computed = self._supplier()
        self._cache.push(computed)
        self._computing = false
        return computed
    }

    Bool isInitialized() { return self._cache.length() > 0 }

    Lazy<R> map<R>(R(T) transform) {
        return new Lazy<R>(() -> transform(self.get()))
    }

    String toString() {
        if self._cache.length() > 0 { return "Lazy(initialized=true)" }
        return "Lazy(initialized=false)"
    }
}
