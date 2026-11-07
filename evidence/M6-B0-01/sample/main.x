// M6-B0-01 样例：调用 .xfb 入口（P-09）。
// 入口来自同目录 bindings/native.xfb：ffiAdd / ffiByteLen。
static Int main() {
    String label = "hello"
    print(str(ffiAdd(2, 3)))
    print(str(ffiByteLen(label)))
    return 0
}
