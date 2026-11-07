#!/usr/bin/env bash
# M6-B0-05 附带 4 项（A+=/-=、B print(null)、C 数组形参下标、D Map.getOr 动态键）。
# 双路径（--interp / 编译）逐字节比对。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/after/extras"
WORK="$(mktemp -d "${TMPDIR:-/private/var/folders/zr/vyzqhmcn20ggrvrkdpblvchm0000gn/T/opencode}/m6b005x.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

export XNULL_RUNTIME="$ROOT/impl/runtime"
if ! (cd "$ROOT/impl" && go build -o "$WORK/xnull" ./cmd/xnull); then
	echo "FAIL: xnull 构建失败" >&2
	exit 1
fi
BIN="$WORK/xnull"

run_limited() {
	local secs="$1"; shift
	perl -e '
		my $secs = shift @ARGV;
		my $pid = fork();
		die "fork: $!" unless defined $pid;
		if ($pid == 0) { exec @ARGV; exit 127 }
		$SIG{ALRM} = sub { kill "KILL", $pid; waitpid($pid, 0); exit 137 };
		alarm $secs;
		waitpid($pid, 0);
		alarm 0;
		my $st = $?;
		exit(128 + ($st & 127)) if ($st & 127);
		exit($st >> 8);
	' "$secs" "$@"
}

TOTAL=0
PASS=0
: > "$OUT/extras.tsv"

run_case() {
	local id="$1" want="$2" src
	src="$(cat)"
	printf '%s\n' "$src" > "$OUT/$id.x"
	run_limited 30 "$BIN" run --interp "$OUT/$id.x" >"$OUT/$id.interp.out" 2>"$OUT/$id.interp.err"
	local ic=$?
	run_limited 120 "$BIN" run "$OUT/$id.x" >"$OUT/$id.compiled.out" 2>"$OUT/$id.compiled.err"
	local cc=$?
	local st=PASS
	[ "$ic" -eq 0 ] && [ "$(cat "$OUT/$id.interp.out")" = "$want" ] || st="FAIL(interp rc=$ic: $(head -1 "$OUT/$id.interp.err"))"
	[ "$cc" -eq 0 ] && [ "$(cat "$OUT/$id.compiled.out")" = "$want" ] || st="FAIL(compiled rc=$cc: $(head -1 "$OUT/$id.compiled.err"))"
	TOTAL=$((TOTAL + 1))
	[ "$st" = PASS ] && PASS=$((PASS + 1))
	printf '%s\t%s\n' "$id" "$st" >> "$OUT/extras.tsv"
	printf '%-24s %s\n' "$id" "$st"
}

run_case A-compound 0 <<'X'
static Int main() {
    Int i = 1
    i += 1
    i -= 2
    print(i)
    return 0
}
X

run_case B-print-null null <<'X'
static Int main() {
    print(null)
    return 0
}
X

run_case C-array-param 3 <<'X'
static Int sum2(Int[] a) {
    return a[0] + a[1]
}
static Int main() {
    Int[] a = [1, 2]
    print(sum2(a))
    return 0
}
X

run_case D-getOr-dynkey 1 <<'X'
static Int main() {
    List<String> l = ["a"]
    Map<String, Int> m = ["a": 1]
    print(m.getOr(l.get(0), 0))
    return 0
}
X

run_case E-keys-sorted $'a\nb\nc' <<'X'
static Int main() {
    Map<String, Int> m = ["c": 3, "a": 1, "b": 2]
    String[] k = m.keys()
    print(k[0])
    print(k[1])
    print(k[2])
    return 0
}
X

run_case F-intkeys-sorted $'10\n2' <<'X'
static Int main() {
    Map<Int, String> m = [2: "b", 10: "a"]
    Int[] k = m.keys()
    print(k[0])
    print(k[1])
    return 0
}
X

{
	echo "extras_total=$TOTAL"
	echo "extras_pass=$PASS"
} > "$OUT/summary.txt"
echo "----"
cat "$OUT/summary.txt"
[ "$PASS" -eq "$TOTAL" ]
