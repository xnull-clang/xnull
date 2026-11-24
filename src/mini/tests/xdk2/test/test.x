package xdk2.test
import xdk.test
import xdk.errors
import xdk.time

static List<String> tagList(String first) {
    List<String> result = []
    result.push(first)
    return result
}

static List<String> tagList2(String first, String second) {
    List<String> result = []
    result.push(first)
    result.push(second)
    return result
}

static List<String> emptyTags() {
    List<String> result = []
    return result
}

static Error testIoError() {
    return new BasicError(ErrorKind.Internal, "assertion")
}

static Int main() {
    Context context = Context.background()
    TestContext direct = new TestContext("direct", context)
    direct.log("hello")
    Result<Unit, Error> skipped = direct.skip("later")
    Result<Unit, Error> failed = direct.fail("broken")
    print("context=" + direct.name() + "," + str(direct.logs().length()) + "," +
        str(skipped.error().describe().indexOf("test.skipped") >= 0) + "," +
        str(failed.error().describe().indexOf("test.failed") >= 0))

    Result<Unit, Error>(TestContext) passingBody = (TestContext ctx) -> {
        ctx.log("pass")
        return Assert.isTrue(1 < 2, "one")
    }
    Result<Unit, Error>(TestContext) failingBody = (TestContext ctx) -> {
        ctx.log("fail")
        return ctx.fail("expected failure")
    }
    Result<Unit, Error>(TestContext) skipBody = (TestContext ctx) -> {
        return ctx.skip("not supported")
    }
    Result<Unit, Error>(TestContext) slowBody = (TestContext ctx) -> {
        sleepMs(80)
        return Ok()
    }
    Test passing = new Test("passing", tagList("fast"), 0, passingBody)
    Test failing = new Test("failing", tagList("fast"), 0, failingBody)
    Test skipping = new Test("skipping", tagList("slow"), 0, skipBody)
    Test timeout = new Test("timeout", tagList("slow"), 20, slowBody)
    print("test=" + passing.name() + "," + str(passing.tags().length()) + "," + str(passing.hasTag("fast")) + "," + str(passing.timeoutMillis()))
    Test normalized = new Test(" t ", tagList2(" a ", "b"), 0, passingBody)
    Test tagNormalized = new Test("t", tagList("  a  "), 0, passingBody)
    print("test-tags=" + normalized.name() + "," + tagNormalized.tags().get(0))

    TestSuite suite = new TestSuite("suite")
    suite.add(passing).add(failing).add(skipping)
    print("suite=" + suite.name() + "," + str(suite.length()) + "," + str(suite.filter("fast").length()) + "," + str(suite.filter("slow").length()))

    TestRunner runner = new TestRunner()
    List<TestResult> results = runner.run(context, suite)
    print("run=" + str(results.length()) + "," + testStatusName(results.get(0).status()) + "," +
        testStatusName(results.get(1).status()) + "," + testStatusName(results.get(2).status()))
    print("result=" + results.get(0).describe() + "," + str(results.get(0).durationMillis() >= 0) + "," + str(results.get(0).logs().get(0)))
    Error? failedError = results.get(1).error()
    Error actualFailed = failedError as Error
    print("failure=" + str(actualFailed.describe().indexOf("test.failed") >= 0))

    TestSuite timeoutSuite = new TestSuite("timeout")
    timeoutSuite.add(timeout)
    List<TestResult> timeoutResults = runner.run(context, timeoutSuite)
    Error? timeoutError = timeoutResults.get(0).error()
    Error actualTimeout = timeoutError as Error
    print("timeout=" + testStatusName(timeoutResults.get(0).status()) + "," +
        errorKindName(actualTimeout.kind()))

    TestSuite second = new TestSuite("second")
    second.add(new Test("second-pass", emptyTags(), 0, passingBody))
    List<TestSuite> suites = []
    suites.push(suite)
    suites.push(second)
    List<TestResult> all = runner.runAll(context, suites)
    print("all=" + str(all.length()) + "," + all.get(all.length() - 1).name())

    TestSuite filteredSuite = new TestSuite("filtered")
    filteredSuite.add(passing).add(skipping)
    Bool(Test) slowPredicate = (Test test) -> {
        return test.hasTag("slow")
    }
    List<TestResult> filtered = runner.runFiltered(context, filteredSuite, slowPredicate)
    print("filtered=" + str(filtered.length()) + "," + filtered.get(0).name())

    Context cancelled = Context.background()
    cancelled.cancel()
    print("parent-cancel=" + str(runner.run(cancelled, suite).length()))

    Context bodyCancelled = Context.background()
    bodyCancelled.cancel()
    Result<Unit, Error>(TestContext) cancelledBody = (TestContext ctx) -> {
        return Err(new BasicError(ErrorKind.Cancelled, "cancelled"))
    }
    TestSuite cancelledSuite = new TestSuite("cancelled")
    cancelledSuite.add(new Test("cancelled", emptyTags(), 0, cancelledBody))
    List<TestResult> cancelledResults = runner.run(bodyCancelled, cancelledSuite)
    print("body-cancel=" + str(cancelledResults.length()))

    Context runningCancel = Context.background()
    Result<Unit, Error>(TestContext) runningCancelBody = (TestContext ctx) -> {
        runningCancel.cancel()
        return Ok()
    }
    TestSuite runningCancelSuite = new TestSuite("running")
    runningCancelSuite.add(new Test("running-cancel", emptyTags(), 0, runningCancelBody))
    List<TestResult> runningResults = runner.run(runningCancel, runningCancelSuite)
    print("running-cancel=" + str(runningResults.length()) + "," + testStatusName(runningResults.get(0).status()))

    print("assert=" + str(Assert.isTrue(true, "").isOk()) + "," + str(Assert.isFalse(false, "").isOk()) +
        "," + str(Assert.equals(2, 2, "").isOk()) + "," + str(Assert.notEquals(2, 3, "").isOk()) +
        "," + str(Assert.isNull<String>(null, "").isOk()) + "," + str(Assert.isNotNull("x", "").isOk()) +
        "," + str(Assert.lessThan(1.0, 2.0, "").isOk()) + "," + str(Assert.greaterThan(2.0, 1.0, "").isOk()) +
        "," + str(Assert.contains("abc", "b", "").isOk()) + "," + str(Assert.startsWith("abc", "a", "").isOk()) +
        "," + str(Assert.endsWith("abc", "c", "").isOk()))
    Result<Unit, Error> failedAssert = Assert.equals(1, 2, "mismatch")
    print("assert-fail=" + str(failedAssert.isErr()) + "," + failedAssert.error().describe())
    Result<Unit, Error> explicitFail = Assert.fail("explicit")
    print("assert-explicit=" + explicitFail.error().describe())
    Result<Int, Error>() errorOperation = () -> {
        return Err(testIoError())
    }
    Result<Error, Error> thrown = Assert.throwsError(errorOperation, "must fail")
    print("throws-error=" + str(thrown.isOk()) + "," + errorKindName(thrown.value().kind()))

    TestSuite duplicateBase = new TestSuite("dup")
    duplicateBase.add(passing)
    List<Test> additions = []
    additions.push(new Test("other", emptyTags(), 0, passingBody))
    additions.push(new Test("passing", emptyTags(), 0, passingBody))
    print("addall-before=" + str(duplicateBase.length()))
    return 0
}
