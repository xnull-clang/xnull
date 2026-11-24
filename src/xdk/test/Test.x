package xdk.test
import xdk.errors
import xdk.runtime
import xdk.tasks
import xdk.time

enum TestStatus {
    Unknown,
    Passed,
    Failed,
    Skipped,
}

String testStatusName(TestStatus status) {
    if status == TestStatus.Passed { return "passed" }
    if status == TestStatus.Failed { return "failed" }
    if status == TestStatus.Skipped { return "skipped" }
    return "unknown"
}

static Error testError(String code, ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error.withCode(code)
}

static Error assertionError(String message) {
    if message == null { throw "Assert: null message" }
    if message.trim() == "" { message = "assertion failed" }
    return testError("test.assertion_failed", ErrorKind.Internal, message)
}

class TestContext {
    final String _name
    final Context _context
    final List<String> _logs

    TestContext(String name, Context context) {
        if name == null || name.trim() == "" { throw "TestContext: empty name" }
        if context == null { throw "TestContext: null context" }
        self._name = name.trim()
        self._context = context
        self._logs = []
    }

    String name() { return self._name }

    Void log(String text) {
        if text == null { throw "TestContext.log: null text" }
        self._logs.push(text)
    }

    Result<Unit, Error> skip(String reason) {
        if reason == null || reason.trim() == "" { throw "TestContext.skip: empty reason" }
        self._logs.push("skip: " + reason)
        return Err(testError("test.skipped", ErrorKind.Cancelled, reason))
    }

    Result<Unit, Error> fail(String message) {
        if message == null || message.trim() == "" { throw "TestContext.fail: empty message" }
        self._logs.push("fail: " + message)
        return Err(testError("test.failed", ErrorKind.Internal, message))
    }

    Bool isCancelled() { return self._context.isCancelled() }
    List<String> logs() { return self._logs.copy() }
}

class Test {
    final String _name
    final List<String> _tags
    final Long _timeoutMillis
    final Result<Unit, Error>(TestContext) _body

    Test(String name, List<String> tags, Long timeoutMillis, Result<Unit, Error>(TestContext) body) {
        if name == null || name.trim() == "" { throw "Test: empty name" }
        if tags == null { throw "Test: null tags" }
        if timeoutMillis < 0 { throw "Test: negative timeout" }
        self._name = name.trim()
        self._tags = []
        Int index = 0
        while index < tags.length() {
            String tag = tags.get(index)
            if tag == null || tag.trim() == "" { throw "Test: empty tag" }
            String normalized = tag.trim()
            Int scan = 0
            while scan < self._tags.length() {
                if self._tags.get(scan) == normalized { throw "Test: duplicate tag" }
                scan = scan + 1
            }
            self._tags.push(normalized)
            index = index + 1
        }
        self._timeoutMillis = timeoutMillis
        self._body = body
    }

    String name() { return self._name }
    List<String> tags() { return self._tags.copy() }
    Long timeoutMillis() { return self._timeoutMillis }
    Result<Unit, Error>(TestContext) body() { return self._body }

    Bool hasTag(String tag) {
        if tag == null { throw "Test.hasTag: null tag" }
        String value = tag.trim()
        Int index = 0
        while index < self._tags.length() {
            if self._tags.get(index) == value { return true }
            index = index + 1
        }
        return false
    }
}

class TestSuite {
    final String _name
    final List<Test> _tests

    TestSuite(String name) {
        if name == null || name.trim() == "" { throw "TestSuite: empty name" }
        self._name = name.trim()
        self._tests = []
    }

    String name() { return self._name }

    Int _indexOf(String name) {
        Int index = 0
        while index < self._tests.length() {
            if self._tests.get(index).name() == name { return index }
            index = index + 1
        }
        return -1
    }

    TestSuite add(Test test) {
        if test == null { throw "TestSuite.add: null test" }
        if self._indexOf(test.name()) >= 0 { throw "TestSuite.add: duplicate test" }
        self._tests.push(test)
        return self
    }

