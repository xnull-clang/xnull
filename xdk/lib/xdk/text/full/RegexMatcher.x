// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// POSIX ERE 子集回溯匹配器。字面量与 . 按 UTF-8 码点推进，
// 字符类范围为码点；匹配偏移仍是字节下标。
package xdk.text
import xdk.errors

class RegexMatcher {
    RegexTree t
    String text
    RegexMatchState st

    RegexMatcher(RegexTree tree, String text, Int groupCount) {
        self.t = tree
        self.text = text
        self.st = new RegexMatchState()
        self.st.ensure(groupCount)
    }

    // 结构节点的第 childIndex 个孩子节点。
    Int childAt(Int nodeIndex, Int childIndex) {
        return self.t.kidRefs.get(self.t.kidStart.get(nodeIndex) + childIndex)
    }

    // 序列自 childIndex 起匹配；走完整个序列返回终点，失败 -1。
    Int matchSeq(Int nodeIndex, Int childIndex, Int textIndex) {
        if childIndex >= self.t.kidCount.get(nodeIndex) {
            return textIndex
        }
        Int child = self.childAt(nodeIndex, childIndex)
        Int kind = self.t.kinds.get(child)
        if kind == 6 {
            return self.matchQuantInSeq(nodeIndex, childIndex, child, textIndex)
        }
        if kind == 0 && self.t.chs.get(child) == "^" {
            if textIndex != 0 {
                return -1
            }
            return self.matchSeq(nodeIndex, childIndex + 1, textIndex)
        }
        if kind == 0 && self.t.chs.get(child) == "$" {
            if textIndex != self.text.length() {
                return -1
            }
            return self.matchSeq(nodeIndex, childIndex + 1, textIndex)
        }
        if kind == 3 {
            Int groupIndex = self.t.groupIds.get(child)
            self.st.pushSnap()
            self.st.starts.set(groupIndex, textIndex)
            Int inner = self.matchSeq(child, 0, textIndex)
            if inner < 0 {
                self.st.popSnapFail()
                return -1
            }
            Int rest = self.matchSeq(nodeIndex, childIndex + 1, inner)
            if rest < 0 {
                self.st.popSnapFail()
                return -1
            }
            self.st.ends.set(groupIndex, inner)
            self.st.popSnapOk()
            return rest
        }
        if kind == 4 {
            Int childCount = self.t.kidCount.get(child)
            Int branch = 0
            while branch < childCount {
                self.st.pushSnap()
                Int inner = self.matchSeq(self.childAt(child, branch), 0, textIndex)
                if inner >= 0 {
                    Int rest = self.matchSeq(nodeIndex, childIndex + 1, inner)
                    if rest >= 0 {
                        self.st.popSnapOk()
                        return rest
                    }
                }
                self.st.popSnapFail()
                branch = branch + 1
            }
            return -1
        }
        if kind == 5 {
            Int inner = self.matchSeq(child, 0, textIndex)
            if inner < 0 {
                return -1
            }
            return self.matchSeq(nodeIndex, childIndex + 1, inner)
        }
        if kind == 7 {
            return self.matchSeq(nodeIndex, childIndex + 1, textIndex)
        }
        Int next = self.matchLeaf(child, textIndex)
        if next < 0 {
            return -1
        }
        return self.matchSeq(nodeIndex, childIndex + 1, next)
    }

    // 单叶节点（char/any/class）匹配一次；返回终点或 -1。
    Int matchLeaf(Int nodeIndex, Int textIndex) {
        if textIndex >= self.text.length() {
            return -1
        }
        Int kind = self.t.kinds.get(nodeIndex)
        if kind == 1 {
            Int length = codePointLen(self.text, textIndex)
            if length < 0 {
                return -1
            }
            return textIndex + length
        }
        if kind == 0 {
            String unit = self.t.chs.get(nodeIndex)
            if textIndex + unit.length() > self.text.length() {
                return -1
            }
            if self.text.substring(textIndex, unit.length()) == unit {
                return textIndex + unit.length()
            }
            return -1
        }
        Int codePoint = decodeCodePoint(self.text, textIndex)
        if codePoint < 0 {
            return -1
        }
        if regexClassMatch(self.t, nodeIndex, codePoint) {
            return textIndex + codePointLen(self.text, textIndex)
        }
        return -1
    }

