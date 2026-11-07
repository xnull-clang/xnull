// 解释路径 oracle：纯 XNull 等价程序（解释器无 FFI 面，属 E3 域）。
static Int add(Int a, Int b) { return a + b }
static Int byteLen(String s) { return s.length() }

static Int main() {
    String label = "hello"
    print(str(add(2, 3)))
    print(str(byteLen(label)))
    return 0
}
