package xdk.cache
import xdk.errors
import xdk.runtime

enum EvictionReason {
    Capacity,
    Expired,
    Replaced,
    Explicit,
    Closed,
}

String evictionReasonName(EvictionReason reason) {
    if reason == EvictionReason.Capacity { return "capacity" }
    if reason == EvictionReason.Expired { return "expired" }
    if reason == EvictionReason.Replaced { return "replaced" }
    if reason == EvictionReason.Explicit { return "explicit" }
    return "closed"
}

class CacheOptions {
    Int _maxEntries
    Long _maxWeight
    Long _defaultTtlMillis
    Bool _recordStats

    CacheOptions() {
        self._maxEntries = 1024
        self._maxWeight = 1048576
        self._defaultTtlMillis = 0
        self._recordStats = true
    }

    CacheOptions maxEntries(Int value) {
        if value < 1 { throw "CacheOptions.maxEntries: < 1" }
        self._maxEntries = value
        return self
    }

    CacheOptions maxWeight(Long value) {
        if value < 1 { throw "CacheOptions.maxWeight: < 1" }
        self._maxWeight = value
        return self
    }

    CacheOptions defaultTtlMillis(Long value) {
        if value < 0 { throw "CacheOptions.defaultTtlMillis: negative" }
        self._defaultTtlMillis = value
        return self
    }

    CacheOptions recordStats(Bool value) {
        self._recordStats = value
        return self
    }

    Int getMaxEntries() { return self._maxEntries }
    Long getMaxWeight() { return self._maxWeight }
    Long getDefaultTtlMillis() { return self._defaultTtlMillis }
    Bool isRecordStats() { return self._recordStats }

    CacheOptions copy() {
        CacheOptions result = new CacheOptions()
        result._maxEntries = self._maxEntries
        result._maxWeight = self._maxWeight
        result._defaultTtlMillis = self._defaultTtlMillis
        result._recordStats = self._recordStats
        return result
    }

    String describe() {
        return "CacheOptions(maxEntries=" + str(self._maxEntries) + " maxWeight=" + str(self._maxWeight) +
            " defaultTtlMillis=" + str(self._defaultTtlMillis) + " recordStats=" + str(self._recordStats) + ")"
    }
}

class CacheStats {
    final Long _hits
    final Long _misses
    final Long _loads
    final Long _loadFailures
    final Long _evictions
    final Long _expirations
    final Int _size
    final Long _weight

    CacheStats(Long hits, Long misses, Long loads, Long loadFailures,
               Long evictions, Long expirations, Int size, Long weight) {
        if hits < 0 || misses < 0 || loads < 0 || loadFailures < 0 {
            throw "CacheStats: negative counter"
        }
        if evictions < 0 || expirations < 0 || size < 0 || weight < 0 {
            throw "CacheStats: negative value"
        }
        self._hits = hits
        self._misses = misses
        self._loads = loads
        self._loadFailures = loadFailures
        self._evictions = evictions
        self._expirations = expirations
        self._size = size
        self._weight = weight
    }

    Long hits() { return self._hits }
    Long misses() { return self._misses }
    Long loads() { return self._loads }
    Long loadFailures() { return self._loadFailures }
    Long evictions() { return self._evictions }
    Long expirations() { return self._expirations }
    Int size() { return self._size }
    Long weight() { return self._weight }

    Double hitRate() {
        Long total = self._hits + self._misses
        if total == 0 { return 0.0 }
        return (self._hits as Double) / (total as Double)
    }

    Double missRate() {
        Long total = self._hits + self._misses
        if total == 0 { return 0.0 }
        return (self._misses as Double) / (total as Double)
    }

    Double loadFailureRate() {
        Long total = self._loads + self._loadFailures
        if total == 0 { return 0.0 }
        return (self._loadFailures as Double) / (total as Double)
    }

    CacheStats copy() {
        return new CacheStats(self._hits, self._misses, self._loads, self._loadFailures,
            self._evictions, self._expirations, self._size, self._weight)
    }

    Bool equals(CacheStats other) {
        if other == null { return false }
        return self._hits == other.hits() && self._misses == other.misses() &&
            self._loads == other.loads() && self._loadFailures == other.loadFailures() &&
            self._evictions == other.evictions() && self._expirations == other.expirations() &&
            self._size == other.size() && self._weight == other.weight()
    }