    TestSuite addAll(List<Test> tests) {
        if tests == null { throw "TestSuite.addAll: null" }
        Int index = 0
        while index < tests.length() {
            if tests.get(index) == null { throw "TestSuite.addAll: null test" }
            if self._indexOf(tests.get(index).name()) >= 0 { throw "TestSuite.addAll: duplicate test" }
            Int scan = index + 1
            while scan < tests.length() {
                if tests.get(scan) != null && tests.get(index).name() == tests.get(scan).name() {
                    throw "TestSuite.addAll: duplicate test"
                }
                scan = scan + 1
            }
            index = index + 1
        }
        index = 0
        while index < tests.length() {
            self._tests.push(tests.get(index))
            index = index + 1
        }
        return self
    }

    TestSuite filter(String tag) {
        if tag == null || tag.trim() == "" { throw "TestSuite.filter: empty tag" }
        TestSuite result = new TestSuite(self._name)
        Int index = 0
        while index < self._tests.length() {
            if self._tests.get(index).hasTag(tag) { result.add(self._tests.get(index)) }
            index = index + 1
        }
        return result
    }

    List<Test> tests() { return self._tests.copy() }
    Int length() { return self._tests.length() }
}

class TestResult {
    final String _name
    final TestStatus _status
    final Long _durationMillis
    final Error? _error
    final List<String> _logs

    TestResult(String name, TestStatus status, Long durationMillis, Error? error, List<String> logs) {
        if name == null || name.trim() == "" { throw "TestResult: empty name" }
        if status == null { throw "TestResult: null status" }
        if durationMillis < 0 { throw "TestResult: negative duration" }
        if logs == null { throw "TestResult: null logs" }
        if status == TestStatus.Passed && error != null { throw "TestResult: passed with error" }
        if status != TestStatus.Passed && error == null { throw "TestResult: non-passed without error" }
        self._name = name.trim()
        self._status = status
        self._durationMillis = durationMillis
        self._error = error
        self._logs = []
        Int index = 0
        while index < logs.length() {
            if logs.get(index) == null { throw "TestResult: null log" }
            self._logs.push(logs.get(index))
            index = index + 1
        }
    }

    String name() { return self._name }
    TestStatus status() { return self._status }
    Long durationMillis() { return self._durationMillis }
    Error? error() { return self._error }
    List<String> logs() { return self._logs.copy() }

    String describe() {
        return self._name + " " + testStatusName(self._status) + " " + str(self._durationMillis) + "ms"
    }
}

class TestTimer {
    final Context _timerContext
    final Context _testContext
    final Long _millis
    Bool _fired

    TestTimer(Context timerContext, Context testContext, Long millis) {
        self._timerContext = timerContext
        self._testContext = testContext
        self._millis = millis
        self._fired = false
    }

    Bool fired() { return self._fired }

    Result<Int, TaskError> run() {
        Result<Unit, Error> slept = sleepContext(self._timerContext, durationOfMillis(self._millis))
        if slept.isErr() { return Ok(0) }
        if !self._testContext.isCancelled() {
            self._fired = true
            self._testContext.cancel()
        }
        return Ok(0)
    }
}

class TestRunner {
    TestRunner() { }

    static Task<Int> _startTimer(TaskGroup group, TestTimer timer) {
        return group.spawn(() -> {
            return timer.run()
        })
    }

