package app.testannotations
import xdk.test
import xdk.errors

static Error bodyFailure() {
    return new BasicError(ErrorKind.Network, "body")
}

static Error beforeFailure() {
    return new BasicError(ErrorKind.AlreadyExists, "before")
}

static Error afterFailure() {
    return new BasicError(ErrorKind.Io, "after")
}

class UserTests {
    Int beforeCount
    Int afterCount
    Int bodyCount
    UserTests() {
        self.beforeCount = 0
        self.afterCount = 0
        self.bodyCount = 0
    }

    @Before
    void setUp() {
        self.beforeCount = self.beforeCount + 1
    }

    @TestCase("passes")
    Result<Unit, Error> passes() {
        self.bodyCount = self.bodyCount + 1
        return Ok()
    }

    @TestCase
    Result<Unit, Error> fails() {
        self.bodyCount = self.bodyCount + 1
        return Err(bodyFailure())
    }

    @After
    void tearDown() {
        self.afterCount = self.afterCount + 1
    }

    @Benchmark("quick")
    void quick() {
        self.bodyCount = self.bodyCount + 1
    }
}

class BeforeFailTests {
    Int beforeCount
    Int afterCount
    Int bodyCount
    BeforeFailTests() {
        self.beforeCount = 0
        self.afterCount = 0
        self.bodyCount = 0
    }

    @Before
    Result<Unit, Error> setUp() {
        self.beforeCount = self.beforeCount + 1
        return Err(beforeFailure())
    }

    @TestCase
    void neverRuns() {
        self.bodyCount = self.bodyCount + 1
    }

    @After
    void tearDown() {
        self.afterCount = self.afterCount + 1
    }
}

class AfterFailTests {
    @TestCase("success")
    Result<Unit, Error> success() {
        return Ok()
    }

    @TestCase("failure")
    Result<Unit, Error> failure() {
        return Err(bodyFailure())
    }

    @After
    Result<Unit, Error> tearDown() {
        return Err(afterFailure())
    }
}

static Int main() { return 0 }