    String describe() {
        return "CacheStats(hits=" + str(self._hits) + " misses=" + str(self._misses) +
            " loads=" + str(self._loads) + " loadFailures=" + str(self._loadFailures) +
            " evictions=" + str(self._evictions) + " expirations=" + str(self._expirations) +
            " size=" + str(self._size) + " weight=" + str(self._weight) + ")"
    }

    String toString() { return self.describe() }
}

class Cache<K, V> {
    final CacheOptions _options
    final void(K, V, EvictionReason) _listener
    final Bool _hasListener
    final RuntimeMonitor _monitor
    final List<K> _order
    final List<V> _values
    final List<Long> _expiries
    final List<Long> _weights
    Long _weight
    Long _hits
    Long _misses
    Long _loads
    Long _loadFailures
    Long _evictions
    Long _expirations
    Bool _closed

    Cache(CacheOptions options) {
        if options == null { throw "Cache: null options" }
        self._options = options.copy()
        self._hasListener = false
        self._monitor = new RuntimeMonitor()
        self._order = []
        self._values = []
        self._expiries = []
        self._weights = []
        self._weight = 0
        self._hits = 0
        self._misses = 0
        self._loads = 0
        self._loadFailures = 0
        self._evictions = 0
        self._expirations = 0
        self._closed = false
    }

    Cache(CacheOptions options, void(K, V, EvictionReason) listener) {
        if options == null { throw "Cache: null options" }
        self._options = options.copy()
        self._listener = listener
        self._hasListener = true
        self._monitor = new RuntimeMonitor()
        self._order = []
        self._values = []
        self._expiries = []
        self._weights = []
        self._weight = 0
        self._hits = 0
        self._misses = 0
        self._loads = 0
        self._loadFailures = 0
        self._evictions = 0
        self._expirations = 0
        self._closed = false
    }

    Int _orderIndex(K key) {
        Int index = 0
        while index < self._order.length() {
            if self._order.get(index) == key { return index }
            index = index + 1
        }
        return -1
    }

    Void _touch(K key) {
        Int index = self._orderIndex(key)
        if index < 0 { return }
        V value = self._values.get(index)
        Long weight = self._weights.get(index)
        Long expiry = self._expiries.get(index)
        self._order.remove(index)
        self._values.remove(index)
        self._weights.remove(index)
        self._expiries.remove(index)
        self._order.push(key)
        self._values.push(value)
        self._weights.push(weight)
        self._expiries.push(expiry)
    }

    Bool _expired(K key) {
        Int index = self._orderIndex(key)
        if index < 0 { return false }
        Long deadline = self._expiries.get(index)
        return deadline > 0 && nowMono() >= deadline
    }

    Void _removeLocked(K key, EvictionReason reason, List<K> eventKeys, List<V> eventValues, List<EvictionReason> eventReasons) {
        Int index = self._orderIndex(key)
        if index < 0 { return }
        V value = self._values.get(index)
        Long itemWeight = self._weights.get(index)
        self._order.remove(index)
        self._values.remove(index)
        self._weights.remove(index)
        self._expiries.remove(index)
        self._weight = self._weight - itemWeight
        eventKeys.push(key)
        eventValues.push(value)
        eventReasons.push(reason)
        if reason != EvictionReason.Replaced {
            self._evictions = self._evictions + 1
        }
        if reason == EvictionReason.Expired {
            self._expirations = self._expirations + 1
        }
    }

    Void _cleanupLocked(List<K> eventKeys, List<V> eventValues, List<EvictionReason> eventReasons) {
        List<K> expiredKeys = []
        Int index = 0
        while index < self._order.length() {
            K key = self._order.get(index)
            if self._expired(key) { expiredKeys.push(key) }
            index = index + 1
        }
        index = 0
        while index < expiredKeys.length() {
            self._removeLocked(expiredKeys.get(index), EvictionReason.Expired, eventKeys, eventValues, eventReasons)
            index = index + 1
        }
    }

    Void _evictLocked(List<K> eventKeys, List<V> eventValues, List<EvictionReason> eventReasons) {
        while self._order.length() > self._options.getMaxEntries() || self._weight > self._options.getMaxWeight() {
            if self._order.length() == 0 { break }
            K key = self._order.get(0)
            self._removeLocked(key, EvictionReason.Capacity, eventKeys, eventValues, eventReasons)
        }
    }

