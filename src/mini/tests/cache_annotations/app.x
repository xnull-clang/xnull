package app.cache
import xdk.cache
import xdk.errors

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

    @Cacheable("users")
    Result<Int, Error> load(Int id) {
        self.loads = self.loads + 1
        return Ok(id * 10)
    }

    @Cacheable("users", "u")
    Result<Int, Error> explicit(Int id) {
        self.explicitLoads = self.explicitLoads + 1
        return Ok(id + 100)
    }

    @CacheEvict("users", "users:load")
    Result<Int, Error> update(Int id) {
        self.evicts = self.evicts + 1
        return Ok(id)
    }

    @Cacheable("errors")
    Result<Int, Error> failing(Int id) {
        self.failures = self.failures + 1
        return Err(cacheError())
    }
}

static Int main() { return 0 }
