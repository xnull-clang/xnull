#!/bin/sh
# XDK-W6 200M performance gate.
#
# Same LCG arithmetic loop as the mini 0.2.0 baseline. Each point is measured
# three times after one discarded warm-up; the fastest run is compared with
# the recorded 0.733s @ 200M baseline. A >20% regression fails the gate.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

BASELINE=0.733

cat > "$D/lcg.x" <<'EOF'
static Int main() {
    Long n = NNN
    Long x = 1
    Long s = 0
    Long i = 0
    while i < n {
        x = (x * 1103515245 + 12345) % 2147483648
        s = (s + x % 7) % 1000000007
        i = i + 1
    }
    print(s)
    return 0
}
EOF

measure() {
    python3 - "$1" <<'PY'
import subprocess, sys, time
exe = sys.argv[1]
subprocess.run([exe], stdout=subprocess.DEVNULL, check=True)
best = None
for _ in range(3):
    t0 = time.monotonic()
    subprocess.run([exe], stdout=subprocess.DEVNULL, check=True)
    dt = time.monotonic() - t0
    if best is None or dt < best:
        best = dt
print("%.3f" % best)
PY
}

for N in 25000000 50000000 100000000 200000000; do
    sed "s/NNN/$N/" "$D/lcg.x" > "$D/lcg-$N.x"
    "$XNULL" --bootstrap --engine=mini build "$D/lcg-$N.x" -o "$D/lcg-$N" >/dev/null 2>"$D/build-$N.err" || {
        cat "$D/build-$N.err" >&2; exit 1
    }
    secs=$(measure "$D/lcg-$N")
    echo "$N $secs"
    if [ "$N" = 200000000 ]; then
        M10_200M=$secs
        export M10_200M
    fi
done

python3 - "$BASELINE" <<'PY'
import sys
baseline = float(sys.argv[1])
# The table was printed above; the 200M value is re-read from the environment
# to keep this shell-portable.
value = float(__import__("os").environ["M10_200M"])
ratio = value / baseline
print("200M %.3fs baseline %.3fs ratio %.3fx" % (value, baseline, ratio))
if ratio > 1.2:
    print("m10 perf: FAIL (>20%% regression)")
    sys.exit(1)
print("m10 perf: PASS")
PY
