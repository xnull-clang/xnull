// M6-B0-03 样例：两包/三包跨包 import（入口 -> lib.b -> lib.a）。
import lib.b

static Int main() {
    print(banner("x"))
    print(twice(3))
    return 0
}
