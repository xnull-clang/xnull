// XNull 版词法器（Go xfront.Lex 的 L1 token dump 对照实现）。
// 只输出 token/AST 层数据，不依赖 Go xfront；lex 诊断以 code/line/col 输出。
// 覆盖：注释/BOM/CRLF、自动分号、数字/字符/字符串/插值（基础）、关键字、运算符。
package xdk.compiler.lexer; import xdk.text
































class Lexer {
    String src = ""
    Bytes bytes
    Int pos = 0
    Int line = 1
    Int col = 1
    Int blen = 0
    Bool sawNL = false
    Bool hasLast = false
    Tok last = new Tok()
    Bool hasStash = false
    Tok stash = new Tok()
    List<Diag> diags = []

    Lexer(String s) {
        self.src = s
        self.bytes = Bytes.fromString(s)
        self.blen = self.bytes.length()
        self.pos = 0
        self.line = 1
        self.col = 1
        if self.blen > 0 && self.bytes.get(0) == 239 && self.blen > 2 &&
            self.bytes.get(1) == 187 && self.bytes.get(2) == 191 {
            self.pos = 3
        }
    }

    Int b(Int i) {
        if i < 0 || i >= self.blen {
            return -1
        }
        return self.bytes.get(i)
    }

    Bool eof() {
        return self.pos >= self.blen
    }

    String piece(Int start, Int end) {
        if end <= start {
            return ""
        }
        return self.src.substring(start, end - start)
    }

    String one(Int i) {
        return self.src.substring(i, 1)
    }

    void adv() {
        if self.eof() {
            return
        }
        Int x = self.bytes.get(self.pos)
        self.pos = self.pos + 1
        if x == 10 {
            self.line = self.line + 1
            self.col = 1
        } else if x < 128 || x >= 192 {
            self.col = self.col + 1
        }
    }

    void err(String code, Int l, Int c, String msg) {
        Diag d = new Diag()
        d.code = code
        d.line = l
        d.col = c
        d.msg = msg
        self.diags.push(d)
    }

    Bool isDigit(Int x) { return x >= 48 && x <= 57 }
    Bool isHex(Int x) {
        return self.isDigit(x) || (x >= 97 && x <= 102) || (x >= 65 && x <= 70)
    }
    Bool isIdentStart(Int x) {
        return x == 95 || (x >= 97 && x <= 122) || (x >= 65 && x <= 90)
    }
    Bool isIdentRune(Int x) { return self.isIdentStart(x) || self.isDigit(x) }

    void skipTrivia() {
        Bool go = true
        while go && !self.eof() {
            Int x = self.bytes.get(self.pos)
            if x == 32 || x == 9 || x == 13 {
                self.adv()
            } else if x == 10 {
                self.sawNL = true
                self.adv()
            } else if x == 47 && self.b(self.pos + 1) == 47 {
                while !self.eof() && self.bytes.get(self.pos) != 10 {
                    self.adv()
                }
            } else if x == 47 && self.b(self.pos + 1) == 42 {
                Int sl = self.line
                Int sc = self.col
                self.adv()
                self.adv()
                Bool closed = false
                while !self.eof() {
                    if self.bytes.get(self.pos) == 42 && self.b(self.pos + 1) == 47 {
                        self.adv()
                        self.adv()
                        closed = true
                        break
                    }
                    self.adv()
                }
                if !closed {
                    self.err("LEX-102", sl, sc, "块注释未闭合")
                }
            } else {
                go = false
            }
        }
    }

    Bool insertable(Tok t) {
        if t.kind == 2 || t.kind == 5 || t.kind == 6 || t.kind == 7 || t.kind == 8 ||
            t.kind == 11 || t.kind == 15 || t.kind == 13 {
            return true
        }
        if t.kind == 9 {
            return t.text == "++" || t.text == "--"
        }
        if t.kind == 3 {
            return t.text == "return" || t.text == "break" || t.text == "continue" || t.text == "throw"
        }
        return false
    }

    Bool blocksSemi(Tok t, Tok l) {
        if l.kind != 13 {
            return false
        }
        return t.kind == 3 && (t.text == "else" || t.text == "while")
    }

    Tok mk(Int kind, String text, Int l, Int c) {
        Tok t = new Tok()
        t.kind = kind
        t.text = text
        t.line = l
        t.col = c
        return t
    }

