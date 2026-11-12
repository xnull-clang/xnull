// B2-01：XNull 版词法器（Go xfront.Lex 的 L1 token dump 对照实现）。
// 只输出 token/AST 层数据，不依赖 Go xfront；lex 诊断以 code/line/col 输出。
// 覆盖：注释/BOM/CRLF、自动分号、数字/字符/字符串/插值（基础）、关键字、运算符。
// B4b-02：新增 --file <path> 文件输入模式（import xdk.sys 提供 readFileText）。
import xdk.sys

static Bool inList(List<String> xs, String w) {
    Int i = 0
    while i < xs.length() {
        if xs.get(i) == w { return true }
        i = i + 1
    }
    return false
}

class Tok {
    Int kind = 0
    String text = ""
    Int line = 1
    Int col = 1
    Int str = 0
    String value = ""
    List<String> segs = []
    List<String> interps = []
    Int ch = 0
    Int base = 0
    String suffix = ""
    Bool hasSuffixF = false
}

class Diag {
    String code = ""
    Int line = 1
    Int col = 1
    String msg = ""
}

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
            "factory", "extension", "implements", "new", "self", "super", "out", "in",
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
                else if e == 39 { val = 39 } else if e == 34 { val = 34 }
                else if e == 48 { val = 0 } else { self.err("LEX-103", l, c, "未知转义") ; val = e }
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
                else if e == 48 { val = val + $"{'\0'}" }
                else if e == 117 && self.b(self.pos) == 48 && self.b(self.pos + 1) == 48 &&
                        self.b(self.pos + 2) == 48 && self.b(self.pos + 3) == 48 {
                    // B4b 大文件：\u0000 → 真实 NUL（String 按长度可含 NUL）。
                    self.adv(); self.adv(); self.adv(); self.adv()
                    val = val + $"{'\0'}"
                }
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

String q(String s) {
    String b = "\""
    String nul = $"{'\0'}"
    Int i = 0
    while i < s.length() {
        String c = s.substring(i, 1)
        if c == "\"" { b = b + "\\\"" }
        else if c == "\\" { b = b + "\\\\" }
        else if c == "\n" { b = b + "\\n" }
        else if c == "\t" { b = b + "\\t" }
        else if c == "\r" { b = b + "\\r" }
        else if c == nul { b = b + "\\x00" }
        else { b = b + c }
        i = i + 1
    }
    return b + "\""
}

String dumpTok(Tok t) {
    String b = "(Token (Kind " + str(t.kind) + ") (Text " + q(t.text)
    b = b + ") (Pos (Pos (Line " + str(t.line) + ") (Col " + str(t.col) + "))) (Str " + str(t.str)
    b = b + ") (Value " + q(t.value) + ") (Segs (slice"
    Int i = 0
    while i < t.segs.length() { b = b + " " + q(t.segs.get(i)); i = i + 1 }
    b = b + ")) (Interps (slice"
    i = 0
    while i < t.interps.length() { b = b + " " + q(t.interps.get(i)); i = i + 1 }
    b = b + ")) (Char " + str(t.ch) + ") (Base " + str(t.base) + ") (Suffix " + q(t.suffix) + ") (HasSuffixF "
    if t.hasSuffixF { b = b + "true" } else { b = b + "false" }
    return b + "))"
}


class E {
    String d = ""
    Int l = 1
    Int c = 1
    Int sl = 1
    Int sc = 1
}

static String P(Int l, Int c) {
    return "(P (Pos (Line " + str(l) + ") (Col " + str(c) + ")))"
}

static String F(String n, String v) {
    return "(" + n + " " + v + ")"
}

static String SL(List<String> xs) {
    if xs.length() == 0 { return "(slice)" }
    String s = "(slice"
    Int i = 0
    while i < xs.length() {
        s = s + " " + xs.get(i)
        i = i + 1
    }
    return s + ")"
}

static String SLS(List<String> xs) {
    if xs.length() == 0 { return "(slice)" }
    String s = "(slice"
    Int i = 0
    while i < xs.length() { s = s + " " + q(xs.get(i)); i = i + 1 }
    return s + ")"
}

static String B(Bool v) {
    if v { return "true" }
    return "false"
}

class M {
    String vis = ""
    Bool abs = false
    Bool fin = false
    Bool stat = false
    Bool cons = false
}

class TN {
    Bool sc = false
    String raw = ""
    String nm = ""
    List<String> fn = []
    List<TN> fv = []
    List<TN> el = []
}

class TP {
    String s = ""
    Int p = 0
    Int n = 0

    TP(String t) { self.s = t; self.n = t.length() }

    String ch(Int i) {
        if i < 0 { return "" }
        if i >= self.n { return "" }
        return self.s.substring(i, 1)
    }

    void ws() {
        while self.p < self.n && self.ch(self.p) == " " { self.p = self.p + 1 }
    }

    String bare() {
        Int st = self.p
        while self.p < self.n {
            String c = self.ch(self.p)
            if c == " " || c == "(" || c == ")" { break }
            self.p = self.p + 1
        }
        return self.s.substring(st, self.p - st)
    }

    TN val() {
        self.ws()
        if self.ch(self.p) == "(" {
            self.p = self.p + 1
            String name = self.bare()
            TN r = new TN()
            if name == "slice" {
                r.nm = "slice"
                while true {
                    self.ws()
                    if self.ch(self.p) == ")" { self.p = self.p + 1; break }
                    r.el.push(self.val())
                }
                return r
            }
            r.nm = name
            while true {
                self.ws()
                if self.ch(self.p) == ")" { self.p = self.p + 1; break }
                self.p = self.p + 1
                String f = self.bare()
                TN v = self.val()
                self.ws()
                self.p = self.p + 1
                r.fn.push(f)
                r.fv.push(v)
            }
            return r
        }
        TN r = new TN()
        r.sc = true
        if self.ch(self.p) == "\"" {
            Int st = self.p
            self.p = self.p + 1
            while true {
                String c = self.ch(self.p)
                if c == "\\" { self.p = self.p + 2; continue }
                if c == "\"" { self.p = self.p + 1; break }
                self.p = self.p + 1
            }
            r.raw = self.s.substring(st, self.p - st)
            return r
        }
        Int st = self.p
        while self.p < self.n {
            String c = self.ch(self.p)
            if c == " " || c == "(" || c == ")" { break }
            self.p = self.p + 1
        }
        r.raw = self.s.substring(st, self.p - st)
        return r
    }

    String render(TN v, Int dep) {
        if dep > 100000 { return "(depth-limit)" }
        if v.sc { return v.raw }
        if v.nm == "nil" { return "(nil)" }
        if v.nm == "slice" {
            String r = "(slice"
            Int i = 0
            while i < v.el.length() {
                r = r + " " + self.render(v.el.get(i), dep + 1)
                i = i + 1
            }
            return r + ")"
        }
        String r = "(" + v.nm
        Int i = 0
        while i < v.fn.length() {
            String f = v.fn.get(i)
            r = r + " (" + f + " " + self.renderField(v.fv.get(i), dep + 1, self.fcat(v.nm, f)) + ")"
            i = i + 1
        }
        return r + ")"
    }

    String renderField(TN v, Int cd, String cat) {
        if cd > 100000 { return "(depth-limit)" }
        if cat == "s" || cat == "v" { return self.render(v, cd) }
        if cat == "p" { return self.render(v, cd + 1) }
        if cat == "i" { return self.render(v, cd + 2) }
        String r = "(slice"
        Int i = 0
        while i < v.el.length() {
            if cat == "ss" || cat == "sv" { r = r + " " + self.render(v.el.get(i), cd + 1) }
            else if cat == "sp" { r = r + " " + self.render(v.el.get(i), cd + 2) }
            else if cat == "si" { r = r + " " + self.render(v.el.get(i), cd + 3) }
            i = i + 1
        }
        return r + ")"
    }

