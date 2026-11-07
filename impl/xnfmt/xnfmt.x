// xnfmt：XNull 版源码格式化器（M6-B1-02）。
// 口径：收件箱/CEO3/格式化规范-v1.0.0.md（v1.0.0）。
// 与 impl/internal/xnfmt（Go oracle 占位）逐字节一致；B1-03 做全量差分。
//
// B1-02 语料范围（122 个 .x）不出现块注释、跨行字符串、switch/case、
// 三元与可空类型；这些构造的完整规则见规范 §4—§10，后续共享向量补测。

class Tok {
    String text = ""
    Int kind = 0
    Bool gen = false
    Bool ternary = false
    Bool unary = false
    Bool postfix = false
}

class Fmt {
    List<String> lines = []
    List<String> header = []
    List<String> imports = []
    List<String> secComments = []
    List<String> outLines = []
    List<Tok> toks = []
    String pkg = ""
    Int brace = 0
    Int paren = 0
    List<Int> swBase = []
    List<Int> swCase = []
    Int swLen = 0
    Bool lexErr = false

    String format(String src) {
        src = src.replace("\r\n", "\n")
        src = src.replace("\r", "\n")
        if (src.trim() == "") {
            return ""
        }
        self.splitLines(src)
        self.outLines.clear()
        self.header.clear()
        self.imports.clear()
        self.secComments.clear()
        self.pkg = ""
        self.lexErr = false
        Int n = self.lines.length()
        Int i = 0
        Bool scanning = true
        while (scanning && i < n) {
            String lt = self.lines.get(i)
            lt = lt.trim()
            if (lt == "") {
                i = i + 1
            } else {
                scanning = false
            }
        }
        scanning = true
        while (scanning && i < n) {
            String lt = self.lines.get(i)
            String raw = lt
            lt = lt.trim()
            if (lt.startsWith("//")) {
                self.header.push(self.rtrim(raw))
                i = i + 1
            } else {
                scanning = false
            }
        }
        scanning = true
        while (scanning && i < n) {
            String lt = self.lines.get(i)
            lt = lt.trim()
            if (lt == "") {
                i = i + 1
            } else {
                scanning = false
            }
        }
        if (i < n) {
            String lt = self.lines.get(i)
            lt = lt.trim()
            if (lt.startsWith("package ")) {
                self.pkg = lt
                i = i + 1
            }
        }
        // R9.2/R9.3：import 区段含独立注释行（按输入顺序、块内空行删除）。
        while (i < n) {
            String raw = self.lines.get(i)
            String lt = raw.trim()
            if (lt == "") {
                i = i + 1
                continue
            }
            if (lt.startsWith("//")) {
                self.secComments.push(self.rtrim(raw))
                i = i + 1
                continue
            }
            break
        }
        scanning = true
        while (scanning && i < n) {
            String lt = self.lines.get(i)
            lt = lt.trim()
            if (lt == "") {
                i = i + 1
            } else {
                scanning = false
            }
        }
        while (i < n) {
            String lt = self.lines.get(i)
            lt = lt.trim()
            if (lt.startsWith("import ")) {
                self.imports.push(lt)
                i = i + 1
                continue
            }
            if (lt == "") {
                i = i + 1
                continue
            }
            break
        }
        Int bodyStart = i
        self.sortImports()
        Int h = 0
        while (h < self.header.length()) {
            self.emit(self.header.get(h))
            h = h + 1
        }
        if (self.header.length() > 0 && (self.pkg != "" || self.secComments.length() > 0 || self.imports.length() > 0 || bodyStart < n)) {
            self.blank()
        }
        if (self.pkg != "") {
            self.tokenize(self.pkg)
            self.emit(self.formatLine(0))
        }
        if (self.pkg != "" && (self.secComments.length() > 0 || self.imports.length() > 0 || bodyStart < n)) {
            self.blank()
        }
        Int c = 0
        while (c < self.secComments.length()) {
            self.emit(self.secComments.get(c))
            c = c + 1
        }
        if (self.secComments.length() > 0 && (self.imports.length() > 0 || bodyStart < n)) {
            self.blank()
        }
        Int m = 0
        while (m < self.imports.length()) {
            self.tokenize(self.imports.get(m))
            self.emit(self.formatLine(0))
            m = m + 1
        }
        if (self.imports.length() > 0 && bodyStart < n) {
            self.blank()
        }
        self.brace = 0
        self.paren = 0
        self.swBase.clear()
        self.swCase.clear()
        self.swLen = 0
        while (i < n) {
            String raw = self.lines.get(i)
            if (raw.trim() == "") {
                if (self.outLines.length() == 0 || self.outLines.get(self.outLines.length() - 1) == "") {
                    i = i + 1
                    continue
                }
                String next = ""
                Int k = i + 1
                while (k < n) {
                    if (self.lineTrim(k) != "") {
                        next = self.lineTrim(k)
                        break
                    }
                    k = k + 1
                }
                String last = self.outLines.get(self.outLines.length() - 1)
                if (next == "" || last.endsWith("{") || next.startsWith("}")) {
                    i = i + 1
                    continue
                }
                self.blank()
                i = i + 1
                continue
            }
            self.tokenize(raw.trim())
            if (self.toks.length() == 0) {
                i = i + 1
                continue
            }
            Tok first = self.toks.get(0)
            Int lineBrace = self.brace
            Bool hasSwitch = false
            Int ti = 0
            while (ti < self.toks.length()) {
                Tok st = self.toks.get(ti)
                if (st.text == "switch") {
                    hasSwitch = true
                }
                ti = ti + 1
            }
            Int ind = self.indentFor(first.text)
            self.emit(self.formatLine(ind))
            self.updateDepth()
            if (hasSwitch && self.brace > lineBrace) {
                self.swBase.push(lineBrace)
                self.swCase.push(0)
                self.swLen = self.swLen + 1
            }
            if ((first.text == "case" || first.text == "default") && self.swLen > 0) {
                self.swCase.set(self.swLen - 1, 1)
            }
            if (first.text == "}") {
                Bool popping = true
                while (popping && self.swLen > 0) {
                    Int topBase = self.swBase.get(self.swLen - 1)
                    if (self.brace == topBase) {
                        self.swLen = self.swLen - 1
                    } else {
                        popping = false
                    }
                }
            }
            i = i + 1
        }
        return self.joinLines()
    }

