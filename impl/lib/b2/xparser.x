// B2-01：XNull 版词法器（Go xfront.Lex 的 L1 token dump 对照实现）。
// 只输出 token/AST 层数据，不依赖 Go xfront；lex 诊断以 code/line/col 输出。
// 覆盖：注释/BOM/CRLF、自动分号、数字/字符/字符串/插值（基础）、关键字、运算符。
import xdk.text

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

String q(String s) {
    String b = "\""
    Int i = 0
    while i < s.length() {
        String c = s.substring(i, 1)
        if c == "\"" { b = b + "\\\"" }
        else if c == "\\" { b = b + "\\\\" }
        else if c == "\n" { b = b + "\\n" }
        else if c == "\t" { b = b + "\\t" }
        else if c == "\r" { b = b + "\\r" }
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

class Parser {
    List<Tok> toks = []
    Int i = 0
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
        List<String> ds = []
        while !self.eof() {
            if self.at(1) { self.next(); continue }
            if self.atKw("package") {
                self.next()
                while self.at(2) || self.atOp(".") { self.next() }
                if self.at(1) { self.next() }
                continue
            }
            if self.atKw("import") {
                self.next()
                while self.at(2) || self.atOp(".") { self.next() }
                if self.atKw("as") { self.next(); self.next() }
                if self.at(1) { self.next() }
                continue
            }
            ds.push(self.parseTop())
        }
        String body = "(CompilationUnit " + P(sl, sc) + " (Package (nil)) (Imports (slice)) (Decls " + SL(ds) + "))"
        return "(xnast v1 " + body + ")"
    }

    String parseTop() {
        Int sl = self.cur().line
        Int sc = self.cur().col
        Bool pub = false
        Bool pro = false
        Bool priv = false
        Bool stat = false
        while true {
            if self.atKw("public") { pub = true; self.next() }
            else if self.atKw("protected") { pro = true; self.next() }
            else if self.atKw("private") { priv = true; self.next() }
            else if self.atKw("static") { stat = true; self.next() }
            else { break }
        }
        Bool void = false
        String ret = ""
        if self.at(2) && self.cur().text == "void" { void = true; self.next() }
        else { ret = self.parseType() }
        String name = ""
        if self.at(2) { name = self.next().text }
        List<String> tps = []
        if self.atOp("<") {
            self.next()
            while !self.atOp(">") && !self.eof() {
                if self.at(2) { tps.push(self.next().text) } else { self.next() }
            }
            if self.atOp(">") { self.next() }
        }
        List<String> ps = []
        if self.at(10) {
            self.next()
            while !self.at(11) && !self.eof() {
                if self.at(16) { self.next(); continue }
                ps.push(self.parseParam())
            }
            if self.at(11) { self.next() }
        }
        String body = self.parseBlock()
        String retv = "(nil)"
        if void { retv = "(nil)" } else { retv = ret }
        return "(TopFunc " + P(sl, sc) + " (Annos (slice)) (Public " + B(pub) + ") (Protected " + B(pro) +
            ") (Private " + B(priv) + ") (Static " + B(stat) + ") (Void " + B(void) + ") (Ret " + retv +
            ") (Name " + q(name) + ") (TypePars " + SLS(tps) + ") (Params " + SL(ps) + ") (Body " + body + "))"
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
                        self.next()
                        break
                    }
                    tas.push(self.parseType())
                }
                if self.atOp(">") { self.next() }
            }
            base = "(NamedType " + P(t.line, t.col) + " (Qual " + SLS(qn) + ") (Args " + SL(tas) + "))"
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
            if self.toks.get(self.i + 1).kind == 2 && self.toks.get(self.i + 2).kind == 16 {
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
        return "(ExprStmt " + P(e.l, e.c) + " (X " + e.d + "))"
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

    E mk(String d, Int l, Int c) { E e = new E(); e.d = d; e.l = l; e.c = c; return e }

    E parseExpr() { return self.parseTernary() }

    E parseTernary() {
        E c = self.parseBin(1)
        if self.atOp("?") {
            Tok t = self.next()
            E a = self.parseExpr()
            if self.atOp(":") { self.next() }
            E b = self.parseTernary()
            return self.mk("(Ternary " + P(t.line, t.col) + " (Cond " + c.d + ") (Then " + a.d + ") (Else " + b.d + "))", t.line, t.col)
        }
        return c
    }

    Int prec(String op) {
        if op == "||" { return 1 }
        if op == "&&" { return 2 }
        if op == "|" { return 3 }
        if op == "^" { return 4 }
        if op == "&" { return 5 }
        if op == "==" || op == "!=" || op == "===" { return 6 }
        if op == "<" || op == ">" || op == "<=" || op == ">=" { return 7 }
        if op == "..<" || op == "..." { return 8 }
        if op == "<<" || op == ">>" { return 9 }
        if op == "+" || op == "-" { return 10 }
        if op == "*" || op == "/" || op == "%" { return 11 }
        return 0
    }

    E parseBin(Int lvl) {
        if lvl > 11 { return self.parseUnary() }
        E l = self.parseBin(lvl + 1)
        while self.cur().kind == 9 && self.prec(self.cur().text) == lvl {
            Tok op = self.next()
            if (op.text == "<" || op.text == ">" || op.text == "<=" || op.text == ">=") && l.d.indexOf("(Binary ") == 0 && l.d.indexOf("(Op \"") > 0 {
                self.err("SYN-102", op.line, op.col, "比较运算不可链式使用")
            }
            E r = self.parseBin(lvl + 1)
            l = self.mk("(Binary " + P(op.line, op.col) + " (Op " + q(op.text) + ") (L " + l.d + ") (R " + r.d + "))", op.line, op.col)
        }
        return l
    }

    E parseUnary() {
        Tok t = self.cur()
        if t.kind == 9 && (t.text == "!" || t.text == "-" || t.text == "+" || t.text == "~" || t.text == "try") {
            self.next()
            E x = self.parseUnary()
            return self.mk("(Unary " + P(t.line, t.col) + " (Op " + q(t.text) + ") (X " + x.d + "))", t.line, t.col)
        }
        return self.parsePostfix()
    }

    E parsePostfix() {
        E e = self.parsePrimary()
        Bool go = true
        while go {
            if self.atOp(".") || self.atOp("?.") {
                Bool ns = self.cur().text == "?."
                Tok dot = self.next()
                Tok n = self.cur()
                if n.kind == 2 {
                    self.next()
                    String d = "(Member " + P(dot.line, dot.col) + " (X " + e.d + ") (Name " + q(n.text) + ") (NullSafe " + B(ns) + "))"
                    e = self.mk(d, dot.line, dot.col)
                } else if n.kind == 5 {
                    self.next()
                    String d = "(TupleMember " + P(dot.line, dot.col) + " (X " + e.d + ") (Index " + n.text + ") (NullSafe " + B(ns) + "))"
                    e = self.mk(d, dot.line, dot.col)
                } else { self.next() }
            } else if self.at(10) {
                self.next()
                List<String> tas = []
                while !self.at(11) && !self.eof() {
                    if self.at(1) {
                        Tok ce = self.cur()
                        self.err("SYN-101", ce.line, ce.col, "期望`)`")
                        break
                    }
                    if self.at(16) { self.next(); continue }
                    tas.push(self.parseExpr().d)
                }
                if self.at(11) { self.next() } else {
                    Tok ce = self.cur()
                    self.err("SYN-101", ce.line, ce.col, "期望`)`")
                }
                e = self.mk("(Call " + P(e.l, e.c) + " (Callee " + e.d + ") (TypeArgs (slice)) (Args " + SL(tas) + "))", e.l, e.c)
            } else if self.at(14) {
                self.next()
                E idx = self.parseExpr()
                if self.at(15) { self.next() }
                e = self.mk("(Index " + P(e.l, e.c) + " (X " + e.d + ") (Idx " + idx.d + "))", e.l, e.c)
            } else { go = false }
        }
        return e
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
            Int j = 0
            while j < t.segs.length() {
                parts.push("(StrPart (Text " + q(t.segs.get(j)) + ") (Expr (nil)))")
                j = j + 1
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
            String ty = self.parseType()
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

static Int main(String[] args) {
    if args.length() == 0 {
        print("xparser: 需要源码字符串")
        return 2
    }
    String src = args[0]
    Bool diagMode = false
    if src == "--diags" {
        if args.length() < 2 { return 2 }
        diagMode = true
        src = args[1]
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