    // 序列内量词：以可连续匹配次数为上界，从上界向 min 枚举（贪心）。
    Int matchQuantInSeq(Int seqNode, Int childIndex, Int quantifier, Int textIndex) {
        Int child = self.childAt(quantifier, 0)
        Int minimum = self.t.minr.get(quantifier)
        Int maximum = self.t.maxr.get(quantifier)
        self.st.pushSnap()
        Int bound = self.maxReps(child, textIndex, maximum)
        self.st.popSnapFail()
        Int count = bound
        while count >= minimum {
            self.st.pushSnap()
            Int end = self.repCount(child, count, seqNode, childIndex, textIndex)
            if end >= 0 {
                self.st.popSnapOk()
                return end
            }
            self.st.popSnapFail()
            count = count - 1
        }
        return -1
    }

    // 从 textIndex 起连续匹配 child 的最大次数（≤maximum；零宽即停）。
    Int maxReps(Int child, Int textIndex, Int maximum) {
        Int position = textIndex
        Int count = 0
        while count < maximum {
            Int end = self.matchOne(child, position)
            if end < 0 || end == position {
                return count
            }
            position = end
            count = count + 1
        }
        return maximum
    }

    // 精确匹配 child 共 count 次后接续 seq 的 childIndex+1。
    Int repCount(Int child, Int count, Int seqNode, Int childIndex, Int textIndex) {
        if count == 0 {
            return self.matchSeq(seqNode, childIndex + 1, textIndex)
        }
        Int end = self.matchOne(child, textIndex)
        if end < 0 {
            return -1
        }
        if end == textIndex {
            return self.matchSeq(seqNode, childIndex + 1, textIndex)
        }
        return self.repCount(child, count - 1, seqNode, childIndex, end)
    }

    // 单个节点完整匹配一次；返回终点或 -1。
    Int matchOne(Int nodeIndex, Int textIndex) {
        Int kind = self.t.kinds.get(nodeIndex)
        if kind == 7 {
            return textIndex
        }
        if kind == 0 && self.t.chs.get(nodeIndex) == "^" {
            return textIndex == 0 ? textIndex : -1
        }
        if kind == 0 && self.t.chs.get(nodeIndex) == "$" {
            return textIndex == self.text.length() ? textIndex : -1
        }
        if kind == 3 {
            Int groupIndex = self.t.groupIds.get(nodeIndex)
            self.st.pushSnap()
            self.st.starts.set(groupIndex, textIndex)
            Int inner = self.matchSeq(nodeIndex, 0, textIndex)
            if inner < 0 {
                self.st.popSnapFail()
                return -1
            }
            self.st.ends.set(groupIndex, inner)
            self.st.popSnapOk()
            return inner
        }
        if kind == 4 {
            Int childCount = self.t.kidCount.get(nodeIndex)
            Int branch = 0
            while branch < childCount {
                self.st.pushSnap()
                Int inner = self.matchSeq(self.childAt(nodeIndex, branch), 0, textIndex)
                if inner >= 0 {
                    self.st.popSnapOk()
                    return inner
                }
                self.st.popSnapFail()
                branch = branch + 1
            }
            return -1
        }
        if kind == 5 {
            return self.matchSeq(nodeIndex, 0, textIndex)
        }
        if kind == 6 {
            Int child = self.childAt(nodeIndex, 0)
            Int minimum = self.t.minr.get(nodeIndex)
            Int maximum = self.t.maxr.get(nodeIndex)
            self.st.pushSnap()
            Int bound = self.maxReps(child, textIndex, maximum)
            self.st.popSnapFail()
            Int count = bound
            while count >= minimum {
                Int end = self.repCountRoot(child, count, textIndex)
                if end >= 0 {
                    return end
                }
                count = count - 1
            }
            return -1
        }
        return self.matchLeaf(nodeIndex, textIndex)
    }

    // 量词单独出现时的精确重复（无接续）。
    Int repCountRoot(Int child, Int count, Int textIndex) {
        if count == 0 {
            return textIndex
        }
        Int end = self.matchOne(child, textIndex)
        if end < 0 {
            return -1
        }
        if end == textIndex {
            return textIndex
        }
        return self.repCountRoot(child, count - 1, end)
    }
}