    Tok next() {
        if self.hasStash {
            self.hasStash = false
            self.last = self.stash
            self.hasLast = true
            return self.stash
        }
        while true {
            self.skipTrivia()
            if self.eof() {
                if self.sawNL && self.hasLast && self.insertable(self.last) {
                    self.sawNL = false
                    return self.mk(1, "", self.last.line, self.last.col)
                }
                return self.mk(0, "", self.line, self.col)
            }
            Tok t = self.scanToken()
            if t.kind == -1 {
                continue
            }
            if self.sawNL && self.hasLast && self.insertable(self.last) && !self.blocksSemi(t, self.last) {
                self.hasStash = true
                self.stash = t
                self.sawNL = false
                return self.mk(1, "", self.last.line, self.last.col)
            }
            self.sawNL = false
            self.last = t
            self.hasLast = true
            return t
        }
    }

    Tok scanToken() {
        Int l = self.line
        Int c = self.col
        Int x = self.bytes.get(self.pos)
        // 字符串前缀（先多行，再单行）。
        if x == 34 && self.b(self.pos + 1) == 34 && self.b(self.pos + 2) == 34 {
            return self.scanString(l, c, false, true, false)
        }
        if x == 114 && self.b(self.pos + 1) == 34 && self.b(self.pos + 2) == 34 && self.b(self.pos + 3) == 34 {
            return self.scanString(l, c, true, true, false)
        }
        if x == 36 && self.b(self.pos + 1) == 34 {
            return self.scanString(l, c, false, false, true)
        }
        if x == 114 && self.b(self.pos + 1) == 34 {
            return self.scanString(l, c, true, false, false)
        }
        if x == 34 {
            return self.scanString(l, c, false, false, false)
        }
        if x == 39 {
            return self.scanChar(l, c)
        }
        if self.isDigit(x) {
            return self.scanNumber(l, c)
        }
        if self.isIdentStart(x) {
            Int start = self.pos
            self.adv()
            while !self.eof() && self.isIdentRune(self.bytes.get(self.pos)) {
                self.adv()
            }
            String word = self.piece(start, self.pos)
            if self.isKeyword(word) {
                return self.mk(3, word, l, c)
            }
            return self.mk(2, word, l, c)
        }
        if x == 64 && self.isIdentStart(self.b(self.pos + 1)) {
            self.adv()
            Int start = self.pos
            self.adv()
            while !self.eof() && self.isIdentRune(self.bytes.get(self.pos)) {
                self.adv()
            }
            return self.mk(4, self.piece(start, self.pos), l, c)
        }
        String op = self.matchOp()
        if op != "" {
            return self.mk(self.opKind(op), op, l, c)
        }
        self.adv()
        self.err("LEX-101", l, c, "无法识别的字符")
        return self.mk(-1, "", l, c)
    }

    String matchOp() {
        List<String> ops = ["<<=", ">>=", "...", "..<", "===", "!==", "==", "!=", "<=", ">=", "<<", ">>",
            "&&", "||", "??", "?.", "->", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=",
            "++", "--", "+", "-", "*", "/", "%", "=", "<", ">", "!", "?", ":", "&", "|", "^", "~",
            ".", ",", ";", "@", "(", ")", "{", "}", "[", "]"]
        Int i = 0
        while i < ops.length() {
            String s = ops.get(i)
            if self.startsAt(s) {
                self.pos = self.pos + s.length()
                if s == "(" || s == ")" || s == "{" || s == "}" || s == "[" || s == "]" {
                    self.col = self.col + 1
                } else if s == ";" || s == "," {
                    self.col = self.col + 1
                } else {
                    self.col = self.col + s.length()
                }
                return s
            }
            i = i + 1
        }
        return ""
    }

    Bool startsAt(String s) {
        if self.pos + s.length() > self.blen {
            return false
        }
        return self.src.substring(self.pos, s.length()) == s
    }

    Int opKind(String s) {
        if s == "(" { return 10 }
        if s == ")" { return 11 }
        if s == "{" { return 12 }
        if s == "}" { return 13 }
        if s == "[" { return 14 }
        if s == "]" { return 15 }
        if s == "," { return 16 }
        if s == ";" { return 1 }
        return 9
    }

