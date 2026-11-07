// t03 数值标量：Int32/Int64 的变量、字面量、算术与比较（无 FFI，先隔离 codegen）。
// 语义：Int32 存 32 位有符号，Int64 存 64 位有符号；同族同宽比较（B0-07a sema 已落地）。
static Int main() {
    Int32 lo = -2147483648
    Int32 hi = 2147483647
    if (lo >= hi) {
        return 31
    }

    Int32 a = 123
    Int32 c = a + 7
    if (c != 130) {
        return 32
    }

    Int64 b = 4567890123
    Int64 d = b + 7
    if (d != 4567890130) {
        return 33
    }

    if (a >= c) {
        return 34
    }
    if (b >= d) {
        return 35
    }
    return 0
}