    String fcat(String nd, String f) {
        String k = nd + "." + f
        if k == "AnnotationDecl.Annos" { return "sp" }
        if k == "AnnotationDecl.Fields" { return "sp" }
        if k == "AnnotationDecl.Mod" { return "v" }
        if k == "AnnotationDecl.Name" { return "s" }
        if k == "AnnotationDecl.P" { return "v" }
        if k == "AnnotationNode.Args" { return "si" }
        if k == "AnnotationNode.Name" { return "s" }
        if k == "AnnotationNode.P" { return "v" }
        if k == "ArrayLit.Elems" { return "si" }
        if k == "ArrayLit.P" { return "v" }
        if k == "AssignStmt.Op" { return "s" }
        if k == "AssignStmt.P" { return "v" }
        if k == "AssignStmt.Target" { return "i" }
        if k == "AssignStmt.Value" { return "i" }
        if k == "Binary.L" { return "i" }
        if k == "Binary.Op" { return "s" }
        if k == "Binary.P" { return "v" }
        if k == "Binary.R" { return "i" }
        if k == "Block.P" { return "v" }
        if k == "Block.Stmts" { return "si" }
        if k == "BoolLit.P" { return "v" }
        if k == "BoolLit.V" { return "s" }
        if k == "BreakStmt.Label" { return "s" }
        if k == "BreakStmt.P" { return "v" }
        if k == "Call.Args" { return "si" }
        if k == "Call.Callee" { return "i" }
        if k == "Call.P" { return "v" }
        if k == "Call.TypeArgs" { return "si" }
        if k == "CharLitExpr.P" { return "v" }
        if k == "CharLitExpr.Rune" { return "s" }
        if k == "ClassDecl.Annos" { return "sp" }
        if k == "ClassDecl.Base" { return "i" }
        if k == "ClassDecl.Ctors" { return "sp" }
        if k == "ClassDecl.Fields" { return "sp" }
        if k == "ClassDecl.Methods" { return "sp" }
        if k == "ClassDecl.Mod" { return "v" }
        if k == "ClassDecl.Name" { return "s" }
        if k == "ClassDecl.P" { return "v" }
        if k == "ClassDecl.Primary" { return "p" }
        if k == "ClassDecl.Protocols" { return "sp" }
        if k == "ClassDecl.TypePars" { return "ss" }
        if k == "CompilationUnit.Decls" { return "si" }
        if k == "CompilationUnit.Imports" { return "sp" }
        if k == "CompilationUnit.P" { return "v" }
        if k == "CompilationUnit.Package" { return "p" }
        if k == "ContinueStmt.Label" { return "s" }
        if k == "ContinueStmt.P" { return "v" }
        if k == "CtorDecl.Annos" { return "sp" }
        if k == "CtorDecl.Body" { return "p" }
        if k == "CtorDecl.Mod" { return "v" }
        if k == "CtorDecl.P" { return "v" }
        if k == "CtorDecl.Params" { return "sp" }
        if k == "DeferStmt.Block" { return "p" }
        if k == "DeferStmt.Errdefer" { return "s" }
        if k == "DeferStmt.P" { return "v" }
        if k == "DeferStmt.Stmt" { return "i" }
        if k == "DoWhileStmt.Body" { return "p" }
        if k == "DoWhileStmt.Cond" { return "i" }
        if k == "DoWhileStmt.P" { return "v" }
        if k == "EnumDecl.Annos" { return "sp" }
        if k == "EnumDecl.Ctors" { return "sp" }
        if k == "EnumDecl.Fields" { return "sp" }
        if k == "EnumDecl.IsData" { return "s" }
        if k == "EnumDecl.Items" { return "sp" }
        if k == "EnumDecl.Methods" { return "sp" }
        if k == "EnumDecl.Mod" { return "v" }
        if k == "EnumDecl.Name" { return "s" }
        if k == "EnumDecl.P" { return "v" }
        if k == "EnumItem.Annos" { return "sp" }
        if k == "EnumItem.Args" { return "si" }
        if k == "EnumItem.Name" { return "s" }
        if k == "EnumItem.P" { return "v" }
        if k == "EnumItem.Value" { return "i" }
        if k == "ExprStmt.P" { return "v" }
        if k == "ExprStmt.X" { return "i" }
        if k == "ExtensionDecl.Annos" { return "sp" }
        if k == "ExtensionDecl.Methods" { return "sp" }
        if k == "ExtensionDecl.Mod" { return "v" }
        if k == "ExtensionDecl.P" { return "v" }
        if k == "ExtensionDecl.Target" { return "i" }
        if k == "FactoryDecl.Annos" { return "sp" }
        if k == "FactoryDecl.Methods" { return "sp" }
        if k == "FactoryDecl.Mod" { return "v" }
        if k == "FactoryDecl.Name" { return "s" }
        if k == "FactoryDecl.P" { return "v" }
        if k == "FactoryDecl.Target" { return "i" }
        if k == "FieldDecl.Annos" { return "sp" }
        if k == "FieldDecl.Canonical" { return "s" }
        if k == "FieldDecl.Init" { return "i" }
        if k == "FieldDecl.Mod" { return "v" }
        if k == "FieldDecl.Name" { return "s" }
        if k == "FieldDecl.P" { return "v" }
        if k == "FieldDecl.Type" { return "i" }
        if k == "FloatLitExpr.HasSuffixF" { return "s" }
        if k == "FloatLitExpr.P" { return "v" }
        if k == "FloatLitExpr.Text" { return "s" }
        if k == "ForStmt.Body" { return "p" }
        if k == "ForStmt.P" { return "v" }
        if k == "ForStmt.Src" { return "i" }
        if k == "ForStmt.Var" { return "s" }
        if k == "FuncTypeRef.P" { return "v" }
        if k == "FuncTypeRef.Params" { return "si" }
        if k == "FuncTypeRef.Ret" { return "i" }
        if k == "GotoStmt.Label" { return "s" }
        if k == "GotoStmt.P" { return "v" }
        if k == "IdentExpr.Name" { return "s" }
        if k == "IdentExpr.P" { return "v" }
        if k == "IfStmt.Cond" { return "i" }
        if k == "IfStmt.Else" { return "i" }
        if k == "IfStmt.P" { return "v" }
        if k == "IfStmt.Then" { return "p" }
        if k == "ImportDecl.Alias" { return "s" }
        if k == "ImportDecl.P" { return "v" }
        if k == "ImportDecl.Path" { return "ss" }
        if k == "IncDecStmt.Op" { return "s" }
        if k == "IncDecStmt.P" { return "v" }
        if k == "IncDecStmt.Prefix" { return "s" }
        if k == "IncDecStmt.Target" { return "i" }
        if k == "Index.Idx" { return "i" }
        if k == "Index.P" { return "v" }
        if k == "Index.X" { return "i" }
        if k == "IntLitExpr.Base" { return "s" }
        if k == "IntLitExpr.P" { return "v" }
        if k == "IntLitExpr.Suffix" { return "s" }
        if k == "IntLitExpr.Text" { return "s" }
        if k == "LabeledStmt.Label" { return "s" }
        if k == "LabeledStmt.P" { return "v" }
        if k == "LabeledStmt.Stmt" { return "i" }
        if k == "Lambda.Block" { return "p" }
        if k == "Lambda.ExprB" { return "i" }
        if k == "Lambda.P" { return "v" }
        if k == "Lambda.Params" { return "sv" }
        if k == "Lambda.Single" { return "s" }
        if k == "LambdaParam.Final" { return "s" }
        if k == "LambdaParam.Name" { return "s" }
        if k == "LambdaParam.P" { return "v" }
        if k == "LambdaParam.Type" { return "i" }
        if k == "LocalDeclStmt.Const" { return "s" }
        if k == "LocalDeclStmt.Final" { return "s" }
        if k == "LocalDeclStmt.Init" { return "i" }
        if k == "LocalDeclStmt.Name" { return "s" }
        if k == "LocalDeclStmt.P" { return "v" }
        if k == "LocalDeclStmt.Type" { return "i" }
        if k == "LocalDeclStmt.Var" { return "s" }
        if k == "MapLit.Keys" { return "si" }
        if k == "MapLit.P" { return "v" }
        if k == "MapLit.Vals" { return "si" }
        if k == "Member.Name" { return "s" }
        if k == "Member.NullSafe" { return "s" }
        if k == "Member.P" { return "v" }
        if k == "Member.X" { return "i" }
        if k == "MethodDecl.Annos" { return "sp" }
        if k == "MethodDecl.Body" { return "p" }
        if k == "MethodDecl.IsDeinit" { return "s" }
        if k == "MethodDecl.Mod" { return "v" }
        if k == "MethodDecl.Name" { return "s" }
        if k == "MethodDecl.P" { return "v" }
        if k == "MethodDecl.Params" { return "sp" }
        if k == "MethodDecl.Ret" { return "i" }
        if k == "MethodDecl.TypePars" { return "ss" }
        if k == "MethodDecl.Void" { return "s" }
        if k == "NamedType.Args" { return "si" }
        if k == "NamedType.P" { return "v" }
        if k == "NamedType.Qual" { return "ss" }
        if k == "New.Args" { return "si" }
        if k == "New.P" { return "v" }
        if k == "New.Type" { return "i" }
        if k == "NewArray.Count" { return "i" }
        if k == "NewArray.P" { return "v" }
        if k == "NewArray.Type" { return "i" }
        if k == "PackageDecl.Name" { return "ss" }
        if k == "PackageDecl.P" { return "v" }
        if k == "Param.Annos" { return "sp" }
        if k == "Param.Final" { return "s" }
        if k == "Param.Name" { return "s" }
        if k == "Param.P" { return "v" }
        if k == "Param.Type" { return "i" }
        if k == "Paren.P" { return "v" }
        if k == "Paren.X" { return "i" }
        if k == "Pos.Col" { return "s" }
        if k == "Pos.Line" { return "s" }
        if k == "ProtocolDecl.Annos" { return "sp" }
        if k == "ProtocolDecl.Extends" { return "sp" }
        if k == "ProtocolDecl.Name" { return "s" }
        if k == "ProtocolDecl.P" { return "v" }
        if k == "ProtocolDecl.Sigs" { return "sp" }
        if k == "ProtocolSig.Annos" { return "sp" }
        if k == "ProtocolSig.Mod" { return "v" }
        if k == "ProtocolSig.Name" { return "s" }
        if k == "ProtocolSig.P" { return "v" }
        if k == "ProtocolSig.Params" { return "sp" }
        if k == "ProtocolSig.Ret" { return "i" }
        if k == "ProtocolSig.Void" { return "s" }
        if k == "ReturnStmt.P" { return "v" }
        if k == "ReturnStmt.Value" { return "i" }
        if k == "SingletonDecl.Annos" { return "sp" }
        if k == "SingletonDecl.Ctors" { return "sp" }
        if k == "SingletonDecl.Fields" { return "sp" }
        if k == "SingletonDecl.Methods" { return "sp" }
        if k == "SingletonDecl.Mod" { return "v" }
        if k == "SingletonDecl.Name" { return "s" }
        if k == "SingletonDecl.P" { return "v" }
        if k == "StrLitExpr.Kind" { return "s" }
        if k == "StrLitExpr.P" { return "v" }
        if k == "StrLitExpr.Parts" { return "sv" }
        if k == "StrPart.Expr" { return "i" }
        if k == "StrPart.Text" { return "s" }
        if k == "StructDecl.Annos" { return "sp" }
        if k == "StructDecl.Ctors" { return "sp" }
        if k == "StructDecl.Fields" { return "sp" }
        if k == "StructDecl.Methods" { return "sp" }
        if k == "StructDecl.Mod" { return "v" }
        if k == "StructDecl.Name" { return "s" }
        if k == "StructDecl.P" { return "v" }
        if k == "StructDecl.Primary" { return "p" }
        if k == "StructDecl.TypePars" { return "ss" }
        if k == "SuffixedType.Base" { return "i" }
        if k == "SuffixedType.P" { return "v" }
        if k == "SuffixedType.Suffixes" { return "ss" }
        if k == "SwitchCase.Default" { return "s" }
        if k == "SwitchCase.Expr" { return "i" }
        if k == "SwitchCase.P" { return "v" }
        if k == "SwitchCase.Stmts" { return "si" }
        if k == "SwitchStmt.Cases" { return "sp" }
        if k == "SwitchStmt.Default" { return "p" }
        if k == "SwitchStmt.P" { return "v" }
        if k == "SwitchStmt.Value" { return "i" }
        if k == "Ternary.Cond" { return "i" }
        if k == "Ternary.Else" { return "i" }
        if k == "Ternary.P" { return "v" }
        if k == "Ternary.Then" { return "i" }
        if k == "ThrowStmt.P" { return "v" }
        if k == "ThrowStmt.Value" { return "i" }
        if k == "Token.Base" { return "s" }
        if k == "Token.Char" { return "s" }
        if k == "Token.HasSuffixF" { return "s" }
        if k == "Token.Interps" { return "ss" }
        if k == "Token.Kind" { return "v" }
        if k == "Token.Pos" { return "v" }
        if k == "Token.Segs" { return "ss" }
        if k == "Token.Str" { return "s" }
        if k == "Token.Suffix" { return "s" }
        if k == "Token.Text" { return "s" }
        if k == "Token.Value" { return "s" }
        if k == "TopField.Annos" { return "sp" }
        if k == "TopField.Const" { return "s" }
        if k == "TopField.Final" { return "s" }
        if k == "TopField.Init" { return "i" }
        if k == "TopField.Name" { return "s" }
        if k == "TopField.P" { return "v" }
        if k == "TopField.Private" { return "s" }
        if k == "TopField.Protected" { return "s" }
        if k == "TopField.Public" { return "s" }
        if k == "TopField.Static" { return "s" }
        if k == "TopField.Type" { return "i" }
        if k == "TopFunc.Annos" { return "sp" }
        if k == "TopFunc.Body" { return "p" }
        if k == "TopFunc.Name" { return "s" }
        if k == "TopFunc.P" { return "v" }
        if k == "TopFunc.Params" { return "sp" }
        if k == "TopFunc.Private" { return "s" }
        if k == "TopFunc.Protected" { return "s" }
        if k == "TopFunc.Public" { return "s" }
        if k == "TopFunc.Ret" { return "i" }
        if k == "TopFunc.Static" { return "s" }
        if k == "TopFunc.TypePars" { return "ss" }
        if k == "TopFunc.Void" { return "s" }
        if k == "Tuple.Elems" { return "si" }
        if k == "Tuple.P" { return "v" }
        if k == "TupleMember.Index" { return "s" }
        if k == "TupleMember.NullSafe" { return "s" }
        if k == "TupleMember.P" { return "v" }
        if k == "TupleMember.X" { return "i" }
        if k == "TupleTypeRef.Elems" { return "si" }
        if k == "TupleTypeRef.P" { return "v" }
        if k == "TypeModifiers.Abstract" { return "s" }
        if k == "TypeModifiers.Const" { return "s" }
        if k == "TypeModifiers.Final" { return "s" }
        if k == "TypeModifiers.Static" { return "s" }
        if k == "TypeModifiers.Vis" { return "s" }
        if k == "Unary.Op" { return "s" }
        if k == "Unary.P" { return "v" }
        if k == "Unary.X" { return "i" }
        if k == "WhileStmt.Body" { return "p" }
        if k == "WhileStmt.Cond" { return "i" }
        if k == "WhileStmt.P" { return "v" }
        return "s"
    }
}