    void splitLines(String src) {
        self.lines.clear()
        Int start = 0
        Int i = 0
        Int n = src.length()
        while (i < n) {
            if (src.substring(i, 1) == "\n") {
                self.lines.push(src.substring(start, i - start))
                start = i + 1
            }
            i = i + 1
        }
        self.lines.push(src.substring(start, n - start))
    }

    String joinLines() {
        String res = ""
        Int i = 0
        while (i < self.outLines.length()) {
            if (i > 0) {
                res = res + "\n"
            }
            res = res + self.outLines.get(i)
            i = i + 1
        }
        if (res != "") {
            res = res + "\n"
        }
        return res
    }

    void emit(String s) {
        self.outLines.push(s)
    }

    void blank() {
        Int n = self.outLines.length()
        if (n > 0 && self.outLines.get(n - 1) != "") {
            self.outLines.push("")
        }
    }

    String rtrim(String s) {
        Int n = s.length()
        while (n > 0) {
            String c = s.substring(n - 1, 1)
            if (c == " " || c == "\t" || c == "\r") {
                n = n - 1
            } else {
                break
            }
        }
        return s.substring(0, n)
    }

    String lineTrim(Int i) {
        String s = self.lines.get(i)
        return s.trim()
    }

    String importKey(String line) {
        String t = line.trim()
        if (t.startsWith("import ")) {
            t = t.substring(7, t.length() - 7)
        }
        Int i = 0
        while (i < t.length()) {
            String c = t.substring(i, 1)
            if (c == " " || c == "\t") {
                return t.substring(0, i)
            }
            i = i + 1
        }
        return t
    }

    void sortImports() {
        Int i = 0
        while (i < self.imports.length()) {
            Int min = i
            Int j = i + 1
            while (j < self.imports.length()) {
                String kj = self.importKey(self.imports.get(j))
                String km = self.importKey(self.imports.get(min))
                if (self.compare(kj, km) < 0) {
                    min = j
                }
                j = j + 1
            }
            if (min != i) {
                String tmp = self.imports.get(i)
                self.imports.set(i, self.imports.get(min))
                self.imports.set(min, tmp)
            }
            i = i + 1
        }
    }

    Int compare(String a, String b) {
        String order = "-.0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
        Int i = 0
        while (i < a.length() && i < b.length()) {
            Int ca = order.indexOf(a.substring(i, 1))
            Int cb = order.indexOf(b.substring(i, 1))
            if (ca < 0) {
                ca = 0
            }
            if (cb < 0) {
                cb = 0
            }
            if (ca < cb) {
                return -1
            }
            if (ca > cb) {
                return 1
            }
            i = i + 1
        }
        if (a.length() < b.length()) {
            return -1
        }
        if (a.length() > b.length()) {
            return 1
        }
        return 0
    }

