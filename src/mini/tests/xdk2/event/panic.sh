#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.event
import xdk.event
import xdk.codec
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    if name == "eventNullId" {
        Event event = new Event(null, "topic", Json.string("x"), 0 as Long, null)
    } else if name == "eventNullTopic" {
        Event event = new Event("id", null, Json.string("x"), 0 as Long, null)
    } else if name == "eventNullPayload" {
        Event event = new Event("id", "topic", null, 0 as Long, null)
    } else if name == "eventEmptyId" {
        Event event = new Event("  ", "topic", Json.string("x"), 0 as Long, null)
    } else if name == "eventEmptyTopic" {
        Event event = new Event("id", "  ", Json.string("x"), 0 as Long, null)
    } else if name == "eventNegative" {
        Event event = new Event("id", "topic", Json.string("x"), -1 as Long, null)
    } else if name == "subscribeTopic" {
        EventBus bus = new EventBus()
        Result<EventSubscription, Error> value = bus.subscribe(null,
            (Event event) -> Ok())
    } else if name == "publishNull" {
        EventBus bus = new EventBus()
        Result<Int, Error> value = bus.publish(null)
    } else if name == "unsubscribeNull" {
        EventBus bus = new EventBus()
        Bool value = bus.unsubscribe(null)
    } else if name == "subscribedNull" {
        EventBus bus = new EventBus()
        Bool value = bus.isSubscribed(null)
    } else if name == "subscriptionBus" {
        EventSubscription value = new EventSubscription(null, "sub-1", "topic")
    } else if name == "subscriptionId" {
        EventBus bus = new EventBus()
        EventSubscription value = new EventSubscription(bus, null, "topic")
    } else if name == "subscriptionTopic" {
        EventBus bus = new EventBus()
        EventSubscription value = new EventSubscription(bus, "sub-1", null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "event panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "event panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic eventNullId "Event: null argument"
check_panic eventNullTopic "Event: null argument"
check_panic eventNullPayload "Event: null argument"
check_panic eventEmptyId "Event: empty id"
check_panic eventEmptyTopic "Event: empty topic"
check_panic eventNegative "Event: negative timestamp"
check_panic subscribeTopic "EventBus.subscribe: null topic"
check_panic publishNull "EventBus.publish: null event"
check_panic unsubscribeNull "EventBus.unsubscribe: null subscription"
check_panic subscribedNull "EventBus.isSubscribed: null subscription"
check_panic subscriptionBus "EventSubscription: null argument"
check_panic subscriptionId "EventSubscription: null argument"
check_panic subscriptionTopic "EventSubscription: null argument"
echo "event_panic: PASS"