class Parser {
    List<Tok> toks = []
    Int i = 0
    Int inNew = 0
    List<Diag> diags = []

    Parser(List<Tok> ts) { self.toks = ts }

    void err(String code, Int l, Int c, String msg) {
        Diag d = new Diag()
        d.code = code
        d.line = l
        d.col = c
        d.msg = msg
        self.diags.push(d)
    }

    Tok cur() { return self.toks.get(self.i) }
    Bool at(Int k) { return self.cur().kind == k }
    Bool atOp(String s) { return self.cur().kind == 9 && self.cur().text == s }
    Bool atKw(String s) { return self.cur().kind == 3 && self.cur().text == s }
    Tok next() { Tok t = self.cur(); self.i = self.i + 1; return t }
    Bool eof() { return self.at(0) }

    String parseUnit() {
        Int sl = self.cur().line
        Int sc = self.cur().col
        String pkg = "(nil)"
        List<String> imps = []
        List<String> ds = []
        while !self.eof() {
            if self.at(1) { self.next(); continue }
            if self.atKw("package") {
                Tok pt = self.next()
                List<String> qn = []
                if self.at(2) { qn.push(self.next().text) }
                while self.atOp(".") { self.next(); if self.at(2) { qn.push(self.next().text) } }
                if self.at(1) { self.next() }
                pkg = "(PackageDecl " + P(pt.line, pt.col) + " (Name " + SLS(qn) + "))"
                continue
            }
            if self.atKw("import") {
                Tok it = self.next()
                List<String> qn = []
                if self.at(2) { qn.push(self.next().text) }
                while self.atOp(".") { self.next(); if self.at(2) { qn.push(self.next().text) } }
                String al = ""
                if self.atKw("as") { self.next(); if self.at(2) { al = self.next().text } }
                if self.at(1) { self.next() }
                imps.push("(ImportDecl " + P(it.line, it.col) + " (Path " + SLS(qn) + ") (Alias " + q(al) + "))")
                continue
            }
            ds.push(self.parseTop())
        }
        String body = "(CompilationUnit " + P(sl, sc) + " (Package " + pkg + ") (Imports " + SL(imps) + ") (Decls " + SL(ds) + "))"
        // B4b 大文件：parseTop 产出的文本已是规范 S 表达式；直接输出，避免
        // TP 重新建树 + render 的深递归与重复拼接（大文件下为 O(n²)）。
        return "(xnast v1 " + body + ")"
    }