    Int indentFor(String first) {
        Int base = self.brace
        if (first == "}") {
            base = base - 1
        }
        if (base < 0) {
            base = 0
        }
        if (self.swLen > 0 && first != "case" && first != "default" && first != "}") {
            Int top = self.swLen - 1
            Int topBase = self.swBase.get(top)
            Int open = self.swCase.get(top)
            if (open == 1 && self.brace > topBase) {
                base = base + 1
            }
        }
        if (self.paren > 0) {
            Int n = base + self.paren
            if (first == ")" || first == "]") {
                n = n - 1
            }
            if (n < 0) {
                n = 0
            }
            return n
        }
        return base
    }

    void updateDepth() {
        Int i = 0
        while (i < self.toks.length()) {
            Tok t = self.toks.get(i)
            if (t.kind != 2 && t.kind != 1) {
                if (t.text == "{") {
                    self.brace = self.brace + 1
                } else if (t.text == "}") {
                    self.brace = self.brace - 1
                } else if (t.text == "(" || t.text == "[") {
                    self.paren = self.paren + 1
                } else if (t.text == ")" || t.text == "]") {
                    self.paren = self.paren - 1
                }
            }
            i = i + 1
        }
    }

    void tokenize(String s) {
        self.toks.clear()
        Int i = 0
        Int n = s.length()
        while (i < n) {
            String c = s.substring(i, 1)
            if (c == " " || c == "\t" || c == "\r") {
                i = i + 1
                continue
            }
            if (c == "/" && i + 1 < n && s.substring(i + 1, 1) == "/") {
                Tok t = new Tok()
                t.text = self.rtrim(s.substring(i, n - i))
                t.kind = 2
                self.toks.push(t)
                i = n
                continue
            }
            if (c == "/" && i + 1 < n && s.substring(i + 1, 1) == "*") {
                Int j = i + 2
                Bool closed = false
                while (j + 1 < n) {
                    if (s.substring(j, 2) == "*/") {
                        j = j + 2
                        closed = true
                        break
                    }
                    j = j + 1
                }
                Tok t = new Tok()
                t.kind = 2
                if (closed) {
                    t.text = s.substring(i, j - i)
                    i = j
                } else {
                    t.text = self.rtrim(s.substring(i, n - i))
                    self.lexErr = true
                    i = n
                }
                self.toks.push(t)
                continue
            }
            if (c == "$" && i + 1 < n && s.substring(i + 1, 1) == "\"") {
                String quote = "\""
                Int start = i
                Int j = i + 2
                Bool closed = false
                while (j < n) {
                    String d = s.substring(j, 1)
                    if (d == "\\") {
                        j = j + 2
                        continue
                    }
                    if (d == quote) {
                        j = j + 1
                        closed = true
                        break
                    }
                    j = j + 1
                }
                if (!closed) {
                    self.lexErr = true
                }
                if (j > n) {
                    j = n
                }
                Tok t = new Tok()
                t.text = s.substring(start, j - start)
                t.kind = 1
                self.toks.push(t)
                i = j
                continue
            }
            if (c == "\"" || c == "'") {
                String quote = c
                Int j = i + 1
                Bool closed = false
                while (j < n) {
                    String d = s.substring(j, 1)
                    if (d == "\\") {
                        j = j + 2
                        continue
                    }
                    if (d == quote) {
                        j = j + 1
                        closed = true
                        break
                    }
                    j = j + 1
                }
                if (!closed) {
                    self.lexErr = true
                }
                if (j > n) {
                    j = n
                }
                Tok t = new Tok()
                t.text = s.substring(i, j - i)
                t.kind = 1
                self.toks.push(t)
                i = j
                continue
            }
            if (self.isDigit(c)) {
                Int j = i + 1
                while (j < n) {
                    String d = s.substring(j, 1)
                    if (self.isIdentRune(d)) {
                        j = j + 1
                        continue
                    }
                    if (d == "." && j + 1 < n && self.isDigit(s.substring(j + 1, 1))) {
                        j = j + 1
                        continue
                    }
                    break
                }
                Tok t = new Tok()
                t.text = s.substring(i, j - i)
                t.kind = 1
                self.toks.push(t)
                i = j
                continue
            }
            if (self.isIdentStart(c)) {
                Int j = i + 1
                while (j < n && self.isIdentRune(s.substring(j, 1))) {
                    j = j + 1
                }
                Tok t = new Tok()
                t.text = s.substring(i, j - i)
                t.kind = 0
                self.toks.push(t)
                i = j
                continue
            }
            String op = self.matchOp(s, i)
            if (op != "") {
                Tok t = new Tok()
                t.text = op
                t.kind = 3
                self.toks.push(t)
                i = i + op.length()
                continue
            }
            Tok t = new Tok()
            t.text = c
            t.kind = 3
            self.toks.push(t)
            i = i + 1
        }
        self.markAngles()
        self.markTernary()
        self.markUnary()
    }

