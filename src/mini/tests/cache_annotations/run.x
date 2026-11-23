package app.cache
import xdk.cache
import xdk.errors
import generated.CacheGenerated

static Error cacheError() {
    return new BasicError(ErrorKind.Network, "cache")
}

class Service {
    Int loads
    Int explicitLoads
    Int evicts
    Int failures
    Service() {
        self.loads = 0
        self.explicitLoads = 0
        self.evicts = 0
        self.failures = 0
    }
    Result<Int, Error> load(Int id) {
        self.loads = self.loads + 1
        return Ok(id * 10)
    }
    Result<Int, Error> explicit(Int id) {
        self.explicitLoads = self.explicitLoads + 1
        return Ok(id + 100)
    }
    Result<Int, Error> update(Int id) {
        self.evicts = self.evicts + 1
        return Ok(id)
    }
    Result<Int, Error> failing(Int id) {
        self.failures = self.failures + 1
        return Err(cacheError())
    }
}

static Int main() {
    CacheOptions options = new CacheOptions()
    options.maxEntries(16)
    Cache<String, Int> cache = new Cache<String, Int>(options)
    Service service = new Service()

    Result<Int, Error> first = Service_loadCached(service, cache, 1)
    Result<Int, Error> second = Service_loadCached(service, cache, 1)
    print("load=" + str(first.value()) + "," + str(second.value()) + "," + str(service.loads))

    Result<Int, Error> other = Service_loadCached(service, cache, 2)
    print("load-other=" + str(other.value()) + "," + str(service.loads))

    Result<Int, Error> explicitOne = Service_explicitCached(service, cache, 1)
    Result<Int, Error> explicitAgain = Service_explicitCached(service, cache, 1)
    print("explicit=" + str(explicitOne.value()) + "," + str(explicitAgain.value()) + "," + str(service.explicitLoads))

    Result<Int, Error> failed = Service_failingCached(service, cache, 1)
    Result<Int, Error> failedAgain = Service_failingCached(service, cache, 1)
    print("error=" + str(failed.isErr()) + "," + str(failedAgain.isErr()) + "," + str(service.failures))

    Result<Int, Error> updated = Service_updateEvict(service, cache, 1)
    Result<Int, Error> reload = Service_loadCached(service, cache, 1)
    print("evict=" + str(updated.value()) + "," + str(service.evicts) + "," + str(reload.value()) + "," + str(service.loads))
    print("cache-size=" + str(cache.size()))
    return 0
}