    String parseTop() {
        Int sl = self.cur().line
        Int sc = self.cur().col
        List<String> annos = self.parseAnnos()
        if self.at(4) && self.cur().text == "annotation" {
            return self.parseAnnotationDecl(sl, sc, annos)
        }
        M m = self.parseMods()
        String kw = ""
        if self.cur().kind == 3 {
            String k = self.cur().text
            if k == "class" || k == "struct" || k == "protocol" || k == "enum" ||
                k == "singleton" || k == "factory" || k == "extension" {
                kw = k
            }
        }
        if kw != "" {
            self.next()
            return self.parseTypeDecl(kw, sl, sc, annos, m)
        }
        Bool void = false
        String ret = ""
        if self.at(2) && self.cur().text == "void" { void = true; self.next() }
        else { ret = self.parseType() }
        String name = ""
        Int nl = sl
        Int nc = sc
        if self.at(2) { Tok nt = self.next(); name = nt.text; nl = nt.line; nc = nt.col }
        List<String> tps = []
        if self.atOp("<") {
            self.next()
            while !self.atOp(">") && !self.eof() {
                if self.at(2) { tps.push(self.next().text) } else { self.next() }
            }
            if self.atOp(">") { self.next() }
        }
        if self.at(10) {
            List<String> ps = self.parseParams()
            String body = self.parseBlock()
            String retv = "(nil)"
            if !void { retv = ret }
            return "(TopFunc " + P(sl, sc) + " (Annos " + SL(annos) + ") (Public " + B(m.vis == "public") +
                ") (Protected " + B(m.vis == "protected") + ") (Private " + B(m.vis == "private") +
                ") (Static " + B(m.stat) + ") (Void " + B(void) + ") (Ret " + retv + ") (Name " + q(name) +
                ") (TypePars " + SLS(tps) + ") (Params " + SL(ps) + ") (Body " + body + "))"
        }
        String init = "(nil)"
        if self.atOp("=") { self.next(); init = self.parseExpr().d }
        if self.at(1) { self.next() }
        return "(TopField " + P(sl, sc) + " (Annos " + SL(annos) + ") (Public " + B(m.vis == "public") +
            ") (Protected " + B(m.vis == "protected") + ") (Private " + B(m.vis == "private") +
            ") (Static " + B(m.stat) + ") (Final " + B(m.fin) + ") (Const " + B(m.cons) + ") (Type " + ret +
            ") (Name " + q(name) + ") (Init " + init + "))"
    }

    List<String> parseAnnos() {
        List<String> res = []
        while self.at(4) {
            Tok t = self.next()
            List<String> args = []
            if self.at(10) {
                self.next()
                while !self.at(11) && !self.eof() {
                    if self.at(16) { self.next(); continue }
                    args.push(self.parseExpr().d)
                }
                if self.at(11) { self.next() }
            }
            res.push("(AnnotationNode " + P(t.line, t.col) + " (Name " + q(t.text) + ") (Args " + SL(args) + "))")
            if self.at(1) { self.next() }
        }
        return res
    }

    M parseMods() {
        M m = new M()
        while true {
            if self.atKw("public") { m.vis = "public"; self.next() }
            else if self.atKw("protected") { m.vis = "protected"; self.next() }
            else if self.atKw("private") { m.vis = "private"; self.next() }
            else if self.atKw("abstract") { m.abs = true; self.next() }
            else if self.atKw("final") { m.fin = true; self.next() }
            else if self.atKw("static") { m.stat = true; self.next() }
            else if self.atKw("const") { m.cons = true; self.next() }
            else { break }
        }
        return m
    }

    String retv(Bool vd, String rt) {
        if vd { return "(nil)" }
        if rt == "" { return "(nil)" }
        return rt
    }

    String modDump(M m) {
        return "(TypeModifiers (Vis " + q(m.vis) + ") (Abstract " + B(m.abs) + ") (Final " + B(m.fin) +
            ") (Static " + B(m.stat) + ") (Const " + B(m.cons) + "))"
    }

    List<String> parseParams() {
        List<String> ps = []
        if self.at(10) {
            self.next()
            while !self.at(11) && !self.eof() {
                if self.at(16) { self.next(); continue }
                ps.push(self.parseParam())
            }
            if self.at(11) { self.next() }
        }
        return ps
    }

    String parseTypeDecl(String kw, Int sl, Int sc, List<String> annos, M m) {
        String name = ""
        Int nl = sl
        Int nc = sc
        if self.at(2) { Tok nt = self.next(); name = nt.text; nl = nt.line; nc = nt.col }
        List<String> tps = []
        if self.atOp("<") {
            self.next()
            while !self.atOp(">") && !self.eof() {
                if self.at(2) { tps.push(self.next().text) } else { self.next() }
            }
            if self.atOp(">") { self.next() }
        }
        String primary = "(nil)"
        if self.at(10) {
            // 主构造器只有参数列表，没有独立函数体；`{` 属于类体。
            Int pl = self.cur().line
            Int pc = self.cur().col
            List<String> pps = self.parseParams()
            primary = "(CtorDecl " + P(pl, pc) + " (Annos (slice)) (Mod (TypeModifiers (Vis \"\") (Abstract false) (Final false) (Static false) (Const false))) (Params " + SL(pps) + ") (Body (nil)))"
        }
        String base = "(nil)"
        if self.atOp(":") { self.next(); base = self.parseType() }
        List<String> protos = []
        if self.atKw("implements") {
            self.next()
            while self.at(2) { protos.push(self.parseType()); if self.at(16) { self.next() } else { break } }
        }
        if self.at(12) { self.next() }
        List<String> fields = []
        List<String> methods = []
        List<String> ctors = []
        List<String> items = []
        List<String> sigs = []
        if kw == "protocol" {
            while !self.at(13) && !self.eof() {
                if self.at(1) { self.next(); continue }
                String ms = self.parseModsDump()
                Bool vd = false
                String rt = ""
                if self.at(2) && self.cur().text == "void" { vd = true; self.next() } else { rt = self.parseType() }
                String mn = ""
                if self.at(2) { mn = self.next().text }
                List<String> ps = self.parseParams()
                if self.at(1) { self.next() }
                sigs.push("(ProtocolSig " + P(sl, sc) + " (Annos (slice)) (Mod " + ms + ") (Name " + q(mn) +
                    ") (Void " + B(vd) + ") (Ret " + self.retv(vd, rt) + ") (Params " + SL(ps) + "))")
            }
        } else if kw == "enum" {
            while !self.at(13) && !self.eof() {
                if self.at(1) { self.next(); continue }
                if self.at(2) {
                    Tok it = self.cur()
                    // 数据项/简单项判别：Name 后紧跟 ( 或 , / }
                    self.next()
                    List<String> args = []
                    if self.at(10) {
                        self.next()
                        while !self.at(11) && !self.eof() {
                            if self.at(16) { self.next(); continue }
                            args.push(self.parseExpr().d)
                        }
                        if self.at(11) { self.next() }
                    }
                    String val = "(nil)"
                    if self.atOp("=") { self.next(); val = self.parseExpr().d }
                    items.push("(EnumItem " + P(it.line, it.col) + " (Annos (slice)) (Name " + q(it.text) +
                        ") (Value " + val + ") (Args " + SL(args) + "))")
                    if self.at(16) { self.next() }
                    continue
                }
                break
            }
            while !self.at(13) && !self.eof() {
                if self.at(1) { self.next(); continue }
                String r = self.parseMember(name, fields, methods, ctors)
                if r != "" { methods.push(r) }
            }
        } else if kw == "annotation" {
            while !self.at(13) && !self.eof() {
                if self.at(1) { self.next(); continue }
                fields.push(self.parseField())
            }
        } else if kw == "factory" || kw == "extension" {
            if self.atKw("for") { self.next(); base = self.parseType() }
            if kw == "extension" && base == "(nil)" {
                base = "(NamedType " + P(nl, nc) + " (Qual (slice " + q(name) + ")) (Args (slice)))"
            }
            // factory 的 `{` 在 target 之后（`factory F for T {`）；通用位置在 target 之前检查不到。
            if self.at(12) { self.next() }
            while !self.at(13) && !self.eof() {
                if self.at(1) { self.next(); continue }
                String r = self.parseMember(name, fields, methods, ctors)
                if r != "" { methods.push(r) }
            }
        } else {
            while !self.at(13) && !self.eof() {
                if self.at(1) { self.next(); continue }
                String r = self.parseMember(name, fields, methods, ctors)
                if r != "" { methods.push(r) }
            }
        }
        if self.at(13) { self.next() }
        if kw == "class" {
            return "(ClassDecl " + P(nl, nc) + " (Annos " + SL(annos) + ") (Mod " + self.modDump(m) + ") (Name " + q(name) +
                ") (TypePars " + SLS(tps) + ") (Primary " + primary + ") (Base " + base + ") (Protocols " + SL(protos) +
                ") (Fields " + SL(fields) + ") (Methods " + SL(methods) + ") (Ctors " + SL(ctors) + "))"
        }
        if kw == "struct" {
            return "(StructDecl " + P(nl, nc) + " (Annos " + SL(annos) + ") (Mod " + self.modDump(m) + ") (Name " + q(name) +
                ") (TypePars " + SLS(tps) + ") (Primary " + primary + ") (Fields " + SL(fields) + ") (Methods " + SL(methods) +
                ") (Ctors " + SL(ctors) + "))"
        }
        if kw == "protocol" {
            return "(ProtocolDecl " + P(nl, nc) + " (Annos " + SL(annos) + ") (Name " + q(name) + ") (Extends " + SL(protos) +
                ") (Sigs " + SL(sigs) + "))"
        }
        if kw == "enum" {
            return "(EnumDecl " + P(nl, nc) + " (Annos " + SL(annos) + ") (Mod " + self.modDump(m) + ") (Name " + q(name) +
                ") (Items " + SL(items) + ") (IsData " + B(fields.length() > 0 || methods.length() > 0 || ctors.length() > 0) +
                ") (Fields " + SL(fields) + ") (Methods " + SL(methods) + ") (Ctors " + SL(ctors) + "))"
        }
        if kw == "singleton" {
            return "(SingletonDecl " + P(nl, nc) + " (Annos " + SL(annos) + ") (Mod " + self.modDump(m) + ") (Name " + q(name) +
                ") (Fields " + SL(fields) + ") (Methods " + SL(methods) + ") (Ctors " + SL(ctors) + "))"
        }
        if kw == "factory" {
            return "(FactoryDecl " + P(nl, nc) + " (Annos " + SL(annos) + ") (Mod " + self.modDump(m) + ") (Name " + q(name) +
                ") (Target " + base + ") (Methods " + SL(methods) + "))"
        }
        return "(ExtensionDecl " + P(nl, nc) + " (Annos " + SL(annos) + ") (Mod " + self.modDump(m) + ") (Target " + base +
            ") (Methods " + SL(methods) + "))"
    }

