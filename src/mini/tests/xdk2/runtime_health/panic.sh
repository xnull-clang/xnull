#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
import xdk.runtime
static Int main(String[] args) {
    String name = args.get(0)
    Map<String, String> details = [:]
    if name == "nullState" {
        HealthReport report = new HealthReport(null, "m", 0, details)
    } else if name == "negativeTime" {
        HealthReport report = new HealthReport(HealthState.Healthy, "m", -1, details)
    } else if name == "nullMessage" {
        HealthReport report = new HealthReport(HealthState.Healthy, null, 0, details)
    } else if name == "nullDetails" {
        HealthReport report = new HealthReport(HealthState.Healthy, "m", 0, null)
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
        echo "runtime_health panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "runtime_health panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}
check_panic nullState "HealthReport: null state"
check_panic negativeTime "HealthReport: negative timestamp"
check_panic nullMessage "HealthReport: null message"
check_panic nullDetails "HealthReport: null details"
echo "runtime_health_panic: PASS"