    String matchOp(String s, Int i) {
        Int n = s.length()
        if (i + 3 <= n) {
            String t = s.substring(i, 3)
            if (t == "..<" || t == "..." || t == ">>=" || t == "<<=" || t == "===") {
                return t
            }
        }
        if (i + 2 <= n) {
            String t = s.substring(i, 2)
            if (t == "?." || t == "??" || t == "==" || t == "!=" || t == "<=" || t == ">=" || t == "&&" || t == "||" || t == "+=" || t == "-=" || t == "*=" || t == "/=" || t == "%=" || t == "&=" || t == "|=" || t == "^=" || t == "<<" || t == ">>" || t == "->" || t == "++" || t == "--") {
                return t
            }
        }
        return ""
    }

    Bool isDigit(String c) {
        return "0123456789".indexOf(c) >= 0
    }

    Bool isIdentStart(String c) {
        return c == "_" || "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ".indexOf(c) >= 0
    }

    Bool isIdentRune(String c) {
        return self.isIdentStart(c) || self.isDigit(c)
    }

    void markAngles() {
        Int i = 0
        while (i < self.toks.length()) {
            Tok t = self.toks.get(i)
            if (t.text == "<" && i > 0 && self.genericStart(self.toks.get(i - 1))) {
                Int depth = 0
                Bool ok = false
                Int j = i
                while (j < self.toks.length()) {
                    Tok xt = self.toks.get(j)
                    String x = xt.text
                    if (x == "<") {
                        depth = depth + 1
                    } else if (x == ">") {
                        depth = depth - 1
                    } else if (x == ">>") {
                        depth = depth - 2
                    } else if (!self.angleAllowed(xt)) {
                        break
                    }
                    if (depth <= 0) {
                        ok = true
                        break
                    }
                    j = j + 1
                }
                if (ok && j < self.toks.length()) {
                    t.gen = true
                    Tok closeTok = self.toks.get(j)
                    closeTok.gen = true
                }
            }
            i = i + 1
        }
    }

    Bool genericStart(Tok t) {
        return t.kind == 0 || t.text == "]" || t.text == ">"
    }

    Bool angleAllowed(Tok t) {
        if (t.kind == 0) {
            return true
        }
        return t.text == "," || t.text == "." || t.text == "[" || t.text == "]" || t.text == "?" || t.text == "<" || t.text == ">" || t.text == ">>" || t.text == "(" || t.text == ")" || t.text == "->"
    }

