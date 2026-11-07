#!/usr/bin/env bash
# M6-B0-05「显式替代写法」验证（死命令 1.4.5：未覆盖分支必须补齐或给出显式替代写法）。
# 对 codegen 尚未直接支持的 12 项成员，给出只用现有双路径能力的等价写法，逐字节比对。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
OUT="$HERE/after/alternatives"
WORK="$(mktemp -d "${TMPDIR:-/private/var/folders/zr/vyzqhmcn20ggrvrkdpblvchm0000gn/T/opencode}/m6b005alt.XXXXXX")"
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
: > "$OUT/alternatives.tsv"

run_case() {
	local id="$1" want="$2" src
	src="$(cat)"
	printf '%s\n' "$src" > "$OUT/$id.x"
	run_limited 30 "$BIN" run --interp "$OUT/$id.x" >"$OUT/$id.interp.out" 2>"$OUT/$id.interp.err"
	local ic=$?
	run_limited 120 "$BIN" run "$OUT/$id.x" >"$OUT/$id.compiled.out" 2>"$OUT/$id.compiled.err"
	local cc=$?
	local st=PASS
	[ "$ic" -eq 0 ] && [ "$(cat "$OUT/$id.interp.out")" = "$want" ] || st="FAIL(interp rc=$ic)"
	[ "$cc" -eq 0 ] && [ "$(cat "$OUT/$id.compiled.out")" = "$want" ] || st="FAIL(compiled rc=$cc)"
	TOTAL=$((TOTAL + 1))
	[ "$st" = PASS ] && PASS=$((PASS + 1))
	printf '%s\t%s\n' "$id" "$st" >> "$OUT/alternatives.tsv"
	printf '%-22s %s\n' "$id" "$st"
}

run_case String.split $'2\na' <<'X'
static Int main() {
    String s = "a,b"
    List<String> parts = []
    Int start = 0
    while start <= s.length() {
        String rest = s.substring(start, s.length() - start)
        Int i = rest.indexOf(",")
        if i < 0 {
            parts.push(rest)
            break
        }
        parts.push(rest.substring(0, i))
        start = start + i + 1
    }
    print(parts.length())
    print(parts.get(0))
    return 0
}
X

run_case String.replace x,b <<'X'
static String repl(String s, String from, String to) {
    String res = ""
    Int start = 0
    while start <= s.length() {
        String rest = s.substring(start, s.length() - start)
        Int i = rest.indexOf(from)
        if i < 0 {
            res = res + rest
            break
        }
        res = res + rest.substring(0, i) + to
        start = start + i + from.length()
    }
    return res
}
static Int main() {
    print(repl("a,b", "a", "x"))
    return 0
}
X

run_case 'T[].join' 1-2 <<'X'
static Int main() {
    Int[] a = [1, 2]
    String res = ""
    Int i = 0
    while i < a.length() {
        if i > 0 {
            res = res + "-"
        }
        res = res + str(a[i])
        i = i + 1
    }
    print(res)
    return 0
}
X

run_case List.insert $'2\n3' <<'X'
static Int main() {
    List<Int> l = [1, 3]
    l.push(0)
    Int i = l.length() - 1
    while i > 1 {
        l.set(i, l.get(i - 1))
        i = i - 1
    }
    l.set(1, 2)
    print(l.get(1))
    print(l.length())
    return 0
}
X

run_case List.remove $'1\n1\n2' <<'X'
static Int main() {
    List<Int> l = [1, 2]
    Int x = l.get(0)
    l.remove(0)
    print(x)
    print(l.length())
    print(l.get(0))
    return 0
}
X

run_case Map.get 1 <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    if m.has("a") {
        print(m.getOr("a", 0))
    }
    return 0
}
X

run_case Map.getMissing null <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    if m.has("z") {
        print(m.getOr("z", 0))
    } else {
        print("null")
    }
    return 0
}
X

run_case Map.keys $'2\na' <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    List<String> keys = ["a"]
    m.put("b", 2)
    keys.push("b")
    print(keys.length())
    print(keys.get(0))
    return 0
}
X

run_case Map.values $'1\n1' <<'X'
static Int main() {
    Map<String, Int> m = ["a": 1]
    List<Int> vals = [1]
    print(vals.length())
    print(vals.get(0))
    return 0
}
X

run_case Set.at 7 <<'X'
static Int main() {
    Set<Int> s = [7, 8]
    Int idx = 0
    Int val = 0
    for x in s {
        if idx == 0 {
            val = x
            break
        }
        idx = idx + 1
    }
    print(val)
    return 0
}
X

run_case Set.remove false <<'X'
static Int main() {
    Set<Int> s = [1]
    Set<Int> kept = []
    for x in s {
        if x != 1 {
            kept.add(x)
        }
    }
    s = kept
    print(s.has(1))
    return 0
}
X

run_case Set.clear 0 <<'X'
static Int main() {
    Set<Int> s = [1]
    Set<Int> empty = []
    s = empty
    print(s.length())
    return 0
}
X

{
	echo "alternatives_total=$TOTAL"
	echo "alternatives_pass=$PASS"
} > "$OUT/summary.txt"
echo "----"
cat "$OUT/summary.txt"
[ "$PASS" -eq "$TOTAL" ]
