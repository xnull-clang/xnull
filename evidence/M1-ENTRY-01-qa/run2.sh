#!/bin/bash
set -u
T=/private/var/folders/zr/vyzqhmcn20ggrvrkdpblvchm0000gn/T/opencode/entry-qa
XN="$T/xnull"
export XNULL_RUNTIME="$T/src/impl/runtime"
C="$T/cases"; OUT="$T/out"
cd "$T" || exit 1

cat > "$C/c7_runtime_divzero.x" <<'EOF'
Int d = 0
Int a = 10 / d
static Int main() {
    print("MAIN-SHOULD-NOT-RUN")
    return 0
}
EOF
cat > "$C/c8_bool_print.x" <<'EOF'
Bool b = true
static Int main() {
    print(b)
    print(str(b))
    print(str(false))
    return 0
}
EOF
cat > "$C/c9_str_bool_main.x" <<'EOF'
static Int main() {
    Bool t = true
    print("s=" + str(t))
    print("raw=" + str(1 == 1))
    return 0
}
EOF
cat > "$C/c10_init_order_3.x" <<'EOF'
static Int mark(Int v) {
    print("m" + str(v))
    return v
}
Int a = mark(10)
Int b = mark(a + 10)
String s = "s"
Int c = mark(b + 10)
static Int main() {
    print("main " + str(a) + "," + str(b) + "," + str(c) + "," + s)
    return 0
}
EOF
cat > "$C/c11_init_void_call.x" <<'EOF'
static void note() {
    print("note")
}
Int a = 1
Int b = 2
static Int main() {
    print("main")
    return 0
}
EOF

run_case() {
  name=$1; shift; path=$1; shift
  for mode in interp compiled; do
    if [ "$mode" = interp ]; then
      "$XN" run "$path" --interp "$@" >"$OUT/$name.$mode.out" 2>"$OUT/$name.$mode.err"; rc=$?
    else
      "$XN" run "$path" "$@" >"$OUT/$name.$mode.out" 2>"$OUT/$name.$mode.err"; rc=$?
    fi
    printf '%s\t%s\trc=%d\tout=%s\terr=%s\n' "$name" "$mode" "$rc" \
      "$(tr '\n' '|' < "$OUT/$name.$mode.out")" \
      "$(head -3 "$OUT/$name.$mode.err" | tr '\n' '|')"
  done
}

for c in c7_runtime_divzero c8_bool_print c9_str_bool_main c10_init_order_3 c11_init_void_call; do
  run_case "$c" "$C/$c.x"
done