    void markTernary() {
        Int i = 0
        while (i < self.toks.length()) {
            Tok qi = self.toks.get(i)
            if (qi.text == "?") {
                Int depth = 0
                Int j = i + 1
                while (j < self.toks.length()) {
                    Tok xt = self.toks.get(j)
                    String x = xt.text
                    if (x == "(" || x == "[") {
                        depth = depth + 1
                    } else if (x == ")" || x == "]") {
                        depth = depth - 1
                    } else if (x == ":") {
                        if (depth == 0) {
                            qi.ternary = true
                            xt.ternary = true
                            j = self.toks.length()
                        }
                    } else if (x == ";" || x == "{" || x == "}") {
                        j = self.toks.length()
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
    }

    void markUnary() {
        Int i = 0
        while (i < self.toks.length()) {
            Tok t = self.toks.get(i)
            if (t.text == "!" || t.text == "~") {
                t.unary = true
            } else if (t.text == "++" || t.text == "--") {
                if (i > 0 && self.exprEnd(self.toks.get(i - 1))) {
                    t.postfix = true
                } else {
                    t.unary = true
                }
            } else if (t.text == "+" || t.text == "-") {
                if (!(i > 0 && self.exprEnd(self.toks.get(i - 1)))) {
                    t.unary = true
                }
            }
            i = i + 1
        }
    }

    Bool exprEnd(Tok t) {
        if (t.kind == 0) {
            return !self.keywordNoEnd(t.text)
        }
        if (t.kind == 1) {
            return true
        }
        if (t.text == ")" || t.text == "]" || t.text == "}" || t.text == ">") {
            return true
        }
        return t.postfix
    }

    Bool keywordNoEnd(String s) {
        return s == "return" || s == "throw" || s == "if" || s == "else" || s == "while" || s == "do" || s == "for" || s == "in" || s == "switch" || s == "case" || s == "default" || s == "defer" || s == "errdefer" || s == "try" || s == "new" || s == "const" || s == "final" || s == "var" || s == "static" || s == "public" || s == "private" || s == "protected" || s == "class" || s == "struct" || s == "protocol" || s == "enum" || s == "singleton" || s == "extension" || s == "annotation" || s == "import" || s == "package" || s == "as" || s == "is" || s == "void"
    }

    String formatLine(Int ind) {
        String b = ""
        Int k = 0
        while (k < ind * 4) {
            b = b + " "
            k = k + 1
        }
        Int i = 0
        while (i < self.toks.length()) {
            if (i > 0) {
                String sp = self.sep(self.toks.get(i - 1), self.toks.get(i))
                b = b + sp
            }
            Tok ct = self.toks.get(i)
            b = b + ct.text
            i = i + 1
        }
        return b
    }

    String sep(Tok prev, Tok cur) {
        if (cur.kind == 2) {
            return " "
        }
        if (prev.text == "@") {
            return ""
        }
        if (prev.text == "." || prev.text == "?." || cur.text == "." || cur.text == "?.") {
            return ""
        }
        if (prev.unary || cur.postfix) {
            return ""
        }
        if (cur.text == "," || cur.text == ";") {
            return ""
        }
        if (cur.text == ")" || cur.text == "]") {
            return ""
        }
        if (prev.text == "(" || prev.text == "[") {
            return ""
        }
        if (cur.text == "(") {
            if (self.controlKeyword(prev.text)) {
                return " "
            }
            if (prev.kind == 0 || prev.text == ")" || prev.text == "]" || prev.text == ">" || prev.gen) {
                return ""
            }
            return " "
        }
        if (cur.text == "[") {
            if (prev.kind == 0 || prev.text == ")" || prev.text == "]" || prev.text == ">" || prev.gen) {
                return ""
            }
            return " "
        }
        if (prev.text == "," || prev.text == ";") {
            return " "
        }
        if (cur.text == ":") {
            if (cur.ternary) {
                return " "
            }
            return ""
        }
        if (prev.text == ":") {
            return " "
        }
        if (cur.text == "{") {
            return " "
        }
        if (prev.text == "{") {
            if (cur.text == "}") {
                return ""
            }
            return " "
        }
        if (cur.text == "}") {
            if (prev.text == "{") {
                return ""
            }
            return " "
        }
        if (self.isRange(prev.text) || self.isRange(cur.text)) {
            return ""
        }
        if (cur.gen) {
            return ""
        }
        if (prev.gen && prev.text == "<") {
            return ""
        }
        if (cur.text == "?" && !cur.ternary) {
            return ""
        }
        if (prev.text == "?" && !prev.ternary) {
            if (cur.text == "[" || cur.text == "]" || cur.text == ")" || cur.text == "," || cur.text == ";") {
                return ""
            }
        }
        return " "
    }

    Bool controlKeyword(String s) {
        return s == "if" || s == "while" || s == "for" || s == "switch" || s == "case"
    }

    Bool isRange(String s) {
        return s == "..<" || s == "..."
    }

    Bool hasLexError() {
        return self.lexErr
    }
}

static Int main(String[] args) {
    if (args.length() == 0) {
        writeFileText("/dev/stderr", "xnfmt: FMT-104 参数不是可读文件\n")
        return 2
    }
    Int i = 0
    Fmt f = new Fmt()
    while (i < args.length()) {
        String path = args[i]
        if (!pathExists(path) || pathExists(path + "/")) {
            writeFileText("/dev/stderr", "xnfmt: FMT-104 参数不是可读文件：" + path + "\n")
            return 2
        }
        String src = readFileText(path)
        // R3.1 / FMT-102：输入必须是合法 UTF-8（与 Go oracle 对齐）。
        if (utf8Valid(src) != 0) {
            writeFileText("/dev/stderr", "xnfmt: " + path + ":0:0: error[FMT-102]: 输入不是合法 UTF-8\n")
            return 2
        }
        String res = f.format(src)
        // R13.6 / FMT-101：字符串/字符/块注释未闭合等词法错误（与 Go oracle 对齐）。
        if (f.hasLexError()) {
            writeFileText("/dev/stderr", "xnfmt: " + path + ":0:0: error[FMT-101]: 词法错误（字面量或块注释未闭合）\n")
            return 2
        }
        Int rc = writeFileText(path, res)
        if (rc != 0) {
            return 2
        }
        i = i + 1
    }
    return 0
}