    String parseModsDump() {
        M mm = self.parseMods()
        return self.modDump(mm)
    }

    String parseMember(String cls, List<String> fields, List<String> methods, List<String> ctors) {
        List<String> annos = self.parseAnnos()
        M m = self.parseMods()
        Int ml = self.cur().line
        Int mc = self.cur().col
        if self.at(2) && self.cur().text == cls && self.toks.get(self.i + 1).kind == 10 {
            self.next()
            String c = self.parseCtor(ml, mc, annos)
            ctors.push(c)
            return ""
        }
        Bool vd = false
        String rt = ""
        if self.at(2) && self.cur().text == "void" { vd = true; self.next() } else { rt = self.parseType() }
        String nm = ""
        Int nml = ml
        Int nmc = mc
        if self.at(2) { Tok nt = self.next(); nm = nt.text; nml = nt.line; nmc = nt.col }
        List<String> tps = []
        if self.atOp("<") {
            self.next()
            while !self.atOp(">") && !self.eof() { if self.at(2) { tps.push(self.next().text) } else { self.next() } }
            if self.atOp(">") { self.next() }
        }
        if self.at(10) {
            List<String> ps = self.parseParams()
            String body = self.parseBlock()
            methods.push("(MethodDecl " + P(nml, nmc) + " (Annos " + SL(annos) + ") (Mod " + self.modDump(m) + ") (Name " + q(nm) +
                ") (TypePars " + SLS(tps) + ") (Void " + B(vd) + ") (Ret " + self.retv(vd, rt) + ") (Params " + SL(ps) + ") (Body " + body +
                ") (IsDeinit " + B(nm == "deinit") + "))")
            return ""
        }
        String init = "(nil)"
        if self.atOp("=") { self.next(); init = self.parseExpr().d }
        if self.at(1) { self.next() }
        fields.push("(FieldDecl " + P(nml, nmc) + " (Annos " + SL(annos) + ") (Mod " + self.modDump(m) + ") (Type " + rt +
            ") (Name " + q(nm) + ") (Canonical \"\") (Init " + init + "))")
        return ""
    }

    String parseField() {
        List<String> annos = self.parseAnnos()
        M m = self.parseMods()
        Int l = self.cur().line
        Int c = self.cur().col
        String ty = self.parseType()
        String nm = ""
        Int nml = l
        Int nmc = c
        if self.at(2) { Tok nt = self.next(); nm = nt.text; nml = nt.line; nmc = nt.col }
        String init = "(nil)"
        if self.atOp("=") { self.next(); init = self.parseExpr().d }
        if self.at(1) { self.next() }
        return "(FieldDecl " + P(nml, nmc) + " (Annos " + SL(annos) + ") (Mod " + self.modDump(m) + ") (Type " + ty +
            ") (Name " + q(nm) + ") (Canonical \"\") (Init " + init + "))"
    }

    String parseCtor(Int l, Int c, List<String> annos) {
        Int pl = self.cur().line
        Int pc = self.cur().col
        List<String> ps = self.parseParams()
        String body = self.parseBlock()
        return "(CtorDecl " + P(pl, pc) + " (Annos " + SL(annos) + ") (Mod (TypeModifiers (Vis \"\") (Abstract false) (Final false) (Static false) (Const false))) (Params " + SL(ps) + ") (Body " + body + "))"
    }

    String parseAnnotationDecl(Int sl, Int sc, List<String> annos) {
        self.next() // @annotation
        String name = ""
        if self.at(2) { name = self.next().text }
        if self.at(12) { self.next() }
        List<String> fs = []
        while !self.at(13) && !self.eof() {
            if self.at(1) { self.next(); continue }
            fs.push(self.parseField())
        }
        if self.at(13) { self.next() }
        return "(AnnotationDecl " + P(sl, sc) + " (Annos " + SL(annos) + ") (Mod (TypeModifiers (Vis \"\") (Abstract false) (Final false) (Static false) (Const false))) (Name " + q(name) +
            ") (Fields " + SL(fs) + "))"
    }

    String parseParam() {
        Int sl = self.cur().line
        Int sc = self.cur().col
        Bool fin = false
        if self.atKw("final") { fin = true; self.next() }
        String ty = self.parseType()
        String nm = ""
        if self.at(2) { nm = self.next().text }
        return "(Param " + P(sl, sc) + " (Annos (slice)) (Final " + B(fin) + ") (Type " + ty + ") (Name " + q(nm) + "))"
    }

    String parseType() {
        Tok t = self.cur()
        String base = ""
        if self.at(10) {
            self.next()
            List<String> es = []
            while !self.at(11) && !self.eof() {
                if self.at(16) { self.next(); continue }
                es.push(self.parseType())
            }
            if self.at(11) { self.next() }
            Tok after = self.cur()
            base = "(TupleTypeRef " + P(after.line, after.col) + " (Elems " + SL(es) + "))"
        } else {
            List<String> qn = []
            if self.at(2) { qn.push(self.next().text) }
            while self.atOp(".") {
                self.next()
                if self.at(2) { qn.push(self.next().text) }
            }
            List<String> tas = []
            if self.atOp("<") {
                self.next()
                while !self.atOp(">") && !self.eof() {
                    if self.at(16) { self.next(); continue }
                    if self.at(9) && self.cur().text == ">>" {
                        // 嵌套泛型右括号被词法器合并为 ">>"：拆成两个 ">"，
                        // 当前层消费一个，插入的一个留给外层 parseType。
                        self.cur().text = ">"
                        Tok extra = new Tok()
                        extra.kind = 9
                        extra.text = ">"
                        extra.line = self.cur().line
                        extra.col = self.cur().col
                        self.toks.insert(self.i + 1, extra)
                        break
                    }
                    tas.push(self.parseType())
                }
                if self.atOp(">") { self.next() }
            }
            base = "(NamedType " + P(t.line, t.col) + " (Qual " + SLS(qn) + ") (Args " + SL(tas) + "))"
            // 函数类型：Ret(Param, ...)，如 Bool(T, T)。new 表达式里的
            // `new Point(2, 3)` 是构造调用，不能按函数类型解析。
            if self.inNew == 0 && self.at(10) {
                self.next()
                List<String> ps = []
                while !self.at(11) && !self.eof() {
                    if self.at(16) { self.next(); continue }
                    ps.push(self.parseType())
                }
                if self.at(11) { self.next() }
                base = "(FuncTypeRef " + P(t.line, t.col) + " (Ret " + base + ") (Params " + SL(ps) + "))"
            }
        }
        List<String> sufs = []
        while true {
            if self.atOp("?") { sufs.push("?"); self.next() }
            else if self.at(14) && self.toks.get(self.i + 1).kind == 15 {
                self.next()
                self.next()
                sufs.push("[]")
            } else { break }
        }
        if sufs.length() > 0 {
            return "(SuffixedType " + P(t.line, t.col) + " (Base " + base + ") (Suffixes " + SLS(sufs) + "))"
        }
        return base
    }

