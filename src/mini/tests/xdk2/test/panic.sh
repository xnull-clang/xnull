#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
import xdk.test
import xdk.errors
static List<String> emptyTagsLocal() { List<String> value = []; return value }
static Test testValue() {
    List<String> tags = []
    Result<Unit, Error>(TestContext) body = (TestContext context) -> { return Ok() }
    return new Test("t", tags, 0, body)
}
static Int main(String[] args) {
    String name = args.get(0)
    Context context = Context.background()
    Result<Unit, Error>(TestContext) bodyLocal = (TestContext ctx) -> { return Ok() }
    if name == "contextName" {
        TestContext direct = new TestContext("", context)
    } else if name == "contextLog" {
        TestContext direct = new TestContext("t", context)
        direct.log(null)
    } else if name == "contextSkip" {
        TestContext direct = new TestContext("t", context)
        direct.skip("")
    } else if name == "contextFail" {
        TestContext direct = new TestContext("t", context)
        direct.fail("")
    } else if name == "testName" {
        List<String> tags = []
        Test test = new Test("", tags, 0, bodyLocal)
    } else if name == "testTag" {
        List<String> tags = []
        tags.push(" ")
        Test test = new Test("t", tags, 0, bodyLocal)
    } else if name == "testDuplicateTag" {
        List<String> tags = []
        tags.push("a")
        tags.push("a")
        Test test = new Test("t", tags, 0, bodyLocal)
    } else if name == "testTimeout" {
        List<String> tags = []
        Test test = new Test("t", tags, -1, bodyLocal)
    } else if name == "suiteName" {
        TestSuite suite = new TestSuite(" ")
    } else if name == "suiteAdd" {
        TestSuite suite = new TestSuite("s")
        suite.add(null)
    } else if name == "suiteDuplicate" {
        TestSuite suite = new TestSuite("s")
        suite.add(testValue())
        suite.add(testValue())
    } else if name == "suiteAddAllDuplicate" {
        TestSuite suite = new TestSuite("s")
        suite.add(testValue())
        List<Test> tests = []
        tests.push(new Test("other", emptyTagsLocal(), 0, bodyLocal))
        tests.push(testValue())
        suite.addAll(tests)
    } else if name == "resultPassedError" {
        List<String> logs = []
        TestResult result = new TestResult("t", TestStatus.Passed, 0, new BasicError(ErrorKind.Io, "x"), logs)
    } else if name == "resultFailedNoError" {
        List<String> logs = []
        TestResult result = new TestResult("t", TestStatus.Failed, 0, null, logs)
    } else if name == "resultDuration" {
        List<String> logs = []
        TestResult result = new TestResult("t", TestStatus.Passed, -1, null, logs)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || {
    cat "$TMP/build.err" >&2
    exit 1
}
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && {
        echo "test panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "test panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}
check_panic contextName "TestContext: empty name"
check_panic contextLog "TestContext.log: null text"
check_panic contextSkip "TestContext.skip: empty reason"
check_panic contextFail "TestContext.fail: empty message"
check_panic testName "Test: empty name"
check_panic testTag "Test: empty tag"
check_panic testDuplicateTag "Test: duplicate tag"
check_panic testTimeout "Test: negative timeout"
check_panic suiteName "TestSuite: empty name"
check_panic suiteAdd "TestSuite.add: null test"
check_panic suiteDuplicate "TestSuite.add: duplicate test"
check_panic suiteAddAllDuplicate "TestSuite.addAll: duplicate test"
check_panic resultPassedError "TestResult: passed with error"
check_panic resultFailedNoError "TestResult: non-passed without error"
check_panic resultDuration "TestResult: negative duration"
echo "test_panic: PASS"
