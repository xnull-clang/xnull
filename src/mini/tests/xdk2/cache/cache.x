package xdk2.cache
import xdk.cache
import xdk.errors
import xdk.tasks
import xdk.time

static Bool hasReason(List<String> reasons, String wanted) {
    Int index = 0
    while index < reasons.length() {
        if reasons.get(index) == wanted { return true }
        index = index + 1
    }
    return false
}

static Int main() {
    CacheOptions options = new CacheOptions()
    options.maxEntries(2)
    Cache<String, Int> cache = new Cache<String, Int>(options)
    print("put-a=" + str(cache.put("a", 1) == null))
    print("put-b=" + str(cache.put("b", 2) == null))
    print("get-a=" + str(cache.get("a")))
    cache.put("c", 3)
    print("lru=" + str(cache.contains("b")) + "," + str(cache.size()) + "," + cache.keys().get(0) + "," + cache.keys().get(1))
    print("values=" + str(cache.values().length()) + "," + str(cache.entries().keys().length()))

    CacheOptions ttlOptions = new CacheOptions()
    ttlOptions.maxEntries(4).defaultTtlMillis(20)
    Cache<String, Int> ttl = new Cache<String, Int>(ttlOptions)
    ttl.put("x", 1)
    sleepMs(40)
    print("ttl-get=" + str(ttl.get("x") == null))
    ttl.put("y", 2)
    sleepMs(40)
    print("ttl-cleanup=" + str(ttl.cleanup()))
    CacheOptions overrideOptions = new CacheOptions()
    overrideOptions.defaultTtlMillis(0)
    Cache<String, Int> override = new Cache<String, Int>(overrideOptions)
    override.putWithTtl("z", 3, 10)
    sleepMs(20)
    print("ttl-override=" + str(override.cleanup()))

    CacheOptions weightOptions = new CacheOptions()
    weightOptions.maxEntries(10).maxWeight(5)
    Cache<String, Int> weighted = new Cache<String, Int>(weightOptions)
    weighted.putWeighted("a", 1, 3, 0)
    weighted.putWeighted("b", 2, 3, 0)
    print("weight=" + str(weighted.size()) + "," + str(weighted.weight()) + "," + str(weighted.contains("a")))

    List<String> reasons = []
    void(String, Int, EvictionReason) listener = (String key, Int value, EvictionReason reason) -> {
        reasons.push(evictionReasonName(reason))
    }
    CacheOptions listenerOptions = new CacheOptions()
    listenerOptions.maxEntries(2)
    Cache<String, Int> listened = new Cache<String, Int>(listenerOptions, listener)
    listened.put("a", 1)
    listened.put("a", 2)
    print("put-old=" + str(listened.put("a", 3)) + "," + str(reasons.get(reasons.length() - 1)))
    print("putif=" + str(listened.putIfAbsent("a", 4)) + "," + str(listened.get("a")))
    listened.invalidate("a")
    print("invalidate=" + str(reasons.get(reasons.length() - 1)))
    listened.invalidateAll()
    print("invalidate-all=" + str(reasons.get(reasons.length() - 1)))

    CacheOptions statsOptions = new CacheOptions()
    statsOptions.maxEntries(2)
    Cache<String, Int> statsCache = new Cache<String, Int>(statsOptions)
    statsCache.put("a", 1)
    statsCache.get("a")
    statsCache.get("missing")
    statsCache.put("b", 2)
    statsCache.put("c", 3)
    CacheStats beforeReset = statsCache.stats()
    print("stats=" + str(beforeReset.hits()) + "," + str(beforeReset.misses()) + "," +
        str(beforeReset.evictions()) + "," + str(beforeReset.expirations()) + "," + str(beforeReset.size()))
    print("rates=" + str(beforeReset.hitRate()) + "," + str(beforeReset.missRate()))
    statsCache.resetStats()
    print("reset=" + str(statsCache.stats().hits()) + "," + str(statsCache.stats().misses()))

    CacheOptions concurrentOptions = new CacheOptions()
    concurrentOptions.maxEntries(4)
    Cache<String, Int> concurrentCache = new Cache<String, Int>(concurrentOptions)
    TaskGroup group = TaskGroup.create(Context.background())
    Task<Int> firstTask = group.spawn(() -> {
        concurrentCache.put("one", 1)
        return Ok(concurrentCache.size())
    })
    Task<Int> secondTask = group.spawn(() -> {
        concurrentCache.put("two", 2)
        return Ok(concurrentCache.size())
    })
    Result<Int, TaskError> joinedOne = firstTask.join()
    Result<Int, TaskError> joinedTwo = secondTask.join()
    group.close()
    print("concurrent=" + str(joinedOne.isOk()) + "," + str(joinedTwo.isOk()) + "," + str(concurrentCache.size()))


    CacheOptions capacityOptions = new CacheOptions()
    capacityOptions.maxEntries(1)
    Cache<String, Int> capacityCache = new Cache<String, Int>(capacityOptions, listener)
    capacityCache.put("a", 1)
    capacityCache.put("b", 2)
    CacheOptions expiredOptions = new CacheOptions()
    expiredOptions.maxEntries(2).defaultTtlMillis(5)
    Cache<String, Int> expiredCache = new Cache<String, Int>(expiredOptions, listener)
    expiredCache.put("x", 1)
    sleepMs(15)
    expiredCache.cleanup()
    capacityCache.close()
    print("reasons=" + str(hasReason(reasons, "capacity")) + "," +
        str(hasReason(reasons, "expired")) + "," + str(hasReason(reasons, "closed")))
    cache.close()
    cache.close()
    print("closed=" + str(cache.isClosed()) + "," + str(cache.get("a") == null) + "," + str(cache.put("x", 1) == null))
    CacheOptions closedLoadOptions = new CacheOptions()
    Cache<String, Int> closedLoad = new Cache<String, Int>(closedLoadOptions)
    closedLoad.close()
    print("closed-load=" + str(closedLoad.isClosed()) + "," + str(closedLoad.get("x") == null))
    return 0
}
