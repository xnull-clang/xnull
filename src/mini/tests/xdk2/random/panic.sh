#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
TMP=$(mktemp -d "$HERE/.panic.XXXXXX")
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/panic.x" <<'X'
package xdk2.random
import xdk.random
import xdk.errors

static Int main(String[] args) {
    String name = args.get(0)
    Random random = new Random(1 as Long)
    if name == "belowZero" {
        Int value = random.nextIntBelow(0)
    } else if name == "intRange" {
        Int value = random.nextIntRange(5, 5)
    } else if name == "longRange" {
        Long value = random.nextLongRange(5 as Long, 5 as Long)
    } else if name == "bytesNegative" {
        Bytes value = random.nextBytes(-1)
    } else if name == "shuffleNull" {
        List<Int> values = null
        random.shuffle(values)
    } else if name == "secureBytesNegative" {
        SecureRandom secure = new SecureRandom()
        Bytes value = secure.nextBytes(-1)
    } else if name == "secureBelowZero" {
        SecureRandom secure = new SecureRandom()
        Int value = secure.nextIntBelow(0)
    } else if name == "secureShuffleNull" {
        SecureRandom secure = new SecureRandom()
        List<Int> values = null
        secure.shuffle(values)
    } else if name == "weightZero" {
        WeightedChoice<String> choice = new WeightedChoice<String>()
        choice.add("a", 0.0)
    } else if name == "weightNegative" {
        WeightedChoice<String> choice = new WeightedChoice<String>()
        choice.add("a", -1.0)
    } else if name == "weightEmpty" {
        WeightedChoice<String> choice = new WeightedChoice<String>()
        String picked = choice.pick(random)
    } else if name == "weightNullRandom" {
        WeightedChoice<String> choice = new WeightedChoice<String>()
        choice.add("a", 1.0)
        String picked = choice.pick(null)
    }
    return 0
}
X
"$XNULL" --bootstrap --engine=mini build "$TMP/panic.x" -o "$TMP/panic" >"$TMP/build.out" 2>"$TMP/build.err" || { cat "$TMP/build.err" >&2; exit 1; }
check_panic() {
    name=$1
    marker=$2
    "$TMP/panic" "$name" >"$TMP/$name.out" 2>"$TMP/$name.err" && { echo "random panic: $name did not fail" >&2; exit 1; }
    grep -Fq "$marker" "$TMP/$name.err" || { echo "random panic: $name missing '$marker'" >&2; cat "$TMP/$name.err" >&2; exit 1; }
}
check_panic belowZero "Random.nextIntBelow: max <= 0"
check_panic intRange "Random.nextIntRange: empty range"
check_panic longRange "Random.nextLongRange: empty range"
check_panic bytesNegative "Random.nextBytes: negative count"
check_panic shuffleNull "Random.shuffle: null list"
check_panic secureBytesNegative "SecureRandom.nextBytes: negative count"
check_panic secureBelowZero "SecureRandom.nextIntBelow: max <= 0"
check_panic secureShuffleNull "SecureRandom.shuffle: null list"
check_panic weightZero "WeightedChoice.add: invalid weight"
check_panic weightNegative "WeightedChoice.add: invalid weight"
check_panic weightEmpty "WeightedChoice.pick: empty"
check_panic weightNullRandom "WeightedChoice.pick: null random"
echo "random_panic: PASS"