    String parseBlock() {
        Tok o = self.cur()
        if self.at(12) { self.next() }
        List<String> ss = []
        while !self.at(13) && !self.eof() {
            if self.at(1) { self.next(); continue }
            ss.push(self.parseStmt())
        }
        if self.at(13) { self.next() } else {
            Tok e = self.cur()
            self.err("SYN-101", e.line, e.col, "期望`}`")
        }
        return "(Block " + P(o.line, o.col) + " (Stmts " + SL(ss) + "))"
    }

    Bool isTypeStart() {
        if self.at(10) {
            Int j = self.i + 1
            Int dep = 1
            Bool comma = false
            while j < self.toks.length() && dep > 0 {
                Tok x = self.toks.get(j)
                if x.kind == 10 { dep = dep + 1 }
                else if x.kind == 11 { dep = dep - 1 }
                else if x.kind == 16 && dep == 1 { comma = true }
                j = j + 1
            }
            if comma { return true }
        }
        if self.atKw("final") || self.atKw("const") || self.atKw("var") { return true }
        if self.at(2) {
            String n = self.cur().text
            if n == "Int" || n == "String" || n == "Bool" || n == "Char" || n == "Float" ||
                n == "Double" || n == "Long" || n == "UInt" || n == "Text" || n == "Bytes" ||
                n == "Map" || n == "List" || n == "Set" || n == "Result" || n == "Object" || n == "Any" {
                return true
            }
            Int j = self.i + 1
            if self.toks.get(j).kind == 9 && self.toks.get(j).text == "<" {
                Int dep = 1
                j = j + 1
                while j < self.toks.length() && dep > 0 {
                    Tok x = self.toks.get(j)
                    if x.kind == 9 && x.text == "<" { dep = dep + 1 }
                    else if x.kind == 9 && x.text == ">>" { dep = dep - 2 }
                    else if x.kind == 9 && x.text == ">" { dep = dep - 1 }
                    j = j + 1
                }
                if dep > 0 { return false }
            }
            while j + 1 < self.toks.length() && self.toks.get(j).kind == 14 && self.toks.get(j + 1).kind == 15 {
                j = j + 2
            }
            if j + 1 < self.toks.length() && self.toks.get(j).kind == 2 &&
                (self.toks.get(j + 1).kind == 9 || self.toks.get(j + 1).kind == 1) {
                return true
            }
            if j + 1 < self.toks.length() && self.toks.get(j).kind == 9 && self.toks.get(j).text == "?" &&
                self.toks.get(j + 1).kind == 2 {
                return true
            }
        }
        return false
    }

    String parseStmt() {
        Tok t = self.cur()
        if self.at(1) { self.next(); return "(EmptyStmt " + P(t.line, t.col) + ")" }
        if self.atKw("return") {
            self.next()
            String v = "(nil)"
            if !self.at(1) && !self.at(13) && !self.at(0) { v = self.parseExpr().d }
            if self.at(1) { self.next() }
            return "(ReturnStmt " + P(t.line, t.col) + " (Value " + v + "))"
        }
        if self.atKw("if") { return self.parseIf() }
        if self.atKw("while") { return self.parseWhile() }
        if self.atKw("do") { return self.parseDo() }
        if self.atKw("for") { return self.parseFor() }
        if self.atKw("switch") { return self.parseSwitch() }
        if self.atKw("defer") || self.atKw("errdefer") { return self.parseDefer() }
        if self.atKw("throw") {
            self.next()
            String v = self.parseExpr().d
            if self.at(1) { self.next() }
            return "(ThrowStmt " + P(t.line, t.col) + " (Value " + v + "))"
        }
        if self.atKw("break") || self.atKw("continue") || self.atKw("goto") {
            String kw = self.next().text
            String lab = ""
            if self.at(2) { lab = self.next().text }
            if self.at(1) { self.next() }
            String type = "BreakStmt"
            if kw == "continue" { type = "ContinueStmt" }
            if kw == "goto" { type = "GotoStmt" }
            return "(" + type + " " + P(t.line, t.col) + " (Label " + q(lab) + "))"
        }
        if self.at(12) { return self.parseBlock() }
        if self.at(2) && self.toks.get(self.i + 1).kind == 9 && self.toks.get(self.i + 1).text == ":" {
            String lab = self.next().text
            self.next()
            String st = ""
            if self.at(1) { Tok s = self.next(); st = "(EmptyStmt " + P(s.line, s.col) + ")" }
            else { st = self.parseStmt() }
            return "(LabeledStmt " + P(t.line, t.col) + " (Label " + q(lab) + ") (Stmt " + st + "))"
        }
        if self.isTypeStart() || self.atKw("var") {
            return self.parseLocal()
        }
        E e = self.parseExpr()
        if self.cur().kind == 9 && (self.cur().text == "=" || self.cur().text == "+=" || self.cur().text == "-=" ||
            self.cur().text == "*=" || self.cur().text == "/=" || self.cur().text == "%=" || self.cur().text == "&=" ||
            self.cur().text == "|=" || self.cur().text == "^=" || self.cur().text == "<<=" || self.cur().text == ">>=") {
            String op = self.next().text
            E v = self.parseExpr()
            if self.at(1) { self.next() }
            return "(AssignStmt " + P(e.l, e.c) + " (Target " + e.d + ") (Op " + q(op) + ") (Value " + v.d + "))"
        }
        if self.cur().kind == 9 && (self.cur().text == "++" || self.cur().text == "--") {
            String op = self.next().text
            if self.at(1) { self.next() }
            return "(IncDecStmt " + P(e.l, e.c) + " (Target " + e.d + ") (Op " + q(op) + ") (Prefix false))"
        }
        if self.at(1) { self.next() }
        return "(ExprStmt " + P(e.sl, e.sc) + " (X " + e.d + "))"
    }

    String parseLocal() {
        Tok t = self.cur()
        Bool fin = false
        Bool cons = false
        Bool vr = false
        if self.atKw("final") { fin = true; self.next() }
        else if self.atKw("const") { cons = true; self.next() }
        else if self.atKw("var") { vr = true; self.next() }
        String ty = "(nil)"
        if !vr { ty = self.parseType() }
        String nm = ""
        if self.at(2) { nm = self.next().text }
        String init = "(nil)"
        if self.atOp("=") { self.next(); init = self.parseExpr().d }
        if self.at(1) { self.next() }
        return "(LocalDeclStmt " + P(t.line, t.col) + " (Final " + B(fin) + ") (Const " + B(cons) +
            ") (Var " + B(vr) + ") (Type " + ty + ") (Name " + q(nm) + ") (Init " + init + "))"
    }

    String parseIf() {
        Tok t = self.next()
        E c = self.parseExpr()
        String th = self.parseBlock()
        String el = "(nil)"
        if self.atKw("else") {
            self.next()
            if self.atKw("if") { el = self.parseIf() } else { el = self.parseBlock() }
        }
        return "(IfStmt " + P(t.line, t.col) + " (Cond " + c.d + ") (Then " + th + ") (Else " + el + "))"
    }

    String parseWhile() {
        Tok t = self.next()
        E c = self.parseExpr()
        String b = self.parseBlock()
        return "(WhileStmt " + P(t.line, t.col) + " (Cond " + c.d + ") (Body " + b + "))"
    }

    String parseDo() {
        Tok t = self.next()
        String b = self.parseBlock()
        if self.atKw("while") { self.next() }
        E c = self.parseExpr()
        if self.at(1) { self.next() }
        return "(DoWhileStmt " + P(t.line, t.col) + " (Body " + b + ") (Cond " + c.d + "))"
    }

    String parseFor() {
        Tok t = self.next()
        String v = ""
        if self.at(2) { v = self.next().text }
        if self.atKw("in") { self.next() }
        E src = self.parseExpr()
        String b = self.parseBlock()
        return "(ForStmt " + P(t.line, t.col) + " (Var " + q(v) + ") (Src " + src.d + ") (Body " + b + "))"
    }

