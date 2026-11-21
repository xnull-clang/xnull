// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// POSIX ERE 子集解析器：字面量、.、* + ?、{m} {m,} {m,n}、字符类与
// POSIX 名字类、分组捕获、|、转义、^ $。语法错误返回 InvalidArgument。
package xdk.text
import xdk.errors

// 量词上界（与 Int 32 位一致）。
static Int regexMaxRepeat() {
    return 2147483647
}

class RegexParser {
    String pattern
    Int pos
    RegexTree t
    Int groupCount
    Bool anchored

    RegexParser(String pattern) {
        self.pattern = pattern
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

    Bool eatByte(Int byteValue) {
        if self.peekByte() == byteValue {
            self.pos = self.pos + 1
            return true
        }
        return false
    }

    // 读取一个完整 UTF-8 码点；非法返回 -1。
    Int readCodePoint() {
        if self.pos >= self.pattern.length() {
            return -1
        }
        Int codePoint = decodeCodePoint(self.pattern, self.pos)
        if codePoint < 0 {
            return -1
        }
        self.pos = self.pos + codePointLen(self.pattern, self.pos)
        return codePoint
    }

    Int escapeCodePoint(Int escaped) {
        if escaped == 110 { return 10 }
        if escaped == 116 { return 9 }
        if escaped == 114 { return 13 }
        if escaped == 102 { return 12 }
        if escaped == 118 { return 11 }
        if escaped == 48 { return 0 }
        if escaped == 92 || escaped == 46 || escaped == 42 || escaped == 43 || escaped == 63 ||
            escaped == 40 || escaped == 41 || escaped == 91 || escaped == 93 ||
            escaped == 123 || escaped == 125 || escaped == 124 || escaped == 36 ||
            escaped == 94 || escaped == 47 || escaped == 45 {
            return escaped
        }
        return -1
    }

    Bool isClassEscape(Int escaped) {
        return escaped == 100 || escaped == 68 || escaped == 119 || escaped == 87 ||
            escaped == 115 || escaped == 83
    }

    void addRange(Int low, Int high) {
        self.t.lo.push(low)
        self.t.hi.push(high)
        self.t.singles.push(-1)
    }

    void addSingle(Int value) {
        self.t.lo.push(value)
        self.t.hi.push(value)
        self.t.singles.push(value)
    }

    // 向当前（最后一个）类节点追加转义展开。范围用码点表示。
    void addClassEscape(Int escaped) {
        if escaped == 100 {
            self.addRange(48, 57)
            return
        }
        if escaped == 68 {
            self.addRange(0, 47)
            self.addRange(58, 1114111)
            return
        }
        if escaped == 119 {
            self.addRange(48, 57)
            self.addRange(65, 90)
            self.addRange(97, 122)
            self.addSingle(95)
            return
        }
        if escaped == 87 {
            self.addRange(0, 47)
            self.addRange(58, 64)
            self.addRange(91, 94)
            self.addSingle(96)
            self.addRange(123, 1114111)
            return
        }
        if escaped == 115 {
            self.addSingle(32)
            self.addSingle(9)
            self.addSingle(10)
            self.addSingle(13)
            self.addSingle(12)
            self.addSingle(11)
            return
        }
        if escaped == 83 {
            self.addRange(0, 8)
            self.addRange(14, 31)
            self.addRange(33, 1114111)
            return
        }
        self.addSingle(escaped)
    }

    // POSIX 名字类 [[:alpha:]]；返回 1=已识别、0=不是该形式、-1=未知名字。
    Int parsePosixClass() {
        if self.peekByte() != 91 {
            return 0
        }
        if self.pos + 1 >= self.pattern.length() || self.pattern.get(self.pos + 1) != 58 {
            return 0
        }
        Int nameStart = self.pos + 2
        Int scan = nameStart
        Int close = -1
        while scan < self.pattern.length() {
            if self.pattern.get(scan) == 58 && scan + 1 < self.pattern.length() &&
                self.pattern.get(scan + 1) == 93 {
                close = scan
                break
            }
            scan = scan + 1
        }
        if close < 0 {
            return 0
        }
        String name = self.pattern.substring(nameStart, close - nameStart)
        self.pos = close + 2
        if name == "alnum" {
            self.addRange(48, 57)
            self.addRange(65, 90)
            self.addRange(97, 122)
            return 1
        }
        if name == "alpha" {
            self.addRange(65, 90)
            self.addRange(97, 122)
            return 1
        }
        if name == "blank" {
            self.addSingle(32)
            self.addSingle(9)
            return 1
        }
        if name == "cntrl" {
            self.addRange(0, 31)
            self.addSingle(127)
            return 1
        }
        if name == "digit" {
            self.addRange(48, 57)
            return 1
        }
        if name == "graph" {
            self.addRange(33, 126)
            return 1
        }
        if name == "lower" {
            self.addRange(97, 122)
            return 1
        }
        if name == "print" {
            self.addRange(32, 126)
            return 1
        }
        if name == "punct" {
            self.addRange(33, 47)
            self.addRange(58, 64)
            self.addRange(91, 96)
            self.addRange(123, 126)
            return 1
        }
        if name == "space" {
            self.addSingle(9)
            self.addSingle(10)
            self.addSingle(11)
            self.addSingle(12)
            self.addSingle(13)
            self.addSingle(32)
            return 1
        }
        if name == "upper" {
            self.addRange(65, 90)
            return 1
        }
        if name == "xdigit" {
            self.addRange(48, 57)
            self.addRange(65, 70)
            self.addRange(97, 102)
            return 1
        }
        return -1
    }

    Bool isRangeStart() {
        if self.peekByte() != 45 {
            return false
        }
        if self.pos + 1 >= self.pattern.length() {
            return false
        }
        if self.pattern.get(self.pos + 1) == 93 {
            return false
        }
        return true
    }

    // 读取类中的一个端点；转义名字类不能作为区间端点（返回 -1）。
    Int readClassEndpoint() {
        Int current = self.peekByte()
        if current < 0 {
            return -1
        }
        if current == 92 {
            self.pos = self.pos + 1
            Int escaped = self.peekByte()
            if escaped < 0 {
                return -1
            }
            self.pos = self.pos + 1
            if self.isClassEscape(escaped) {
                return -1
            }
            return self.escapeCodePoint(escaped)
        }
        return self.readCodePoint()
    }

    // 解析字符类（'[' 已消费）；返回类节点下标，失败 -1。
    Int parseClass() {
        Int node = self.t.addNode(2, "")
        self.t.clsStart.set(node, self.t.lo.length())
        if self.eatByte(94) {
            self.t.negated.set(node, 1)
        }
        Bool first = true
        while true {
            Int current = self.peekByte()
            if current < 0 {
                return -1
            }
            if current == 93 && !first {
                self.pos = self.pos + 1
                break
            }
            first = false
            if current == 91 {
                Int posix = self.parsePosixClass()
                if posix < 0 {
                    return -1
                }
                if posix > 0 {
                    continue
                }
            }
            Int low = self.readClassEndpoint()
            if low < 0 {
                return -1
            }
            if self.isRangeStart() {
                self.pos = self.pos + 1
                Int high = self.readClassEndpoint()
                if high < 0 || high < low {
                    return -1
                }
                self.addRange(low, high)
            } else {
                self.addSingle(low)
            }
        }
        self.t.clsCount.set(node, self.t.lo.length() - self.t.clsStart.get(node))
        return node
    }

    Result<Int, Error> parseAtom() {
        Int current = self.peekByte()
        if current == 40 {
            self.pos = self.pos + 1
            Int groupIndex = self.groupCount
            self.groupCount = self.groupCount + 1
            Result<Int, Error> inner = self.parseAlt()
            if inner.isErr() {
                return inner
            }
            if !self.eatByte(41) {
                return Err(textErr("regexCompile: 缺少右括号"))
            }
            Int node = self.t.addNode(3, "")
            self.t.kidStart.set(node, self.t.kidRefs.length())
            self.t.kidRefs.push(inner.value())
            self.t.kidCount.set(node, 1)
            self.t.groupIds.set(node, groupIndex)
            return Ok(node)
        }
        if current == 91 {
            self.pos = self.pos + 1
            Int node = self.parseClass()
            if node < 0 {
                return Err(textErr("regexCompile: 字符类非法"))
            }
            return Ok(node)
        }
        if current == 46 {
            self.pos = self.pos + 1
            return Ok(self.t.addNode(1, "."))
        }
        if current == 92 {
            self.pos = self.pos + 1
            Int escaped = self.peekByte()
            if escaped < 0 {
                return Err(textErr("regexCompile: 转义截断"))
            }
            self.pos = self.pos + 1
            if self.isClassEscape(escaped) {
                Int node = self.t.addNode(2, "")
                self.t.clsStart.set(node, self.t.lo.length())
                self.addClassEscape(escaped)
                self.t.clsCount.set(node, self.t.lo.length() - self.t.clsStart.get(node))
                return Ok(node)
            }
            Int decoded = self.escapeCodePoint(escaped)
            if decoded < 0 {
                return Err(textErr("regexCompile: 非法转义"))
            }
            return Ok(self.t.addNode(0, fromCodePoint(decoded)))
        }
        if current == 41 || current == 124 {
            return Err(textErr("regexCompile: 意外的 ) 或 |"))
        }
        if current == 42 || current == 43 || current == 63 {
            return Err(textErr("regexCompile: 量词缺少原子"))
        }
        if current == 36 {
            self.pos = self.pos + 1
            return Ok(self.t.addNode(0, "$"))
        }
        if current == 94 {
            self.pos = self.pos + 1
            return Ok(self.t.addNode(0, "^"))
        }
        Int codePoint = self.readCodePoint()
        if codePoint < 0 {
            return Err(textErr("regexCompile: 非法 UTF-8 模式"))
        }
        return Ok(self.t.addNode(0, fromCodePoint(codePoint)))
    }

    // 读取十进制数；-1=没有数字，-2=溢出。
    Int readDecimal() {
        Int value = 0
        Int digits = 0
        while self.pos < self.pattern.length() {
            Int current = self.pattern.get(self.pos)
            if current < 48 || current > 57 {
                break
            }
            if value > 214748364 {
                return -2
            }
            value = value * 10 + (current - 48)
            if value < 0 {
                return -2
            }
            digits = digits + 1
            self.pos = self.pos + 1
        }
        if digits == 0 {
            return -1
        }
        return value
    }

    Result<Int, Error> parseInterval(Int atom) {
        Int saved = self.pos
        self.pos = self.pos + 1
        Int minimum = self.readDecimal()
        if minimum == -2 {
            return Err(textErr("regexCompile: 量词上界溢出"))
        }
        if minimum < 0 {
            self.pos = saved
            return Ok(atom)
        }
        Int maximum = minimum
        if self.eatByte(125) {
            // {m}
        } else if self.eatByte(44) {
            if self.eatByte(125) {
                maximum = regexMaxRepeat()
            } else {
                maximum = self.readDecimal()
                if maximum == -2 {
                    return Err(textErr("regexCompile: 量词上界溢出"))
                }
                if maximum < 0 || !self.eatByte(125) {
                    return Err(textErr("regexCompile: 区间量词非法"))
                }
            }
        } else {
            return Err(textErr("regexCompile: 区间量词非法"))
        }
        if maximum < minimum {
            return Err(textErr("regexCompile: 区间量词上下界颠倒"))
        }
        Int node = self.t.addNode(6, "")
        self.t.kidStart.set(node, self.t.kidRefs.length())
        self.t.kidRefs.push(atom)
        self.t.kidCount.set(node, 1)
        self.t.minr.set(node, minimum)
        self.t.maxr.set(node, maximum)
        return Ok(node)
    }

    Result<Int, Error> parseQuantified() {
        Result<Int, Error> atom = self.parseAtom()
        if atom.isErr() {
            return atom
        }
        Int node = atom.value()
        Int current = self.peekByte()
        if current == 42 {
            self.pos = self.pos + 1
            Int quantifier = self.t.addNode(6, "")
            self.t.kidStart.set(quantifier, self.t.kidRefs.length())
            self.t.kidRefs.push(node)
            self.t.kidCount.set(quantifier, 1)
            self.t.minr.set(quantifier, 0)
            self.t.maxr.set(quantifier, regexMaxRepeat())
            return Ok(quantifier)
        }
        if current == 43 {
            self.pos = self.pos + 1
            Int quantifier = self.t.addNode(6, "")
            self.t.kidStart.set(quantifier, self.t.kidRefs.length())
            self.t.kidRefs.push(node)
            self.t.kidCount.set(quantifier, 1)
            self.t.minr.set(quantifier, 1)
            self.t.maxr.set(quantifier, regexMaxRepeat())
            return Ok(quantifier)
        }
        if current == 63 {
            self.pos = self.pos + 1
            Int quantifier = self.t.addNode(6, "")
            self.t.kidStart.set(quantifier, self.t.kidRefs.length())
            self.t.kidRefs.push(node)
            self.t.kidCount.set(quantifier, 1)
            self.t.minr.set(quantifier, 0)
            self.t.maxr.set(quantifier, 1)
            return Ok(quantifier)
        }
        if current == 123 {
            return self.parseInterval(node)
        }
        return Ok(node)
    }

    Result<Int, Error> parseSeq() {
        List<Int> children = []
        while true {
            Int current = self.peekByte()
            if current < 0 || current == 41 || current == 124 {
                break
            }
            Result<Int, Error> child = self.parseQuantified()
            if child.isErr() {
                return child
            }
            children.push(child.value())
        }
        if children.length() == 0 {
            return Ok(self.t.addNode(7, ""))
        }
        if children.length() == 1 {
            return Ok(children.get(0))
        }
        Int node = self.t.addNode(5, "")
        self.t.kidStart.set(node, self.t.kidRefs.length())
        Int index = 0
        while index < children.length() {
            self.t.kidRefs.push(children.get(index))
            index = index + 1
        }
        self.t.kidCount.set(node, children.length())
        return Ok(node)
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
            Result<Int, Error> branch = self.parseSeq()
            if branch.isErr() {
                return branch
            }
            branches.push(branch.value())
        }
        if branches.length() == 1 {
            return Ok(branches.get(0))
        }
        Int node = self.t.addNode(4, "")
        self.t.kidStart.set(node, self.t.kidRefs.length())
        Int index = 0
        while index < branches.length() {
            self.t.kidRefs.push(branches.get(index))
            index = index + 1
        }
        self.t.kidCount.set(node, branches.length())
        return Ok(node)
    }
}
