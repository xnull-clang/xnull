#!/usr/bin/env bash
# M6-B0-05 容器与字符串成员覆盖矩阵（解释 vs 编译）。
# 用法：./matrix.sh before|after
# 每项独立 .x 用例；两路径都跑真实 CLI（含 sema），输出逐字节比对。
set -uo pipefail

PHASE="${1:-before}"
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/$PHASE"
WORK="$(mktemp -d "${TMPDIR:-/private/var/folders/zr/vyzqhmcn20ggrvrkdpblvchm0000gn/T/opencode}/m6b005.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"

export XNULL_RUNTIME="$ROOT/impl/runtime"
if ! (cd "$ROOT/impl" && go build -o "$WORK/xnull" ./cmd/xnull); then
	echo "FAIL: xnull 构建失败" >&2
	exit 1
fi
BIN="$WORK/xnull"

# 端口：SIGALRM 到点 SIGKILL 子进程（Go 忽略 SIGALRM）。
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
PASS_CELLS=0
FULL_OPS=0
OPS=0
: > "$OUT/matrix.tsv"

note_of() { # 取 stderr 首行，截断
	local f="$1"
	if [ -s "$f" ]; then head -1 "$f" | cut -c1-120; fi
}

run_case() {
	local typ="$1" member="$2" want="$3" src id
	src="$(cat)"
	OPS=$((OPS + 1))
	id="${typ}.${member}"
	printf '%s\n' "$src" > "$OUT/$id.x"

	run_limited 30 "$BIN" run --interp "$OUT/$id.x" \
		>"$OUT/$id.interp.out" 2>"$OUT/$id.interp.err"
	local ic=$?
	local iok=FAIL
	if [ "$ic" -eq 0 ] && [ "$(cat "$OUT/$id.interp.out")" = "$want" ]; then
		iok=PASS
		PASS_CELLS=$((PASS_CELLS + 1))
	elif [ "$ic" -eq 0 ]; then
		iok="FAIL(out)"
	elif [ "$ic" -eq 137 ]; then
		iok="FAIL(timeout)"
	fi

	run_limited 120 "$BIN" run "$OUT/$id.x" \
		>"$OUT/$id.compiled.out" 2>"$OUT/$id.compiled.err"
	local cc=$?
	local cok=FAIL
	if [ "$cc" -eq 0 ] && [ "$(cat "$OUT/$id.compiled.out")" = "$want" ]; then
		cok=PASS
		PASS_CELLS=$((PASS_CELLS + 1))
	elif [ "$cc" -eq 0 ]; then
		cok="FAIL(out)"
	elif [ "$cc" -eq 137 ]; then
		cok="FAIL(timeout)"
	fi

	TOTAL=$((TOTAL + 2))
	[ "$iok" = PASS ] && [ "$cok" = PASS ] && FULL_OPS=$((FULL_OPS + 1))

	local inote cnote
	inote=""; cnote=""
	[ "$iok" = PASS ] || inote="$(note_of "$OUT/$id.interp.err")"
	[ "$cok" = PASS ] || cnote="$(note_of "$OUT/$id.compiled.err")"
	printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$typ" "$member" "$iok" "$cok" "$inote" "$cnote" \
		>> "$OUT/matrix.tsv"
	printf '%-22s interp=%-10s compiled=%-10s\n' "$id" "$iok" "$cok"
}

# ---------- String（§9.2） ----------
run_case String length 3 <<'X'
static Int main() {
    String s = "abc"
    print(s.length())
    return 0
}
X
run_case String substring bc <<'X'
static Int main() {
    print("abcd".substring(1, 2))
    return 0
}
X
run_case String indexOf 1 <<'X'
static Int main() {
    print("abc".indexOf("b"))
    return 0
}
X
run_case String trim x <<'X'
static Int main() {
    String s = "  x  "
    print(s.trim())
    return 0
}
X
run_case String split $'2\na' <<'X'
static Int main() {
    String[] p = "a,b".split(",")
    print(p.length())
    print(p[0])
    return 0
}
X
run_case String replace x,b <<'X'
static Int main() {
    print("a,b".replace("a", "x"))
    return 0
}
X
run_case String toUpper AB <<'X'
static Int main() {
    print("aB".toUpper())
    return 0
}
X
run_case String toLower ab <<'X'
static Int main() {
    print("Ab".toLower())
    return 0
}
X
run_case String startsWith true <<'X'
static Int main() {
    print("abc".startsWith("ab"))
    return 0
}
X
run_case String endsWith true <<'X'
static Int main() {
    print("abc".endsWith("bc"))
    return 0
}
X

