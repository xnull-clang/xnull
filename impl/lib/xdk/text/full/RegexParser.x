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








































































































































































































































































































































































































































class RegexParser {
    String pattern
    Int pos
    RegexTree t
    Int groupCount
    Bool anchored

    RegexParser(String p) {
        self.pattern = p
        self.pos = 0
        self.t = new RegexTree()
        self.groupCount = 0
        self.anchored = false
    }

    Int peekByte() {
        if self.pos >= self.pattern.length() {
            return -1
        }
        return self.pattern.get(self.pos)
    }

    Bool eatByte(Int b) {
        if self.peekByte() == b {
            self.pos = self.pos + 1
            return true
        }
        return false
    }

    Int escapeByte(Int e) {
        if e == 110 { return 10 }
        if e == 116 { return 9 }
        if e == 114 { return 13 }
        if e == 102 { return 12 }
        if e == 118 { return 11 }
        if e == 48 { return 0 }
        if e == 92 || e == 46 || e == 42 || e == 43 || e == 63 || e == 40 ||
            e == 41 || e == 91 || e == 93 || e == 123 || e == 125 ||
            e == 124 || e == 36 || e == 94 || e == 47 || e == 45 {
            return e
        }
        return -1
    }

    // 向当前（最后一个）类节点追加转义展开。
    void addClassEscape(Int esc) {
        Int last = self.t.negated.length() - 1
        if esc == 100 || esc == 68 {
            self.t.lo.push(48)
            self.t.hi.push(57)
            self.t.singles.push(-1)
            if esc == 68 {
                self.t.negated.set(last, 1)
            }
            return
        }
        if esc == 119 || esc == 87 {
            self.t.lo.push(48)
            self.t.hi.push(57)
            self.t.singles.push(-1)
            self.t.lo.push(97)
            self.t.hi.push(122)
            self.t.singles.push(-1)
            self.t.lo.push(65)
            self.t.hi.push(90)
            self.t.singles.push(-1)
            self.t.singles.push(95)
            if esc == 87 {
                self.t.negated.set(last, 1)
            }
            return
        }
        if esc == 115 || esc == 83 {
            self.t.singles.push(32)
            self.t.singles.push(9)
            self.t.singles.push(10)
            self.t.singles.push(13)
            self.t.singles.push(12)
            self.t.singles.push(11)
            if esc == 83 {
                self.t.negated.set(last, 1)
            }
            return
        }
        self.t.singles.push(esc)
    }

    // 解析字符类（'[' 已消费）；返回类节点下标，失败 -1。
    Int parseClass() {
        Int ni = self.t.addNode(2, "")
        self.t.clsStart.set(ni, self.t.singles.length())
        if self.eatByte(94) {
            self.t.negated.set(ni, 1)
        }
        Bool first = true
        while true {
            Int c = self.peekByte()
            if c < 0 {
                return -1
            }
            if c == 93 && !first {
                self.pos = self.pos + 1
                break
            }
            first = false
            Int lo = -1
            if c == 92 {
                self.pos = self.pos + 1
                Int e = self.peekByte()
                if e < 0 {
                    return -1
                }
                self.pos = self.pos + 1
                if e == 100 || e == 68 || e == 119 || e == 87 || e == 115 || e == 83 {
                    self.addClassEscape(e)
                    continue
                }
                lo = self.escapeByte(e)
            } else {
                lo = c
                self.pos = self.pos + 1
            }
            if lo < 0 {
                return -1
            }
            if self.peekByte() == 45 && self.pos + 1 < self.pattern.length() &&
                self.pattern.get(self.pos + 1) != 93 {
                self.pos = self.pos + 1
                Int hc = self.peekByte()
                Int hi = -1
                if hc == 92 {
                    self.pos = self.pos + 1
                    Int e2 = self.peekByte()
                    self.pos = self.pos + 1
                    hi = self.escapeByte(e2)
                } else {
                    hi = hc
                    self.pos = self.pos + 1
                }
                if hi < lo {
                    return -1
                }
                self.t.lo.push(lo)
                self.t.hi.push(hi)
                self.t.singles.push(-1)
            } else {
                self.t.singles.push(lo)
            }
        }
        self.t.clsCount.set(ni, self.t.singles.length() - self.t.clsStart.get(ni))
        return ni
    }

