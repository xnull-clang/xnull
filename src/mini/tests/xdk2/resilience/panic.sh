#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
import xdk.resilience
import xdk.errors
static Int main(String[] args) {
    String name = args.get(0)
    if name == "circuitThreshold" {
        CircuitBreaker breaker = new CircuitBreaker(0)
    } else if name == "circuitOpen" {
        CircuitBreaker breaker = new CircuitBreaker(1, 0, 1)
    } else if name == "circuitHalf" {
        CircuitBreaker breaker = new CircuitBreaker(1, 1, 0)
    } else if name == "rateZero" {
        RateLimiter limiter = new RateLimiter(0.0)
    } else if name == "capacityZero" {
        RateLimiter limiter = new RateLimiter(1.0, 0.0)
    } else if name == "bulkZero" {
        Bulkhead bulkhead = new Bulkhead(0)
    } else if name == "retryJitter" {
        RetryPolicy policy = new RetryPolicy()
        policy = policy.withJitter(1.5)
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
        echo "resilience panic: $name did not fail" >&2
        exit 1
    }
    grep -q "$marker" "$TMP/$name.err" || {
        echo "resilience panic: $name missing marker '$marker'" >&2
        cat "$TMP/$name.err" >&2
        exit 1
    }
}
check_panic circuitThreshold "CircuitBreaker: invalid threshold"
check_panic circuitOpen "CircuitBreaker: invalid configuration"
check_panic circuitHalf "CircuitBreaker: invalid configuration"
check_panic rateZero "RateLimiter: permitsPerSecond must be positive"
check_panic capacityZero "RateLimiter: burstCapacity must be at least 1"
check_panic bulkZero "Bulkhead: maxConcurrent < 1"
check_panic retryJitter "RetryPolicy.withJitter: out of range"
echo "resilience_panic: PASS"
