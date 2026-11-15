// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 与 src/xdk/text.x（默认构建面）同源；追加顶层工厂与 Utf16 包装。
// 默认构建不加载本单元，避免改变冻结 golden。
//
// 依赖：xdk.errors（错误值）；C 原语对应 src/runtime/rt_std_text.c
// （parse_int/parse_float/utf8_to_utf16/utf16_to_utf8/regex_match；解释器路径由等价源码执行）。
// 稳定性：@preview。
// 合同：可失败操作返回 Result；Regex 动态编译失败是可恢复错误，不 panic。
package xdk.text
import xdk.errors

// ---------- 格式化 builder ----------

// Format：链式格式化构造器（Format.int(7).width(4).pad('0').build()）。












































































































































































































































































































































































































































































































































































































































































































































































































class RegexMatcher {
    RegexTree t
    String text
    RegexMatchState st

    RegexMatcher(RegexTree t0, String text0, Int groupCount) {
        self.t = t0
        self.text = text0
        self.st = new RegexMatchState()
        self.st.ensure(groupCount)
    }

    // 序列自 ki 起匹配；走完整个序列返回终点 ti'，失败 -1。
    Int matchSeq(Int ni, Int ki, Int ti) {
        if ki >= self.t.kidCount.get(ni) {
            return ti
        }
        Int child = self.t.kidStart.get(ni) + ki
        Int ck = self.t.kinds.get(child)
        if ck == 6 {
            return self.matchQuantInSeq(ni, ki, child, ti)
        }
        if ck == 0 && self.t.chs.get(child) == "^" {
            if ti != 0 {
                return -1
            }
            return self.matchSeq(ni, ki + 1, ti)
        }
        if ck == 0 && self.t.chs.get(child) == "$" {
            if ti != self.text.length() {
                return -1
            }
            return self.matchSeq(ni, ki + 1, ti)
        }
        if ck == 3 {
            Int gi = self.t.groupIds.get(child)
            self.st.pushSnap()
            self.st.starts.set(gi, ti)
            Int inner = self.matchSeq(child, 0, ti)
            if inner < 0 {
                self.st.popSnapFail()
                return -1
            }
            Int rest = self.matchSeq(ni, ki + 1, inner)
            if rest < 0 {
                self.st.popSnapFail()
                return -1
            }
            self.st.ends.set(gi, inner)
            self.st.popSnapOk()
            return rest
        }
        if ck == 4 {
            Int ks = self.t.kidStart.get(child)
            Int kc = self.t.kidCount.get(child)
            Int b = 0
            while b < kc {
                self.st.pushSnap()
                Int inner = self.matchSeq(ks + b, 0, ti)
                if inner >= 0 {
                    Int rest = self.matchSeq(ni, ki + 1, inner)
                    if rest >= 0 {
                        self.st.popSnapOk()
                        return rest
                    }
                }
                self.st.popSnapFail()
                b = b + 1
            }
            return -1
        }
        if ck == 5 {
            Int inner = self.matchSeq(child, 0, ti)
            if inner < 0 {
                return -1
            }
            return self.matchSeq(ni, ki + 1, inner)
        }
        if ck == 7 {
            return self.matchSeq(ni, ki + 1, ti)
        }
        // 单字符原子：0=char 1=any 2=class
        if ti >= self.text.length() {
            return -1
        }
        Int byte = self.text.get(ti)
        Bool ok = false
        if ck == 1 {
            ok = true
        } else if ck == 0 {
            ok = self.t.chs.get(child).get(0) == byte
        } else {
            ok = regexClassMatch(self.t, child, byte)
        }
        if !ok {
            return -1
        }
        return self.matchSeq(ni, ki + 1, ti + 1)
    }

