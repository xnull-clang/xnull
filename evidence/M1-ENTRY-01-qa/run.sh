#!/bin/bash
# CEO3-QA2 独立验收 ENTRY-01：临时目录运行，不改仓库。
set -u
T=/private/var/folders/zr/vyzqhmcn20ggrvrkdpblvchm0000gn/T/opencode/entry-qa
XN="$T/xnull"
export XNULL_RUNTIME="$T/src/impl/runtime"
C="$T/cases"
OUT="$T/out"
rm -rf "$OUT"; mkdir -p "$OUT" "$C"
cd "$T" || exit 1

# ---------- 用例源码 ----------
cat > "$C/a1_void_noarg.x" <<'EOF'
static void main() {
    print("v0")
}
EOF
cat > "$C/a2_int_noarg.x" <<'EOF'
static Int main() {
    print("i0")
    return 7
}
EOF
cat > "$C/a3_void_args.x" <<'EOF'
static void main(final String[] args) {
    print("va " + str(args.length()))
}
EOF
cat > "$C/a4_int_args.x" <<'EOF'
static Int main(final String[] args) {
    print("ia " + str(args.length()))
    return 5
}
EOF
for n in 0 1 42 255 256 300; do
cat > "$C/b_exit$n.x" <<EOF
static Int main() {
    return $n
}
EOF
done
cat > "$C/b_exit_neg1.x" <<'EOF'
static Int main() {
    return -1
}
EOF
cat > "$C/c1_init_order.x" <<'EOF'
static Int mark(Int v) {
    print("init " + str(v))
    return v
}
Int a = mark(1)
Int b = mark(a + 1)
static Int main() {
    print("main " + str(b))
    return 0
}
EOF
cat > "$C/c2_forward_zero.x" <<'EOF'
Int b = a + 1
Int a = 5
static Int main() {
    print("a=" + str(a) + " b=" + str(b))
    return 0
}
EOF
cat > "$C/c3_init_fatal.x" <<'EOF'
Int a = 1 / 0
static Int main() {
    print("MAIN-SHOULD-NOT-RUN")
    return 0
}
EOF
cat > "$C/c4_fields_order.x" <<'EOF'
static Bool seen() {
    return true
}
Bool b = seen()
String s = "top"
Int i = 3
static Int main() {
    print(str(b) + " " + s + " " + str(i))
    return 0
}
EOF
cat > "$C/c5_init_calls_func.x" <<'EOF'
Int a = 1
Int b = read()
static Int read() {
    print("read a=" + str(a))
    return 2
}
static Int main() {
    print("main b=" + str(b))
    return 0
}
EOF
cat > "$C/c6_init_reads_future.x" <<'EOF'
Int b = read()
static Int read() {
    print("read c=" + str(c))
    return 2
}
Int c = 9
static Int main() {
    print("main c=" + str(c))
    return 0
}
EOF
cat > "$C/d1_args_dump.x" <<'EOF'
static Int main(final String[] args) {
    print("n=" + str(args.length()))
    for a in args {
        print("ARG")
        print(a)
    }
    return 0
}
EOF
cat > "$C/e1_missing_main.x" <<'EOF'
static Int helper() {
    return 1
}
EOF
cat > "$C/e2_dup_same.x" <<'EOF'
static Int main() {
    return 0
}
static Int main() {
    return 1
}
EOF
cat > "$C/e3_dup_overload.x" <<'EOF'
static Int main() {
    print("entry")
    return 0
}
static Int main(Int x) {
    return x + 1
}
EOF
cat > "$C/e4_nonstatic.x" <<'EOF'
Int main() {
    return 0
}
EOF
cat > "$C/e5_ret_string.x" <<'EOF'
static String main() {
    return "x"
}
EOF
cat > "$C/e6_ret_bool.x" <<'EOF'
static Bool main() {
    return true
}
EOF
cat > "$C/e7_param_int.x" <<'EOF'
static Int main(Int x) {
    return x
}
EOF
cat > "$C/e8_two_params.x" <<'EOF'
static Int main(String[] a, Int b) {
    return 0
}
EOF
cat > "$C/e9_param_string.x" <<'EOF'
static Int main(String a) {
    return 0
}
EOF
cat > "$C/e10_private_main.x" <<'EOF'
private static Int main() {
    return 0
}
EOF
cat > "$C/e11_generic_main.x" <<'EOF'
static Int main<Int>() {
    return 0
}
EOF

# ---------- 运行器 ----------
run_case() { # name path extra-args...
  name=$1; shift
  path=$1; shift
  for mode in interp compiled; do
    if [ "$mode" = interp ]; then
      "$XN" run "$path" --interp "$@" >"$OUT/$name.$mode.out" 2>"$OUT/$name.$mode.err"; rc=$?
    else
      "$XN" run "$path" "$@" >"$OUT/$name.$mode.out" 2>"$OUT/$name.$mode.err"; rc=$?
    fi
    printf '%s\t%s\trc=%d\tout=%s\terr=%s\n' "$name" "$mode" "$rc" \
      "$(tr '\n' '|' < "$OUT/$name.$mode.out")" \
      "$(head -2 "$OUT/$name.$mode.err" | tr '\n' '|')"
  done
}

echo "===== A 四形态 ====="
run_case a1 "$C/a1_void_noarg.x"
run_case a2 "$C/a2_int_noarg.x"
run_case a3 "$C/a3_void_args.x"
run_case a4 "$C/a4_int_args.x" alpha beta

echo "===== B 退出码 ====="
for n in 0 1 42 255 256 300; do run_case "b$n" "$C/b_exit$n.x"; done
run_case b_neg1 "$C/b_exit_neg1.x"

echo "===== C 初始化顺序 ====="
for c in c1_init_order c2_forward_zero c3_init_fatal c4_fields_order c5_init_calls_func c6_init_reads_future; do
  run_case "$c" "$C/$c.x"
done

echo "===== D args ====="
run_case d0 "$C/d1_args_dump.x"
run_case d2 "$C/d1_args_dump.x" alpha beta
run_case ddash "$C/d1_args_dump.x" -x beta

echo "===== E 负例 ====="
for e in e1_missing_main e2_dup_same e3_dup_overload e4_nonstatic e5_ret_string e6_ret_bool e7_param_int e8_two_params e9_param_string e10_private_main e11_generic_main; do
  run_case "$e" "$C/$e.x"
done
