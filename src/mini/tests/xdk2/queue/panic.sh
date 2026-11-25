#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.queue
import xdk.queue
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    if name == "statsSize" {
        QueueStats sizeStats = new QueueStats(-1, 0 as Long, 0 as Long, 0 as Long, 0 as Long, false)
    } else if name == "statsPushed" {
        QueueStats pushedStats = new QueueStats(0, -1 as Long, 0 as Long, 0 as Long, 0 as Long, false)
    } else if name == "boundedCapacity" {
        BoundedQueue<String> boundedQueue = new BoundedQueue<String>(0, DropPolicy.Error)
    } else if name == "batchSize" {
        BatchQueue<String> batchQueue = new BatchQueue<String>(0)
    } else if name == "delayNegative" {
        DelayQueue<String> delayQueue = new DelayQueue<String>()
        Bool seeded = delayQueue.put("a", -1 as Long)
    } else if name == "delayNullContext" {
        DelayQueue<String> nullQueue = new DelayQueue<String>()
        Result<String, Error> taken = nullQueue.take(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "queue panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "queue panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic statsSize "QueueStats: negative value"
check_panic statsPushed "QueueStats: negative value"
check_panic boundedCapacity "BoundedQueue: capacity < 1"
check_panic batchSize "BatchQueue: batchSize < 1"
check_panic delayNegative "DelayQueue.put: negative delay"
check_panic delayNullContext "DelayQueue.take: null context"
echo "queue_panic: PASS"
