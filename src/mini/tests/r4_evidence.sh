#!/bin/sh
# R4 evidence programs: escape subset, DetailedError aggregation, Config.setChecked,
# and the retained DateTime add/diff subset. These are evidence, not new gates;
# every program is built and run end-to-end with exact output diffs.
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$HERE/../../.." && pwd)
XNULL="$ROOT/src/cli/xnull"
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

run_case() {
    name=$1
    "$XNULL" --bootstrap --engine=mini build "$HERE/r4/$name.x" -o "$D/$name" >"$D/$name.build" 2>&1 || {
        cat "$D/$name.build" >&2; exit 1
    }
    "$D/$name" >"$D/$name.out" 2>"$D/$name.err" || {
        cat "$D/$name.err" >&2; exit 1
    }
    diff -u "$D/$name.exp" "$D/$name.out"
}

cat > "$D/escape.exp" <<'EOF'
26
10
13
9
2
65
127
2
233
4
128512
1
10
1
13
1
9
1
92
1
39
1
34
EOF

cat > "$D/errors_detail.exp" <<'EOF'
2
2
0.origin
custom
1.path
true
2
[cfg.bad] InvalidArgument: bad setting
[cfg.bad] InvalidArgument: bad setting; NotFound: missing
true
true
true
false
false
true
true
true
true
true
true
16
true
EOF

cat > "$D/config_checked.exp" <<'EOF'
true
demo
true
true
1
true
1
next
true
true
on
override
next
EOF

cat > "$D/time_calendar.exp" <<'EOF'
2024-01-31 23:59:59
2024-02-01 23:59:59
86400000
-86400000
true
false
-1
3
31
2024-03-01
2023-03-01
1970-01-01 00:00:00
1970-01-01 00:00:01.500
-1
EOF

run_case escape
run_case errors_detail
run_case config_checked
run_case time_calendar

echo "mini r4 evidence: PASS"