    String parseSwitch() {
        Tok t = self.next()
        E v = self.parseExpr()
        List<String> cs = []
        String def = "(nil)"
        if self.at(12) { self.next() }
        while !self.at(13) && !self.eof() {
            if self.at(1) { self.next(); continue }
            if self.atKw("case") {
                Tok c = self.next()
                E ex = self.parseExpr()
                if self.atOp(":") { self.next() }
                List<String> ss = []
                while !self.atKw("case") && !self.atKw("default") && !self.at(13) && !self.eof() {
                    if self.at(1) { self.next(); continue }
                    ss.push(self.parseStmt())
                }
                cs.push("(SwitchCase " + P(c.line, c.col) + " (Expr " + ex.d + ") (Stmts " + SL(ss) + ") (Default false))")
            } else if self.atKw("default") {
                Tok c = self.next()
                if self.atOp(":") { self.next() }
                List<String> ss = []
                while !self.atKw("case") && !self.at(13) && !self.eof() {
                    if self.at(1) { self.next(); continue }
                    ss.push(self.parseStmt())
                }
                def = "(SwitchCase " + P(c.line, c.col) + " (Expr (nil)) (Stmts " + SL(ss) + ") (Default true))"
            } else { self.next() }
        }
        if self.at(13) { self.next() }
        return "(SwitchStmt " + P(t.line, t.col) + " (Value " + v.d + ") (Cases " + SL(cs) + ") (Default " + def + "))"
    }

    String parseDefer() {
        Tok t = self.next()
        Bool er = t.text == "errdefer"
        String blk = "(nil)"
        String st = "(nil)"
        if self.at(12) { blk = self.parseBlock() }
        else { st = self.parseStmt() }
        return "(DeferStmt " + P(t.line, t.col) + " (Errdefer " + B(er) + ") (Block " + blk + ") (Stmt " + st + "))"
    }

    E mk(String d, Int l, Int c) { E e = new E(); e.d = d; e.l = l; e.c = c; e.sl = l; e.sc = c; return e }

    E parseExpr() { return self.parseTernary() }

    E parseTernary() {
        E c = self.parseCoalesce()
        if self.atOp("?") {
            Tok t = self.next()
            E a = self.parseExpr()
            if self.atOp(":") { self.next() }
            E b = self.parseTernary()
            E te = self.mk("(Ternary " + P(t.line, t.col) + " (Cond " + c.d + ") (Then " + a.d + ") (Else " + b.d + "))", t.line, t.col)
            te.sl = c.sl
            te.sc = c.sc
            return te
        }
        return c
    }

    E parseCoalesce() {
        E l = self.parseBin(1)
        if self.atOp("??") {
            Tok op = self.next()
            E r = self.parseCoalesce()
            E be = self.mk("(Binary " + P(op.line, op.col) + " (Op \"??\") (L " + l.d + ") (R " + r.d + "))", op.line, op.col)
            be.sl = l.sl
            be.sc = l.sc
            return be
        }
        return l
    }

    Int prec(String op) {
        if op == "||" { return 1 }
        if op == "&&" { return 2 }
        if op == "|" { return 3 }
        if op == "^" { return 4 }
        if op == "&" { return 5 }
        if op == "==" || op == "!=" || op == "===" || op == "!==" { return 6 }
        if op == "<" || op == ">" || op == "<=" || op == ">=" || op == "is" || op == "as" || op == "as?" { return 7 }
        if op == "..<" || op == "..." { return 8 }
        if op == "<<" || op == ">>" { return 9 }
        if op == "+" || op == "-" { return 10 }
        if op == "*" || op == "/" || op == "%" { return 11 }
        return 0
    }

    E parseBin(Int lvl) {
        if lvl > 11 { return self.parseUnary() }
        // B4b 大文件：native codegen 对类局部变量重新赋值不补根，跨安全点的
        // `l = be` 会被 GC 回收（UAF → xn_concat NULL）。用 List<E> 容器生根。
        List<E> lh = []
        lh.push(self.parseBin(lvl + 1))
        while (self.cur().kind == 9 || self.cur().kind == 3) && self.prec(self.cur().text) == lvl {
            E l = lh.get(0)
            Tok op = self.next()
            if (op.text == "<" || op.text == ">" || op.text == "<=" || op.text == ">=") && l.d.indexOf("(Binary ") == 0 && l.d.indexOf("(Op \"") > 0 {
                self.err("SYN-102", op.line, op.col, "比较运算不可链式使用")
                self.err("SYN-108", op.line, op.col, "语句未终止（同一行的下一条语句前缺少 `;`）")
            }
            E r = self.mk("(nil)", 0, 0)
            if op.text == "as" && self.atOp("?") { self.next(); op.text = "as?" }
            if op.text == "is" || op.text == "as" || op.text == "as?" {
                String ty = self.parseType()
                String ta = "(TypeAsExpr " + P(0, 0) + " (Type " + ty + ") (Is " + B(op.text == "is") + ") (NullSafe " + B(op.text == "as?") + "))"
                r = self.mk(ta, 0, 0)
            } else {
                r = self.parseBin(lvl + 1)
            }
            E be = self.mk("(Binary " + P(op.line, op.col) + " (Op " + q(op.text) + ") (L " + l.d + ") (R " + r.d + "))", op.line, op.col)
            be.sl = l.sl
            be.sc = l.sc
            lh.set(0, be)
        }
        return lh.get(0)
    }

    E parseUnary() {
        Tok t = self.cur()
        if (t.kind == 9 && (t.text == "!" || t.text == "-" || t.text == "+" || t.text == "~")) || (t.kind == 3 && t.text == "try") {
            self.next()
            E x = self.parseUnary()
            return self.mk("(Unary " + P(t.line, t.col) + " (Op " + q(t.text) + ") (X " + x.d + "))", t.line, t.col)
        }
        return self.parsePostfix()
    }

    E parsePostfix() {
        // B4b 大文件：同 parseBin，`e` 跨循环迭代被重新赋值，需容器生根。
        List<E> eh = []
        eh.push(self.parsePrimary())
        Bool go = true
        while go {
            E e = eh.get(0)
            if self.genericCallAhead() && e.d.indexOf("(IdentExpr ") == 0 {
                self.next()
                List<String> tas2 = []
                while !self.atOp(">") && !self.eof() {
                    if self.at(16) { self.next(); continue }
                    tas2.push(self.parseType())
                }
                if self.atOp(">") { self.next() }
                List<String> cas = []
                if self.at(10) {
                    self.next()
                    while !self.at(11) && !self.eof() {
                        if self.at(1) { break }
                        if self.at(16) { self.next(); continue }
                        cas.push(self.parseExpr().d)
                    }
                    if self.at(11) { self.next() }
                }
                E ne = self.mk("(Call " + P(e.l, e.c) + " (Callee " + e.d + ") (TypeArgs " + SL(tas2) + ") (Args " + SL(cas) + "))", e.l, e.c)
                ne.sl = e.sl; ne.sc = e.sc; eh.set(0, ne)
            } else if self.atOp(".") || self.atOp("?.") {
                Bool ns = self.cur().text == "?."
                Tok dot = self.next()
                Tok n = self.cur()
                if n.kind == 2 {
                    self.next()
                    String d = "(Member " + P(dot.line, dot.col) + " (X " + e.d + ") (Name " + q(n.text) + ") (NullSafe " + B(ns) + "))"
                    E ne = self.mk(d, dot.line, dot.col); ne.sl = e.sl; ne.sc = e.sc; eh.set(0, ne)
                } else if n.kind == 5 {
                    self.next()
                    String d = "(TupleMember " + P(dot.line, dot.col) + " (X " + e.d + ") (Index " + n.text + ") (NullSafe " + B(ns) + "))"
                    E ne = self.mk(d, dot.line, dot.col); ne.sl = e.sl; ne.sc = e.sc; eh.set(0, ne)
                } else { self.next() }
            } else if self.at(10) {
                self.next()
                List<String> tas = []
                Bool argBad = false
                while !self.at(11) && !self.eof() {
                    if self.at(1) {
                        Tok ce = self.cur()
                        self.err("SYN-101", ce.line, ce.col, "期望`)`")
                        argBad = true
                        break
                    }
                    if self.at(16) { self.next(); continue }
                    tas.push(self.parseExpr().d)
                }
                if self.at(11) { self.next() } else if !argBad {
                    Tok ce = self.cur()
                    self.err("SYN-101", ce.line, ce.col, "期望`)`")
                }
                E ne = self.mk("(Call " + P(e.l, e.c) + " (Callee " + e.d + ") (TypeArgs (slice)) (Args " + SL(tas) + "))", e.l, e.c)
                ne.sl = e.sl; ne.sc = e.sc; eh.set(0, ne)
            } else if self.at(14) {
                self.next()
                E idx = self.parseExpr()
                if self.at(15) { self.next() }
                E ne = self.mk("(Index " + P(e.l, e.c) + " (X " + e.d + ") (Idx " + idx.d + "))", e.l, e.c)
                ne.sl = e.sl; ne.sc = e.sc; eh.set(0, ne)
            } else { go = false }
        }
        return eh.get(0)
    }

