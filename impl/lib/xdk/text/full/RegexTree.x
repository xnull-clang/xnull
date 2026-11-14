// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 与 impl/lib/xdk/text.x（默认构建面）同源；追加顶层工厂与 Utf16 包装。
// 默认构建不加载本单元，避免改变冻结 golden。
//
// 依赖：xdk.errors（错误值）；C 原语对应 impl/runtime/rt_std_text.c
// （parse_int/parse_float/utf8_to_utf16/utf16_to_utf8/regex_match；解释器路径由等价源码执行）。
// 稳定性：@preview。
// 合同：可失败操作返回 Result；Regex 动态编译失败是可恢复错误，不 panic。
package xdk.text
import xdk.errors

// ---------- 格式化 builder ----------

// Format：链式格式化构造器（Format.int(7).width(4).pad('0').build()）。


































































































































































































































































































class RegexTree {
    List<Int> kinds        // 0=char 1=any 2=class 3=group 4=alt 5=seq 6=quant 7=empty
    List<String> chs
    List<Int> kidStart
    List<Int> kidCount
    List<Int> minr
    List<Int> maxr
    List<Int> negated
    List<Int> lo
    List<Int> hi
    List<Int> singles
    List<Int> clsStart
    List<Int> clsCount
    List<Int> groupIds

    RegexTree() {
        self.kinds = []
        self.chs = []
        self.kidStart = []
        self.kidCount = []
        self.minr = []
        self.maxr = []
        self.negated = []
        self.lo = []
        self.hi = []
        self.singles = []
        self.clsStart = []
        self.clsCount = []
        self.groupIds = []
    }

    Int addNode(Int kind, String ch) {
        self.kinds.push(kind)
        self.chs.push(ch)
        self.kidStart.push(0)
        self.kidCount.push(0)
        self.minr.push(0)
        self.maxr.push(0)
        self.negated.push(0)
        self.clsStart.push(0)
        self.clsCount.push(0)
        self.groupIds.push(-1)
        return self.kinds.length() - 1
    }
}
