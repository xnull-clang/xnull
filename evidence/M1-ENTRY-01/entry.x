// M1-ENTRY-01 验收样例：顶层字段初始化顺序 + 两种入口形态 + 退出码 + args。
static Int mark(Int v) {
    print("init " + str(v))
    return v
}

Int a = mark(1)
Int b = mark(a + 1)
String tag = "t" + str(b)

static Int main(final String[] args) {
    print("main " + tag + " args=" + str(args.length()))
    return 7
}
