#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
import xdk.audit
import xdk.text
class Sink implements AuditSink {
    Bool open
    Sink() { self.open = true }
    Result<Unit, Error> write(AuditEvent event) { return Ok() }
    Result<Unit, Error> flush() { return Ok() }
    Void close() { self.open = false }
    Bool isOpen() { return self.open }
}
static Int main(String[] args) {
    String name = args.get(0)
    Map<String, String> fields = [:]
    if name == "emptyActor" {
        AuditEvent event = new AuditEvent("", "a", "", "ok", AuditLevel.Info, 0, fields)
    } else if name == "emptyAction" {
        AuditEvent event = new AuditEvent("a", "", "", "ok", AuditLevel.Info, 0, fields)
    } else if name == "emptyOutcome" {
        AuditEvent event = new AuditEvent("a", "x", "", "", AuditLevel.Info, 0, fields)
    } else if name == "negativeTime" {
        AuditEvent event = new AuditEvent("a", "x", "", "ok", AuditLevel.Info, -1, fields)
    } else if name == "emptyFieldKey" {
        fields.put("", "v")
        AuditEvent event = new AuditEvent("a", "x", "", "ok", AuditLevel.Info, 0, fields)
    } else if name == "redactorPattern" {
        AuditRedactor redactor = new AuditRedactor()
        redactor.addPattern(null, "x")
    } else if name == "redactorReplacement" {
        AuditRedactor redactor = new AuditRedactor()
        Regex pattern = Regex.compile("x").value()
        redactor.addPattern(pattern, "")
    } else if name == "loggerSink" {
        AuditLogger logger = new AuditLogger(null)
    } else if name == "loggerField" {
        Sink sink = new Sink()
        AuditLogger logger = new AuditLogger(sink)
        logger.withField("", "x")
    } else if name == "loggerRedactor" {
        Sink sink = new Sink()
        AuditLogger logger = new AuditLogger(sink)
        logger.withRedactor(null)
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
        echo "audit panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "audit panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}
check_panic emptyActor "AuditEvent: empty actor"
check_panic emptyAction "AuditEvent: empty action"
check_panic emptyOutcome "AuditEvent: empty outcome"
check_panic negativeTime "AuditEvent: negative timestamp"
check_panic emptyFieldKey "AuditEvent: empty field key"
check_panic redactorPattern "AuditRedactor.addPattern: null pattern"
check_panic redactorReplacement "AuditRedactor.addPattern: empty replacement"
check_panic loggerSink "AuditLogger: null sink"
check_panic loggerField "AuditLogger.withField: empty key"
check_panic loggerRedactor "AuditLogger.withRedactor: null redactor"
echo "audit_panic: PASS"