    Bool isKeyword(String w) {
        List<String> ks = ["package", "import", "as", "public", "protected", "private", "final", "static",
            "const", "var", "abstract", "class", "struct", "protocol", "enum", "singleton",
            "factory", "extension", "implements", "new", "self", "super", "in",
            "if", "else", "while", "do", "for", "switch", "case", "default", "break", "continue",
            "throw", "try", "return", "goto", "defer", "errdefer", "is"]
        return inList(ks, w)
    }

    Int scanDigits(Int base) {
        Int n = 0
        while !self.eof() {
            Int x = self.bytes.get(self.pos)
            if x == 95 {
                if !self.isDigit(self.b(self.pos + 1)) {
                    self.err("LEX-104", self.line, self.col, "下划线位置错误")
                }
                self.adv()
                continue
            }
            Bool ok = false
            if base == 16 { ok = self.isHex(x) }
            else if base == 2 { ok = x == 48 || x == 49 }
            else if base == 8 { ok = x >= 48 && x <= 55 }
            else { ok = self.isDigit(x) }
            if !ok { return n }
            n = n + 1
            self.adv()
        }
        return n
    }

    Tok scanNumber(Int l, Int c) {
        Int start = self.pos
        Int base = 10
        Int save = self.pos
        Int saveL = self.line
        Int saveC = self.col
        if self.b(self.pos) == 48 && (self.b(self.pos + 1) == 120 || self.b(self.pos + 1) == 88) {
            base = 16
            self.adv()
            self.adv()
            self.scanDigits(16)
        } else if self.b(self.pos) == 48 && (self.b(self.pos + 1) == 98 || self.b(self.pos + 1) == 66) {
            base = 2
            self.adv()
            self.adv()
            self.scanDigits(2)
        } else if self.b(self.pos) == 48 && (self.b(self.pos + 1) == 111 || self.b(self.pos + 1) == 79) {
            base = 8
            self.adv()
            self.adv()
            self.scanDigits(8)
        } else {
            self.scanDigits(10)
        }
        if base == 10 {
            if self.b(self.pos) == 46 && self.isDigit(self.b(self.pos + 1)) {
                self.adv()
                self.scanDigits(10)
                if self.b(self.pos) == 101 || self.b(self.pos) == 69 {
                    if self.isDigit(self.b(self.pos + 1)) ||
                        ((self.b(self.pos + 1) == 43 || self.b(self.pos + 1) == 45) && self.isDigit(self.b(self.pos + 2))) {
                        self.adv()
                        if self.b(self.pos) == 43 || self.b(self.pos) == 45 { self.adv() }
                        self.scanDigits(10)
                    }
                }
                String sf = self.scanSuffix()
                Tok t = self.mk(6, self.piece(start, self.pos), l, c)
                t.base = 0
                t.suffix = sf
                t.hasSuffixF = sf == "F"
                return t
            }
        }
        String sf = self.scanSuffix()
        Tok t = self.mk(5, self.piece(start, self.pos), l, c)
        t.base = base
        t.suffix = sf
        return t
    }

    String scanSuffix() {
        if self.eof() { return "" }
        Int x = self.bytes.get(self.pos)
        if x == 70 {
            self.adv()
            return "F"
        }
        if x == 76 {
            self.adv()
            return "L"
        }
        if x == 85 {
            self.adv()
            if self.b(self.pos) == 76 { self.adv(); return "UL" }
            return "U"
        }
        return ""
    }