    Bool genericCallAhead() {
        if !self.atOp("<") { return false }
        Int dep = 0
        Int j = self.i
        while j < self.toks.length() {
            Tok x = self.toks.get(j)
            if x.kind == 9 && x.text == "<" { dep = dep + 1 }
            else if x.kind == 9 && x.text == ">" {
                dep = dep - 1
                if dep == 0 { return j + 1 < self.toks.length() && self.toks.get(j + 1).kind == 10 }
            }
            j = j + 1
        }
        return false
    }

    Bool lambdaAhead() {
        if !self.at(10) { return false }
        Int dep = 1
        Int j = self.i + 1
        while j < self.toks.length() && dep > 0 {
            Tok x = self.toks.get(j)
            if x.kind == 10 { dep = dep + 1 }
            else if x.kind == 11 { dep = dep - 1 }
            j = j + 1
        }
        return j < self.toks.length() && self.toks.get(j).kind == 9 && self.toks.get(j).text == "->"
    }

    String parseSubExpr(String text) {
        Lexer sl = new Lexer(text)
        List<Tok> ts = []
        Bool go = true
        while go {
            Tok x = sl.next()
            ts.push(x)
            if x.kind == 0 { go = false }
        }
        Parser sp = new Parser(ts)
        return sp.parseExpr().d
    }

    E parsePrimary() {
        Tok t = self.cur()
        if t.kind == 2 {
            self.next()
            if t.text == "true" || t.text == "false" {
                return self.mk("(BoolLit " + P(t.line, t.col) + " (V " + B(t.text == "true") + "))", t.line, t.col)
            }
            if t.text == "null" {
                return self.mk("(NullLit " + P(t.line, t.col) + ")", t.line, t.col)
            }
            return self.mk("(IdentExpr " + P(t.line, t.col) + " (Name " + q(t.text) + "))", t.line, t.col)
        }
        if t.kind == 5 {
            self.next()
            return self.mk("(IntLitExpr " + P(t.line, t.col) + " (Text " + q(t.text) + ") (Base " + str(t.base) + ") (Suffix " + q(t.suffix) + "))", t.line, t.col)
        }
        if t.kind == 6 {
            self.next()
            return self.mk("(FloatLitExpr " + P(t.line, t.col) + " (Text " + q(t.text) + ") (HasSuffixF " + B(t.hasSuffixF) + "))", t.line, t.col)
        }
        if t.kind == 7 {
            self.next()
            return self.mk("(CharLitExpr " + P(t.line, t.col) + " (Rune " + str(t.ch) + "))", t.line, t.col)
        }
        if t.kind == 8 {
            self.next()
            List<String> parts = []
            if t.interps.length() == 0 {
                parts.push("(StrPart (Text " + q(t.value) + ") (Expr (nil)))")
            } else {
                Int j = 0
                while j < t.interps.length() {
                    if t.segs.get(j) != "" {
                        parts.push("(StrPart (Text " + q(t.segs.get(j)) + ") (Expr (nil)))")
                    }
                    parts.push("(StrPart (Text \"\") (Expr " + self.parseSubExpr(t.interps.get(j)) + "))")
                    j = j + 1
                }
                String tail = t.segs.get(t.segs.length() - 1)
                if tail != "" {
                    parts.push("(StrPart (Text " + q(tail) + ") (Expr (nil)))")
                }
            }
            return self.mk("(StrLitExpr " + P(t.line, t.col) + " (Kind " + str(t.str) + ") (Parts " + SL(parts) + "))", t.line, t.col)
        }
        if t.kind == 10 && self.lambdaAhead() {
            self.next()
            List<String> lps = []
            while !self.at(11) && !self.eof() {
                if self.at(16) { self.next(); continue }
                Tok lp = self.cur()
                Bool lf = false
                if self.atKw("final") { lf = true; self.next() }
                String lt = self.parseType()
                String ln = ""
                if self.at(2) { ln = self.next().text }
                lps.push("(LambdaParam " + P(lp.line, lp.col) + " (Type " + lt + ") (Name " + q(ln) + ") (Final " + B(lf) + "))")
            }
            if self.at(11) { self.next() }
            if self.atOp("->") { self.next() }
            String lb = "(nil)"
            String le = "(nil)"
            Bool single = true
            Tok bodyTok = self.cur()
            if self.at(12) { lb = self.parseBlock(); single = false }
            else { le = self.parseExpr().d }
            return self.mk("(Lambda " + P(t.line, t.col) + " (Params " + SL(lps) + ") (Block " + lb + ") (ExprB " + le + ") (Single " + B(single) + "))", t.line, t.col)
        }
        if t.kind == 10 {
            self.next()
            E x = self.parseExpr()
            if self.at(16) {
                List<String> es = [x.d]
                while self.at(16) {
                    self.next()
                    es.push(self.parseExpr().d)
                }
                if self.at(11) { self.next() }
                return self.mk("(Tuple " + P(t.line, t.col) + " (Elems " + SL(es) + "))", t.line, t.col)
            }
            if self.at(11) { self.next() }
            return self.mk("(Paren " + P(t.line, t.col) + " (X " + x.d + "))", t.line, t.col)
        }
        if t.kind == 14 {
            self.next()
            if self.at(15) { self.next(); return self.mk("(ArrayLit " + P(t.line, t.col) + " (Elems (slice)))", t.line, t.col) }
            if self.atOp(":") {
                self.next()
                if self.at(15) { self.next() }
                return self.mk("(MapLit " + P(t.line, t.col) + " (Keys (slice)) (Vals (slice)))", t.line, t.col)
            }
            E first = self.parseExpr()
            if self.atOp(":") {
                self.next()
                E v = self.parseExpr()
                List<String> ks = [first.d]
                List<String> vs = [v.d]
                while self.at(16) {
                    self.next()
                    ks.push(self.parseExpr().d)
                    if self.atOp(":") { self.next() }
                    vs.push(self.parseExpr().d)
                }
                if self.at(15) { self.next() }
                return self.mk("(MapLit " + P(t.line, t.col) + " (Keys " + SL(ks) + ") (Vals " + SL(vs) + "))", t.line, t.col)
            }
            List<String> es = [first.d]
            while self.at(16) {
                self.next()
                es.push(self.parseExpr().d)
            }
            if self.at(15) { self.next() }
            return self.mk("(ArrayLit " + P(t.line, t.col) + " (Elems " + SL(es) + "))", t.line, t.col)
        }
        if t.kind == 3 && t.text == "new" {
            self.next()
            self.inNew = self.inNew + 1
            String ty = self.parseType()
            self.inNew = self.inNew - 1
            if self.at(14) {
                self.next()
                E cnt = self.parseExpr()
                if self.at(15) { self.next() }
                return self.mk("(NewArray " + P(t.line, t.col) + " (Type " + ty + ") (Count " + cnt.d + "))", t.line, t.col)
            }
            List<String> tas = []
            if self.at(10) {
                self.next()
                while !self.at(11) && !self.eof() {
                    if self.at(16) { self.next(); continue }
                    tas.push(self.parseExpr().d)
                }
                if self.at(11) { self.next() }
            }
            return self.mk("(New " + P(t.line, t.col) + " (Type " + ty + ") (Args " + SL(tas) + "))", t.line, t.col)
        }
        self.next()
        return self.mk("(IdentExpr " + P(t.line, t.col) + " (Name " + q(t.text) + "))", t.line, t.col)
    }
}

// B4b-02：参数形态
//   xparser <源码字符串>            （B2 兼容）
//   xparser --diags <源码字符串>     （B2 兼容）
//   xparser --file <path>           （按文件读入，替代 oracle 的 argv 传参）
//   xparser --diags --file <path>
static Int main(String[] args) {
    if args.length() == 0 {
        print("xparser: 需要源码字符串或 --file <path>")
        return 2
    }
    Bool diagMode = false
    Int ai = 0
    if args[ai] == "--diags" {
        diagMode = true
        ai = ai + 1
        if ai >= args.length() { return 2 }
    }
    String src = ""
    if args[ai] == "--file" {
        if ai + 1 >= args.length() { return 2 }
        // readFileText 读失败即 throw（解释器与 native 一致），退出码非 0。
        String path = args[ai + 1]
        src = readFileText(path)
    } else {
        src = args[ai]
    }
    Lexer l = new Lexer(src)
    List<Tok> ts = []
    Bool go = true
    while go {
        Tok t = l.next()
        ts.push(t)
        if t.kind == 0 { go = false }
    }
    Parser p = new Parser(ts)
    String res = p.parseUnit()
    if diagMode {
        print("xnast-diags-simple v1")
        Int i = 0
        while i < p.diags.length() {
            Diag d = p.diags.get(i)
            print(d.code + " " + str(d.line) + " " + str(d.col))
            i = i + 1
        }
        return 0
    }
    print(res)
    return 0
}