# ---------- T[]（§9.3） ----------
run_case 'T[]' indexRead 2 <<'X'
static Int main() {
    Int[] a = [1, 2]
    print(a[1])
    return 0
}
X
run_case 'T[]' indexWrite 9 <<'X'
static Int main() {
    Int[] a = [1, 2]
    a[1] = 9
    print(a[1])
    return 0
}
X
run_case 'T[]' length 2 <<'X'
static Int main() {
    Int[] a = [1, 2]
    print(a.length())
    return 0
}
X
run_case 'T[]' join 1-2 <<'X'
static Int main() {
    Int[] a = [1, 2]
    print(a.join("-"))
    return 0
}
X

# ---------- List（§9.4） ----------
run_case List length 2 <<'X'
static Int main() {
    List<Int> l = [1, 2]
    print(l.length())
    return 0
}
X
run_case List push $'2\n2' <<'X'
static Int main() {
    List<Int> l = [1]
    l.push(2)
    print(l.length())
    print(l[1])
    return 0
}
X
run_case List insert $'2\n3' <<'X'
static Int main() {
    List<Int> l = [1, 3]
    l.insert(1, 2)
    print(l.get(1))
    print(l.length())
    return 0
}
X
run_case List set 7 <<'X'
static Int main() {
    List<Int> l = [1]
    l.set(0, 7)
    print(l.get(0))
    return 0
}
X
run_case List get 8 <<'X'
static Int main() {
    List<Int> l = [8]
    print(l.get(0))
    return 0
}
X
run_case List remove $'1\n1\n2' <<'X'
static Int main() {
    List<Int> l = [1, 2]
    Int x = l.remove(0)
    print(x)
    print(l.length())
    print(l.get(0))
    return 0
}
X
run_case List clear 0 <<'X'
static Int main() {
    List<Int> l = [1]
    l.clear()
    print(l.length())
    return 0
}
X
run_case List indexRead 5 <<'X'
static Int main() {
    List<Int> l = [5]
    print(l[0])
    return 0
}
X
run_case List indexWrite 6 <<'X'
static Int main() {
    List<Int> l = [5]
    l[0] = 6
    print(l.get(0))
    return 0
}
X

# ---------- Map（§9.5） ----------
run_case Map length 1 <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    print(m.length())
    return 0
}
X
run_case Map put 2 <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    m.put("b", 2)
    print(m.length())
    return 0
}
X
run_case Map get 1 <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    print(m.get("a"))
    return 0
}
X
run_case Map getMissing null <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    Int? v = m.get("z")
    print(v)
    return 0
}
X
run_case Map getOr 0 <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    print(m.getOr("z", 0))
    return 0
}
X
run_case Map has true <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    print(m.has("a"))
    return 0
}
X
run_case Map remove false <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    m.remove("a")
    print(m.has("a"))
    return 0
}
X
run_case Map clear 0 <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    m.clear()
    print(m.length())
    return 0
}
X
run_case Map keys $'1\na' <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    String[] k = m.keys()
    print(k.length())
    print(k[0])
    return 0
}
X
run_case Map values $'1\n1' <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    Int[] v = m.values()
    print(v.length())
    print(v[0])
    return 0
}
X

# ---------- Set（§9.6） ----------
run_case Set length 2 <<'X'
static Int main() {
    Set<Int> s = [1, 2]
    print(s.length())
    return 0
}
X
run_case Set add $'2\ntrue' <<'X'
static Int main() {
    Set<Int> s = [1]
    s.add(2)
    print(s.length())
    print(s.has(2))
    return 0
}
X
run_case Set has true <<'X'
static Int main() {
    Set<Int> s = [1]
    print(s.has(1))
    return 0
}
X
run_case Set at 7 <<'X'
static Int main() {
    Set<Int> s = [7, 8]
    print(s.at(0))
    return 0
}
X
run_case Set remove false <<'X'
static Int main() {
    Set<Int> s = [1]
    s.remove(1)
    print(s.has(1))
    return 0
}
X
run_case Set clear 0 <<'X'
static Int main() {
    Set<Int> s = [1]
    s.clear()
    print(s.length())
    return 0
}
X

{
	echo "phase=$PHASE"
	echo "ops=$OPS"
	echo "cells_total=$TOTAL"
	echo "cells_pass=$PASS_CELLS"
	echo "ops_both_pass=$FULL_OPS"
} > "$OUT/summary.txt"
echo "----"
cat "$OUT/summary.txt"