    Tok scanChar(Int l, Int c) {
        self.adv()
        Int val = 0
        Int count = 0
        if !self.eof() && self.bytes.get(self.pos) == 39 {
            self.adv()
            self.err("LEX-106", l, c, "空字符字面量")
            return self.mk(7, "", l, c)
        }
        if self.eof() || self.bytes.get(self.pos) == 10 {
            self.err("LEX-106", l, c, "字符字面量跨行或为空")
            return self.mk(7, "", l, c)
        }
        if self.bytes.get(self.pos) == 92 {
            self.adv()
            if !self.eof() {
                Int e = self.bytes.get(self.pos)
                self.adv()
                if e == 110 { val = 10 } else if e == 116 { val = 9 }
                else if e == 114 { val = 13 } else if e == 92 { val = 92 }
                else if e == 39 { val = 39 } else if e == 34 { val = 34 } else { self.err("LEX-103", l, c, "未知转义") ; val = e }
                count = 1
            }
        } else {
            val = self.bytes.get(self.pos)
            self.adv()
            count = 1
        }
        if !self.eof() && self.bytes.get(self.pos) != 39 {
            count = 2
            while !self.eof() && self.bytes.get(self.pos) != 39 && self.bytes.get(self.pos) != 10 {
                self.adv()
            }
        }
        if !self.eof() && self.bytes.get(self.pos) == 39 {
            self.adv()
        } else {
            self.err("LEX-106", l, c, "字符字面量未闭合")
        }
        if count != 1 && count != 0 {
            self.err("LEX-106", l, c, "字符字面量必须恰好一个码点")
        }
        Tok t = self.mk(7, "", l, c)
        t.ch = val
        return t
    }

    Tok scanString(Int l, Int c, Bool raw, Bool multiline, Bool interp) {
        if raw || interp { self.adv() }
        self.adv()
        if multiline { self.adv(); self.adv() }
        String val = ""
        String joined = ""
        List<String> segs = []
        List<String> interps = []
        Bool closed = false
        while !self.eof() {
            Int x = self.bytes.get(self.pos)
            if !multiline && x == 10 {
                break
            }
            if interp && x == 123 {
                if self.b(self.pos + 1) == 123 {
                    self.adv(); self.adv()
                    val = val + "{"
                    continue
                }
                segs.push(val)
                joined = joined + val
                val = ""
                self.adv()
                String expr = ""
                Int depth = 1
                while !self.eof() && depth > 0 {
                    Int y = self.bytes.get(self.pos)
                    if y == 123 {
                        depth = depth + 1
                        expr = expr + "{"
                        self.adv()
                    } else if y == 125 {
                        depth = depth - 1
                        if depth == 0 {
                            self.adv()
                        } else {
                            expr = expr + "}"
                            self.adv()
                        }
                    } else if y == 34 {
                        expr = expr + "\""
                        self.adv()
                        Bool qdone = false
                        while !self.eof() && !qdone {
                            Int z = self.bytes.get(self.pos)
                            if z == 92 {
                                expr = expr + self.one(self.pos)
                                self.adv()
                                if !self.eof() {
                                    expr = expr + self.one(self.pos)
                                    self.adv()
                                }
                            } else {
                                expr = expr + self.one(self.pos)
                                self.adv()
                                if z == 34 { qdone = true }
                            }
                        }
                    } else {
                        expr = expr + self.one(self.pos)
                        self.adv()
                    }
                }
                interps.push(expr)
                continue
            }
            if x == 34 {
                if multiline {
                    if self.b(self.pos + 1) == 34 && self.b(self.pos + 2) == 34 {
                        self.adv(); self.adv(); self.adv()
                        closed = true
                        break
                    }
                    val = val + self.one(self.pos)
                    self.adv()
                } else {
                    self.adv()
                    closed = true
                    break
                }
            } else if !raw && x == 92 {
                Int el = self.line
                Int ec = self.col
                self.adv()
                if self.eof() { break }
                Int e = self.bytes.get(self.pos)
                self.adv()
                if e == 110 { val = val + "\n" }
                else if e == 116 { val = val + "\t" }
                else if e == 114 { val = val + "\r" }
                else if e == 34 { val = val + "\"" }
                else if e == 92 { val = val + "\\" }
                else if e == 39 { val = val + "'" }
                else if e == 48 { val = val + "\u0000" }
                else { self.err("LEX-103", el, ec, "未知转义") ; val = val + self.one(self.pos - 1) }
            } else {
                val = val + self.one(self.pos)
                self.adv()
            }
        }
        if !closed {
            self.err("LEX-102", l, c, "字符串未闭合")
        }
        segs.push(val)
        joined = joined + val
        Int kind = 0
        if interp { kind = 4 }
        else if raw && multiline { kind = 3 }
        else if raw { kind = 1 }
        else if multiline { kind = 2 }
        Tok t = self.mk(8, "", l, c)
        t.str = kind
        t.value = joined
        t.segs = segs
        t.interps = interps
        return t
    }
}
