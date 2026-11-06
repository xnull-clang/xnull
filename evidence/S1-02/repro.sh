#!/usr/bin/env bash
# S1-02 复现脚本：解释器 break 传播
# 4 类场景，每个 30s 超时；任一超时或输出不符即 FAIL。
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
IMPL="$ROOT/impl"
OUTDIR="$HERE"
WORK="$(mktemp -d "$IMPL/s1-02-repro.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# 解释器入口：临时 main 包（位于模块内，可 import internal/interp）。
cat > "$WORK/main.go" <<'GO'
package main

import (
	"fmt"
	"os"
	"strings"

	"xnull.dev/xnull/internal/interp"
	"xnull.dev/xnull/internal/xfront"
)

func main() {
	src, err := os.ReadFile(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
	u, diags := xfront.ParseUnit(os.Args[1], string(src))
	if len(diags) > 0 {
		for _, d := range diags {
			fmt.Fprintln(os.Stderr, d.String())
		}
		os.Exit(1)
	}
	var out strings.Builder
	code, err := interp.Run(u, &out, nil)
	fmt.Print(out.String())
	if err != nil {
		fmt.Fprintf(os.Stderr, "interp: %v\n", err)
	}
	os.Exit(code)
}
GO

if ! (cd "$IMPL" && go build -o "$WORK/xnrun" "$WORK/main.go") >"$OUTDIR/build.log" 2>&1; then
	echo "FAIL build（详见 build.log）"
	exit 1
fi

# 30s 超时（macOS 无 timeout；Go 运行时忽略 SIGALRM，故由 perl 父进程
# 用 SIGALRM 到点 SIGKILL 子进程，超时返回 137）。
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

pass=0
fail=0
results=()

check() {
	local name="$1" file="$2" want="$3"
	local got code
	got="$(run_limited 30 "$WORK/xnrun" "$file" 2>"$OUTDIR/$name.err")"
	code=$?
	if [ "$code" -eq 137 ] || [ "$code" -eq 142 ]; then
		echo "FAIL $name: 超时（30s，break 未传播）"
		fail=$((fail + 1))
		results+=("$name FAIL timeout")
		return
	fi
	if [ "$got" != "$want" ] || [ "$code" -ne 0 ]; then
		echo "FAIL $name: exit=$code got=$(printf %q "$got") want=$(printf %q "$want")"
		fail=$((fail + 1))
		results+=("$name FAIL exit=$code")
		return
	fi
	echo "PASS $name: $want"
	pass=$((pass + 1))
	results+=("$name PASS")
}

cat > "$WORK/while_direct.xn" <<'XN'
static Int main() {
    Int i = 0
    while true {
        i += 1
        if i == 3 {
            break
        }
    }
    print(i)
    return 0
}
XN
printf '3\n' > "$WORK/while_direct.want"

cat > "$WORK/while_nested_if.xn" <<'XN'
static Int main() {
    Int i = 0
    Int n = 0
    while i < 10 {
        i += 1
        if i > 1 {
            if i == 4 {
                break
            }
        }
        n += 1
    }
    print(i)
    print(n)
    return 0
}
XN
printf '4\n3\n' > "$WORK/while_nested_if.want"

cat > "$WORK/do_while.xn" <<'XN'
static Int main() {
    Int i = 0
    do {
        i += 1
        if i == 3 {
            break
        }
    } while i < 10
    print(i)
    return 0
}
XN
printf '3\n' > "$WORK/do_while.want"

cat > "$WORK/for_in.xn" <<'XN'
static Int main() {
    Int sum = 0
    for i in 0..<10 {
        if i == 3 {
            break
        }
        sum += i
    }
    print(sum)
    return 0
}
XN
printf '3\n' > "$WORK/for_in.want"

for name in while_direct while_nested_if do_while for_in; do
	check "$name" "$WORK/$name.xn" "$(cat "$WORK/$name.want")"
done

echo "----"
echo "S1-02 repro: $pass/4 PASS, $fail FAIL"
[ "$fail" -eq 0 ]
