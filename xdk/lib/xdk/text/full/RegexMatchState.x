// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 分组捕获状态；快照栈支持回溯恢复。每个快照保存所有组的起点/终点。
package xdk.text
import xdk.errors

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
        Int index = 0
        while index < self.starts.length() {
            self.snap.push(self.starts.get(index))
            self.snap.push(self.ends.get(index))
            index = index + 1
        }
    }

    void popSnapFail() {
        Int base = self.marks.get(self.marks.length() - 1)
        self.marks.remove(self.marks.length() - 1)
        Int index = 0
        while index < self.starts.length() {
            self.starts.set(index, self.snap.get(base + index * 2))
            self.ends.set(index, self.snap.get(base + index * 2 + 1))
            index = index + 1
        }
        while self.snap.length() > base {
            self.snap.remove(self.snap.length() - 1)
        }
    }

    void popSnapOk() {
        Int base = self.marks.get(self.marks.length() - 1)
        self.marks.remove(self.marks.length() - 1)
        while self.snap.length() > base {
            self.snap.remove(self.snap.length() - 1)
        }
    }
}
