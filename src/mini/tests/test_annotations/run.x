package app.testannotations
import xdk.test
import xdk.errors
import generated.TestGenerated

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
    void setUp() { self.beforeCount = self.beforeCount + 1 }
    void tearDown() { self.afterCount = self.afterCount + 1 }
    Result<Unit, Error> passes() {
        self.bodyCount = self.bodyCount + 1
        return Ok()
    }
    Result<Unit, Error> fails() {
        self.bodyCount = self.bodyCount + 1
        return Err(bodyFailure())
    }
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
    Result<Unit, Error> setUp() {
        self.beforeCount = self.beforeCount + 1
        return Err(beforeFailure())
    }
    void tearDown() { self.afterCount = self.afterCount + 1 }
    void neverRuns() {
        self.bodyCount = self.bodyCount + 1
    }
}

class AfterFailTests {
    Result<Unit, Error> success() { return Ok() }
    Result<Unit, Error> failure() { return Err(bodyFailure()) }
    Result<Unit, Error> tearDown() { return Err(afterFailure()) }
}

static String resultStatus(TestResult result) {
    return testStatusName(result.status())
}

static String resultKind(TestResult result) {
    Error? maybeError = result.error()
    Error failure = maybeError as Error
    return errorKindName(failure.kind())
}

static Int main() {
    Context context = Context.background()
    TestRunner runner = new TestRunner()

    UserTests users = new UserTests()
    TestSuite userSuite = UserTestsSuite(users)
    List<TestResult> userResults = runner.run(context, userSuite)
    Error? userFailure = userResults.get(1).error()
    Error actualUserFailure = userFailure as Error
    print("suite=" + userSuite.name() + "," + str(userResults.length()))
    print("names=" + userResults.get(0).name() + "," + userResults.get(1).name())
    print("status=" + resultStatus(userResults.get(0)) + "," + resultStatus(userResults.get(1)))
    print("failure=" + errorKindName(actualUserFailure.kind()))
    print("lifecycle=" + str(users.beforeCount) + "," + str(users.afterCount) + "," + str(users.bodyCount))

    List<Test> benchmarks = UserTestsBenchmarks(users)
    TestSuite benchmarkSuite = new TestSuite("benchmarks")
    benchmarkSuite.addAll(benchmarks)
    List<TestResult> benchmarkResults = runner.run(context, benchmarkSuite)
    print("benchmarks=" + str(benchmarks.length()) + "," + benchmarkResults.get(0).name() + "," +
        resultStatus(benchmarkResults.get(0)))
    print("benchmark-body=" + str(users.bodyCount))

    BeforeFailTests beforeFail = new BeforeFailTests()
    List<TestResult> beforeResults = runner.run(context, BeforeFailTestsSuite(beforeFail))
    print("before-fail=" + resultStatus(beforeResults.get(0)) + "," + resultKind(beforeResults.get(0)) + "," +
        str(beforeFail.bodyCount) + "," + str(beforeFail.afterCount))

    AfterFailTests afterFail = new AfterFailTests()
    List<TestResult> afterResults = runner.run(context, AfterFailTestsSuite(afterFail))
    print("after-success=" + resultStatus(afterResults.get(0)) + "," + resultKind(afterResults.get(0)))
    print("after-failure=" + resultStatus(afterResults.get(1)) + "," + resultKind(afterResults.get(1)))
    return 0
}
