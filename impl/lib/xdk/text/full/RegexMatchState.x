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
















































































































































































































































































































































// 分组捕获状态；快照栈支持回溯恢复。
class RegexMatchState {
    List<Int> starts
    List<Int> ends
    List<Int> snap
    List<Int> marks

    RegexMatchState() {
        self.starts = []
        self.ends = []
        self.snap = []
        self.marks = []
    }

    void ensure(Int groupCount) {
        while self.starts.length() < groupCount {
            self.starts.push(-1)
            self.ends.push(-1)
        }
    }

    void pushSnap() {
        self.marks.push(self.snap.length())
        Int i = 0
        while i < self.starts.length() {
            self.snap.push(self.starts.get(i))
            self.snap.push(self.ends.get(i))
            i = i + 1
        }
    }

    void popSnapFail() {
        Int base = self.marks.get(self.marks.length() - 1)
        self.marks.remove(self.marks.length() - 1)
        while self.snap.length() > base {
            self.snap.remove(self.snap.length() - 1)
        }
        Int i = 0
        while i < self.starts.length() {
            self.starts.set(i, self.snap.get(base + i * 2))
            self.ends.set(i, self.snap.get(base + i * 2 + 1))
            i = i + 1
        }
    }

    void popSnapOk() {
        self.marks.remove(self.marks.length() - 1)
        Int i = 0
        while i < self.starts.length() {
            self.snap.remove(self.snap.length() - 1)
            i = i + 1
        }
    }
}