    TestResult _runOne(Context parent, Test test) {
        if parent.isCancelled() {
            Error error = testError("test.skipped", ErrorKind.Cancelled, "parent cancelled")
            List<String> emptyLogs = []
            return new TestResult(test.name(), TestStatus.Skipped, 0, error, emptyLogs)
        }
        Context groupContext = Context.withCancel(parent)
        Context child = Context.withCancel(parent)
        TaskGroup group = TaskGroup.create(groupContext)
        TestTimer timer = new TestTimer(groupContext, child, test.timeoutMillis())
        if test.timeoutMillis() > 0 {
            TestRunner._startTimer(group, timer)
        }
        TestContext testContext = new TestContext(test.name(), child)
        Result<Unit, Error>(TestContext) body = test.body()
        Long started = nowMono()
        Result<Unit, Error> outcome = body(testContext)
        Long duration = nowMono() - started
        if duration < 0 { duration = 0 }
        group.close()
        List<String> logs = testContext.logs()
        if parent.isCancelled() {
            Error error = testError("test.skipped", ErrorKind.Cancelled, "parent cancelled")
            return new TestResult(test.name(), TestStatus.Skipped, duration, error, logs)
        }
        if timer.fired() {
            Error error = new BasicError(ErrorKind.Timeout, "test timed out")
            return new TestResult(test.name(), TestStatus.Failed, duration, error, logs)
        }
        if outcome.isOk() {
            return new TestResult(test.name(), TestStatus.Passed, duration, null, logs)
        }
        Error failure = outcome.error()
        if failure.kind() == ErrorKind.Cancelled {
            return new TestResult(test.name(), TestStatus.Skipped, duration, failure, logs)
        }
        return new TestResult(test.name(), TestStatus.Failed, duration, failure, logs)
    }

    List<TestResult> run(Context context, TestSuite suite) {
        if context == null || suite == null { throw "TestRunner.run: null argument" }
        List<TestResult> results = []
        List<Test> tests = suite.tests()
        Int index = 0
        while index < tests.length() {
            if context.isCancelled() { break }
            results.push(self._runOne(context, tests.get(index)))
            index = index + 1
        }
        return results
    }

    List<TestResult> runAll(Context context, List<TestSuite> suites) {
        if context == null || suites == null { throw "TestRunner.runAll: null argument" }
        List<TestResult> results = []
        Int index = 0
        while index < suites.length() {
            if suites.get(index) == null { throw "TestRunner.runAll: null suite" }
            if context.isCancelled() { break }
            List<TestResult> part = self.run(context, suites.get(index))
            Int j = 0
            while j < part.length() {
                results.push(part.get(j))
                j = j + 1
            }
            index = index + 1
        }
        return results
    }

    List<TestResult> runFiltered(Context context, TestSuite suite, Bool(Test) predicate) {
        if context == null || suite == null { throw "TestRunner.runFiltered: null argument" }
        if context.isCancelled() {
            List<TestResult> empty = []
            return empty
        }
        TestSuite filtered = new TestSuite(suite.name())
        List<Test> tests = suite.tests()
        Int index = 0
        while index < tests.length() {
            if predicate(tests.get(index)) { filtered.add(tests.get(index)) }
            index = index + 1
        }
        return self.run(context, filtered)
    }
}

class Assert {
    private Assert() { }

    static Result<Unit, Error> isTrue(Bool condition, String message) {
        if condition { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> isFalse(Bool condition, String message) {
        if !condition { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> equals<T>(T expected, T actual, String message) {
        if expected == actual { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> notEquals<T>(T expected, T actual, String message) {
        if expected != actual { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> isNull<T>(T? value, String message) {
        if value == null { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> isNotNull<T>(T? value, String message) {
        if value != null { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> lessThan(Double left, Double right, String message) {
        if left < right { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> greaterThan(Double left, Double right, String message) {
        if left > right { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> contains(String text, String fragment, String message) {
        if text == null || fragment == null { throw "Assert.contains: null argument" }
        if text.indexOf(fragment) >= 0 { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> startsWith(String text, String prefix, String message) {
        if text == null || prefix == null { throw "Assert.startsWith: null argument" }
        if text.startsWith(prefix) { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> endsWith(String text, String suffix, String message) {
        if text == null || suffix == null { throw "Assert.endsWith: null argument" }
        if text.endsWith(suffix) { return Ok() }
        return Err(assertionError(message))
    }

    static Result<Error, Error> throwsError<T>(Result<T, Error>() operation, String message) {
        Result<T, Error> result = operation()
        if result.isErr() { return Ok(result.error()) }
        return Err(assertionError(message))
    }

    static Result<Unit, Error> fail(String message) {
        return Err(assertionError(message))
    }
}