    Void _flush(List<K> eventKeys, List<V> eventValues, List<EvictionReason> eventReasons) {
        if !self._hasListener { return }
        Int index = 0
        while index < eventKeys.length() {
            self._listener(eventKeys.get(index), eventValues.get(index), eventReasons.get(index))
            index = index + 1
        }
    }

    Void _putLocked(K key, V value, Long weight, Long ttlMillis, List<K> eventKeys, List<V> eventValues, List<EvictionReason> eventReasons) {
        if self._orderIndex(key) >= 0 {
            self._removeLocked(key, EvictionReason.Replaced, eventKeys, eventValues, eventReasons)
        }
        Long ttl = ttlMillis
        if ttl == 0 { ttl = self._options.getDefaultTtlMillis() }
        Long expiry = 0
        if ttl > 0 { expiry = nowMono() + ttl }
        self._order.push(key)
        self._values.push(value)
        self._weights.push(weight)
        self._expiries.push(expiry)
        self._weight = self._weight + weight
        self._evictLocked(eventKeys, eventValues, eventReasons)
    }

    V? get(K key) {
        if key == null { throw "Cache.get: null key" }
        List<K> eventKeys = []
        List<V> eventValues = []
        List<EvictionReason> eventReasons = []
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return null
        }
        self._cleanupLocked(eventKeys, eventValues, eventReasons)
        V? result = null
        Int found = self._orderIndex(key)
        if found >= 0 {
            result = self._values.get(found)
            self._touch(key)
            if self._options.isRecordStats() { self._hits = self._hits + 1 }
        } else {
            if self._options.isRecordStats() { self._misses = self._misses + 1 }
        }
        self._monitor.exit()
        self._flush(eventKeys, eventValues, eventReasons)
        return result
    }

    Result<V, Error> getOrLoad(K key, Result<V, Error>(K) loader) {
        if key == null { throw "Cache.getOrLoad: null key" }
        self._monitor.enter()
        Bool closed = self._closed
        self._monitor.exit()
        if closed { return Err(new BasicError(ErrorKind.Unavailable, "cache is closed")) }
        if self.contains(key) {
            return Ok(self.get(key))
        }
        Result<V, Error> loaded = loader(key)
        if loaded.isErr() {
            self._monitor.enter()
            if self._options.isRecordStats() { self._loadFailures = self._loadFailures + 1 }
            self._monitor.exit()
            return loaded
        }
        self._monitor.enter()
        Bool closedAfterLoad = self._closed
        if self._options.isRecordStats() { self._loads = self._loads + 1 }
        self._monitor.exit()
        if closedAfterLoad { return Err(new BasicError(ErrorKind.Unavailable, "cache is closed")) }
        V value = loaded.value()
        self.put(key, value)
        return loaded
    }

    V? put(K key, V value) {
        return self.putWithTtl(key, value, 0)
    }

    V? putIfAbsent(K key, V value) {
        if key == null || value == null { throw "Cache.putIfAbsent: null argument" }
        List<K> eventKeys = []
        List<V> eventValues = []
        List<EvictionReason> eventReasons = []
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return null
        }
        self._cleanupLocked(eventKeys, eventValues, eventReasons)
        V? existing = null
        Int found = self._orderIndex(key)
        if found >= 0 {
            existing = self._values.get(found)
        } else {
            self._putLocked(key, value, 1, 0, eventKeys, eventValues, eventReasons)
        }
        self._monitor.exit()
        self._flush(eventKeys, eventValues, eventReasons)
        return existing
    }

    V? putWithTtl(K key, V value, Long ttlMillis) {
        if key == null || value == null { throw "Cache.put: null argument" }
        if ttlMillis < 0 { throw "Cache.putWithTtl: negative ttl" }
        return self.putWeighted(key, value, 1, ttlMillis)
    }

    V? putWeighted(K key, V value, Long weight, Long ttlMillis) {
        if key == null || value == null { throw "Cache.putWeighted: null argument" }
        if weight < 1 { throw "Cache.putWeighted: weight < 1" }
        if ttlMillis < 0 { throw "Cache.putWeighted: negative ttl" }
        List<K> eventKeys = []
        List<V> eventValues = []
        List<EvictionReason> eventReasons = []
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return null
        }
        self._cleanupLocked(eventKeys, eventValues, eventReasons)
        V? old = null
        Int found = self._orderIndex(key)
        if found >= 0 { old = self._values.get(found) }
        self._putLocked(key, value, weight, ttlMillis, eventKeys, eventValues, eventReasons)
        self._monitor.exit()
        self._flush(eventKeys, eventValues, eventReasons)
        return old
    }

    Bool invalidate(K key) {
        if key == null { throw "Cache.invalidate: null key" }
        List<K> eventKeys = []
        List<V> eventValues = []
        List<EvictionReason> eventReasons = []
        self._monitor.enter()
        Bool present = self._orderIndex(key) >= 0
        if present { self._removeLocked(key, EvictionReason.Explicit, eventKeys, eventValues, eventReasons) }
        self._monitor.exit()
        self._flush(eventKeys, eventValues, eventReasons)
        return present
    }

    Void invalidateAll() {
        List<K> eventKeys = []
        List<V> eventValues = []
        List<EvictionReason> eventReasons = []
        self._monitor.enter()
        List<K> keys = self._order.copy()
        Int index = 0
        while index < keys.length() {
            self._removeLocked(keys.get(index), EvictionReason.Explicit, eventKeys, eventValues, eventReasons)
            index = index + 1
        }
        self._monitor.exit()
        self._flush(eventKeys, eventValues, eventReasons)
    }

    Int cleanup() {
        List<K> eventKeys = []
        List<V> eventValues = []
        List<EvictionReason> eventReasons = []
        self._monitor.enter()
        Int before = self._order.length()
        self._cleanupLocked(eventKeys, eventValues, eventReasons)
        Int removed = before - self._order.length()
        self._monitor.exit()
        self._flush(eventKeys, eventValues, eventReasons)
        return removed
    }

    Bool contains(K key) {
        if key == null { throw "Cache.contains: null key" }
        List<K> eventKeys = []
        List<V> eventValues = []
        List<EvictionReason> eventReasons = []
        self._monitor.enter()
        self._cleanupLocked(eventKeys, eventValues, eventReasons)
        Bool result = self._orderIndex(key) >= 0
        self._monitor.exit()
        self._flush(eventKeys, eventValues, eventReasons)
        return result
    }

    Int size() {
        self._monitor.enter()
        Int result = self._order.length()
        self._monitor.exit()
        return result
    }

    Long weight() {
        self._monitor.enter()
        Long result = self._weight
        self._monitor.exit()
        return result
    }

    List<K> keys() {
        self._monitor.enter()
        List<K> result = self._order.copy()
        self._monitor.exit()
        return result
    }

    List<V> values() {
        self._monitor.enter()
        List<V> result = []
        Int index = 0
        while index < self._order.length() {
            K key = self._order.get(index)
            result.push(self._values.get(index))
            index = index + 1
        }
        self._monitor.exit()
        return result
    }

    Map<K, V> entries() {
        self._monitor.enter()
        Map<K, V> result = [:]
        Int index = 0
        while index < self._order.length() {
            K key = self._order.get(index)
            result.put(key, self._values.get(index))
            index = index + 1
        }
        self._monitor.exit()
        return result
    }

    CacheStats stats() {
        List<K> eventKeys = []
        List<V> eventValues = []
        List<EvictionReason> eventReasons = []
        self._monitor.enter()
        self._cleanupLocked(eventKeys, eventValues, eventReasons)
        CacheStats result = new CacheStats(self._hits, self._misses, self._loads, self._loadFailures,
            self._evictions, self._expirations, self._order.length(), self._weight)
        self._monitor.exit()
        self._flush(eventKeys, eventValues, eventReasons)
        return result
    }

    Void resetStats() {
        self._monitor.enter()
        self._hits = 0
        self._misses = 0
        self._loads = 0
        self._loadFailures = 0
        self._evictions = 0
        self._expirations = 0
        self._monitor.exit()
    }

    CacheOptions options() { return self._options.copy() }
    Bool isClosed() { return self._closed }

    Void close() {
        List<K> eventKeys = []
        List<V> eventValues = []
        List<EvictionReason> eventReasons = []
        self._monitor.enter()
        if self._closed {
            self._monitor.exit()
            return
        }
        self._closed = true
        List<K> keys = self._order.copy()
        Int index = 0
        while index < keys.length() {
            self._removeLocked(keys.get(index), EvictionReason.Closed, eventKeys, eventValues, eventReasons)
            index = index + 1
        }
        self._monitor.exit()
        self._flush(eventKeys, eventValues, eventReasons)
    }
}
