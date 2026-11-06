// 多文件编译单元示例（M5.2 前置）：入口 import 两个模块，
// 覆盖「主文件调子文件函数」与「子文件类被主文件使用」，并含二级依赖（lib/text → lib/shapes）。
import lib.text
import lib.shapes

static Int main() {
    Point p = new Point();
    p.x = 3;
    p.y = 4;
    print(banner("xnull"));
    print(p.norm2());
    print(describe(p));
    return 0;
}
