#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.execution
import xdk.execution
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    Context context = Context.background()
    if name == "semNegative" {
        Semaphore semaphore = new Semaphore(-1)
    } else if name == "semNullContext" {
        Semaphore semaphore = new Semaphore(1)
        Result<Unit, Error> result = semaphore.acquire(null)
    } else if name == "waitNegative" {
        WaitGroup group = new WaitGroup()
        group.add(-1)
    } else if name == "waitZeroDone" {
        WaitGroup group = new WaitGroup()
        group.done()
    } else if name == "waitNullContext" {
        WaitGroup group = new WaitGroup()
        group.add(1)
        Result<Unit, Error> result = group.wait(null)
    } else if name == "onceNullContext" {
        Once once = new Once()
        Result<Unit, Error> result = once.run(null, () -> { })
    } else if name == "rwNullContext" {
        RwLock<Int> rwLock = new RwLock<Int>(1)
        Result<Unit, Error> result = rwLock.withRead(null, (Int item) -> { })
    } else if name == "poolCapacity" {
        Pool<Int> pool = new Pool<Int>(0, () -> { return Ok(1) }, (Int item) -> { })
    } else if name == "poolNullContext" {
        Pool<Int> pool = new Pool<Int>(1, () -> { return Ok(1) }, (Int item) -> { })
        Result<Int, Error> result = pool.acquire(null)
    } else if name == "promiseFailNull" {
        Promise<Int> promise = new Promise<Int>()
        Bool result = promise.fail(null)
    } else if name == "promiseCancelNull" {
        Promise<Int> promise = new Promise<Int>()
        Bool result = promise.cancel(null)
    } else if name == "futureNull" {
        Future<Int> future = new Future<Int>(null)
    } else if name == "executorNullParent" {
        Executor executor = new Executor(null, 1)
    } else if name == "executorZero" {
        Executor executor = new Executor(context, 0)
    } else if name == "executorNullSubmit" {
        Executor executor = Executor.single(context)
        Result<Task<Int>, Error> result = executor.submit<Int>(null, (Context taskContext) -> {
            return Ok(1)
        })
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "execution panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "execution panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic semNegative "Semaphore: negative permits"
check_panic semNullContext "Semaphore.acquire: null context"
check_panic waitNegative "WaitGroup.add: negative count"
check_panic waitZeroDone "WaitGroup.done: counter is zero"
check_panic waitNullContext "WaitGroup.wait: null context"
check_panic onceNullContext "Once.run: null context"
check_panic rwNullContext "RwLock.withRead: null context"
check_panic poolCapacity "Pool: capacity must be positive"
check_panic poolNullContext "Pool.acquire: null context"
check_panic promiseFailNull "Promise.fail: null error"
check_panic promiseCancelNull "Promise.cancel: null reason"
check_panic futureNull "Future: null promise"
check_panic executorNullParent "Executor: null parent"
check_panic executorZero "Executor: parallelism must be positive"
check_panic executorNullSubmit "Executor.submit: null context"
echo "execution_panic: PASS"
