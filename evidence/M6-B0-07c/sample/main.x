// M6-B0-07c 样例：FFI 句柄 open/close（P-09 注入 + 绑定可见性）。
// 在 sample/ 目录下执行：xnull build main.x -o prog --runtime ../../../impl/runtime
static Int main() {
    File f = fileOpenRead("in.txt")
    fileClose(f)
    print("closed")
    return 0
}
