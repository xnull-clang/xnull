// t00 基线：文本变体（B0-07b）已经可用，用来证明测试包/执行器本身正常。
// 不用 readFileText 的 null 分支：E4 当前主线尚未支持 String == null（M4.1 范围）。
import xdk.sys

static Int main() {
    String outPath = "out.txt"
    String text = "hello\n"
    Int w = writeFileText(outPath, text)
    if (w != 0) {
        return 22
    }
    return 0
}