    // 序列内量词：以可连续匹配次数为上界，从上界向 min 枚举（贪心）。
    Int matchQuantInSeq(Int seqNi, Int ki, Int qni, Int ti) {
        Int child = self.t.kidStart.get(qni)
        Int min = self.t.minr.get(qni)
        Int max = self.t.maxr.get(qni)
        self.st.pushSnap()
        Int bound = self.maxReps(child, ti, max)
        self.st.popSnapFail()
        Int cnt = bound
        while cnt >= min {
            self.st.pushSnap()
            Int end = self.repCount(child, cnt, seqNi, ki, ti)
            if end >= 0 {
                self.st.popSnapOk()
                return end
            }
            self.st.popSnapFail()
            cnt = cnt - 1
        }
        return -1
    }

    // 从 ti 起连续匹配 child 的最大次数（≤max；零宽即停）。
    Int maxReps(Int child, Int ti, Int max) {
        Int pos = ti
        Int n = 0
        while n < max {
            Int end = self.matchOne(child, pos)
            if end < 0 || end == pos {
                return n
            }
            pos = end
            n = n + 1
        }
        return max
    }

    // 精确匹配 child 共 cnt 次后接续 seq 的 ki+1。
    Int repCount(Int child, Int cnt, Int seqNi, Int ki, Int ti) {
        if cnt == 0 {
            return self.matchSeq(seqNi, ki + 1, ti)
        }
        Int end = self.matchOne(child, ti)
        if end < 0 {
            return -1
        }
        if end == ti {
            // 零宽原子：剩余重复按零宽满足，直接接续
            return self.matchSeq(seqNi, ki + 1, ti)
        }
        return self.repCount(child, cnt - 1, seqNi, ki, end)
    }

    // 单个节点完整匹配一次；返回终点或 -1。
    Int matchOne(Int ni, Int ti) {
        Int k = self.t.kinds.get(ni)
        if k == 7 {
            return ti
        }
        if k == 0 && self.t.chs.get(ni) == "^" {
            return ti == 0 ? ti : -1
        }
        if k == 0 && self.t.chs.get(ni) == "$" {
            return ti == self.text.length() ? ti : -1
        }
        if k == 3 {
            Int gi = self.t.groupIds.get(ni)
            self.st.pushSnap()
            self.st.starts.set(gi, ti)
            Int inner = self.matchSeq(ni, 0, ti)
            if inner < 0 {
                self.st.popSnapFail()
                return -1
            }
            self.st.ends.set(gi, inner)
            self.st.popSnapOk()
            return inner
        }
        if k == 4 {
            Int ks = self.t.kidStart.get(ni)
            Int kc = self.t.kidCount.get(ni)
            Int b = 0
            while b < kc {
                self.st.pushSnap()
                Int inner = self.matchSeq(ks + b, 0, ti)
                if inner >= 0 {
                    self.st.popSnapOk()
                    return inner
                }
                self.st.popSnapFail()
                b = b + 1
            }
            return -1
        }
        if k == 5 {
            return self.matchSeq(ni, 0, ti)
        }
        if k == 6 {
            Int child = self.t.kidStart.get(ni)
            Int min = self.t.minr.get(ni)
            Int max = self.t.maxr.get(ni)
            self.st.pushSnap()
            Int bound = self.maxReps(child, ti, max)
            self.st.popSnapFail()
            Int cnt = bound
            while cnt >= min {
                Int end = self.repCountRoot(child, cnt, ti)
                if end >= 0 {
                    return end
                }
                cnt = cnt - 1
            }
            return -1
        }
        if ti >= self.text.length() {
            return -1
        }
        Int byte = self.text.get(ti)
        if k == 1 {
            return ti + 1
        }
        if k == 0 {
            if self.t.chs.get(ni).get(0) == byte {
                return ti + 1
            }
            return -1
        }
        if regexClassMatch(self.t, ni, byte) {
            return ti + 1
        }
        return -1
    }

    // 量词单独出现时的精确重复（无接续）。
    Int repCountRoot(Int child, Int cnt, Int ti) {
        if cnt == 0 {
            return ti
        }
        Int end = self.matchOne(child, ti)
        if end < 0 {
            return -1
        }
        if end == ti {
            return ti
        }
        return self.repCountRoot(child, cnt - 1, end)
    }
}