    Result<Int, Error> parseAtom() {
        Int c = self.peekByte()
        if c == 40 {
            self.pos = self.pos + 1
            Int gi = self.groupCount
            self.groupCount = self.groupCount + 1
            Result<Int, Error> inner = self.parseAlt()
            if inner.isErr() {
                return inner
            }
            if !self.eatByte(41) {
                return Err(textErr("regexCompile: 缺少右括号"))
            }
            Int ni = self.t.addNode(3, "")
            self.t.kidStart.set(ni, inner.value())
            self.t.kidCount.set(ni, 1)
            self.t.groupIds.set(ni, gi)
            return Ok(ni)
        }
        if c == 91 {
            self.pos = self.pos + 1
            Int ni = self.parseClass()
            if ni < 0 {
                return Err(textErr("regexCompile: 字符类非法"))
            }
            return Ok(ni)
        }
        if c == 46 {
            self.pos = self.pos + 1
            return Ok(self.t.addNode(1, "."))
        }
        if c == 92 {
            self.pos = self.pos + 1
            Int e = self.peekByte()
            if e < 0 {
                return Err(textErr("regexCompile: 转义截断"))
            }
            self.pos = self.pos + 1
            if e == 100 || e == 68 || e == 119 || e == 87 || e == 115 || e == 83 {
                Int ni = self.t.addNode(2, "")
                self.t.clsStart.set(ni, self.t.singles.length())
                self.addClassEscape(e)
                self.t.clsCount.set(ni, self.t.singles.length() - self.t.clsStart.get(ni))
                return Ok(ni)
            }
            Int b = self.escapeByte(e)
            if b < 0 {
                return Err(textErr("regexCompile: 非法转义"))
            }
            return Ok(self.t.addNode(0, stringOfByte(b)))
        }
        if c == 41 || c == 124 {
            return Err(textErr("regexCompile: 意外的 ) 或 |"))
        }
        if c == 42 || c == 43 || c == 63 {
            return Err(textErr("regexCompile: 量词缺少原子"))
        }
        self.pos = self.pos + 1
        if c == 36 {
            return Ok(self.t.addNode(0, "$"))
        }
        if c == 94 {
            return Ok(self.t.addNode(0, "^"))
        }
        return Ok(self.t.addNode(0, stringOfByte(c)))
    }

    Result<Int, Error> parseQuantified() {
        Result<Int, Error> atom = self.parseAtom()
        if atom.isErr() {
            return atom
        }
        Int ni = atom.value()
        Int c = self.peekByte()
        if c == 42 {
            self.pos = self.pos + 1
            Int q = self.t.addNode(6, "")
            self.t.kidStart.set(q, ni)
            self.t.kidCount.set(q, 1)
            self.t.minr.set(q, 0)
            self.t.maxr.set(q, 2147483647)
            return Ok(q)
        }
        if c == 43 {
            self.pos = self.pos + 1
            Int q = self.t.addNode(6, "")
            self.t.kidStart.set(q, ni)
            self.t.kidCount.set(q, 1)
            self.t.minr.set(q, 1)
            self.t.maxr.set(q, 2147483647)
            return Ok(q)
        }
        if c == 63 {
            self.pos = self.pos + 1
            Int q = self.t.addNode(6, "")
            self.t.kidStart.set(q, ni)
            self.t.kidCount.set(q, 1)
            self.t.minr.set(q, 0)
            self.t.maxr.set(q, 1)
            return Ok(q)
        }
        return Ok(ni)
    }

    // 把 src 子树复制追加到树尾（seq/alt 收集孩子用）。
    void copyNode(Int src) {
        Int kind = self.t.kinds.get(src)
        Int ni = self.t.addNode(kind, self.t.chs.get(src))
        if kind == 2 {
            self.t.negated.set(ni, self.t.negated.get(src))
            Int cs = self.t.clsStart.get(src)
            Int cc = self.t.clsCount.get(src)
            self.t.clsStart.set(ni, self.t.singles.length())
            Int i = 0
            while i < cc {
                Int j = cs + i
                self.t.lo.push(self.t.lo.get(j))
                self.t.hi.push(self.t.hi.get(j))
                self.t.singles.push(self.t.singles.get(j))
                i = i + 1
            }
            self.t.clsCount.set(ni, cc)
            return
        }
        if kind == 5 || kind == 4 || kind == 3 || kind == 6 {
            Int cs = self.t.kidStart.get(src)
            Int cc = self.t.kidCount.get(src)
            self.t.kidStart.set(ni, self.t.kinds.length())
            Int i = 0
            while i < cc {
                self.copyNode(cs + i)
                i = i + 1
            }
            self.t.kidCount.set(ni, cc)
            self.t.minr.set(ni, self.t.minr.get(src))
            self.t.maxr.set(ni, self.t.maxr.get(src))
            self.t.groupIds.set(ni, self.t.groupIds.get(src))
        }
    }

    Result<Int, Error> parseSeq() {
        List<Int> kids = []
        while true {
            Int c = self.peekByte()
            if c < 0 || c == 41 || c == 124 {
                break
            }
            Result<Int, Error> k = self.parseQuantified()
            if k.isErr() {
                return k
            }
            kids.push(k.value())
        }
        if kids.length() == 0 {
            return Ok(self.t.addNode(7, ""))
        }
        if kids.length() == 1 {
            return Ok(kids.get(0))
        }
        Int ni = self.t.addNode(5, "")
        self.t.kidStart.set(ni, self.t.kinds.length())
        Int i = 0
        while i < kids.length() {
            self.copyNode(kids.get(i))
            i = i + 1
        }
        self.t.kidCount.set(ni, kids.length())
        return Ok(ni)
    }

    Result<Int, Error> parseAlt() {
        Result<Int, Error> first = self.parseSeq()
        if first.isErr() {
            return first
        }
        if self.peekByte() != 124 {
            return first
        }
        List<Int> branches = []
        branches.push(first.value())
        while self.eatByte(124) {
            Result<Int, Error> b = self.parseSeq()
            if b.isErr() {
                return b
            }
            branches.push(b.value())
        }
        if branches.length() == 1 {
            return Ok(branches.get(0))
        }
        Int ni = self.t.addNode(4, "")
        self.t.kidStart.set(ni, self.t.kinds.length())
        Int i = 0
        while i < branches.length() {
            self.copyNode(branches.get(i))
            i = i + 1
        }
        self.t.kidCount.set(ni, branches.length())
        return Ok(ni)
    }
}
