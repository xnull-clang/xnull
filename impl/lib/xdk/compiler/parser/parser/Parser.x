// XNull 版词法器（Go xfront.Lex 的 L1 token dump 对照实现）。
// 只输出 token/AST 层数据，不依赖 Go xfront；lex 诊断以 code/line/col 输出。
// 覆盖：注释/BOM/CRLF、自动分号、数字/字符/字符串/插值（基础）、关键字、运算符。
// 新增 --file <path> 文件输入模式（import xdk.sys 提供 readFileText）。
package xdk.compiler.parser; import xdk.sys

































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































































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
        // 大文件：parseTop 产出的文本已是规范 S 表达式；直接输出，避免
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
            if kw == "protocol" {
                self.err("SYN-101", self.cur().line, self.cur().col, "协议不支持类型参数")
            }
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
            if kw == "enum" {
                self.err("SYN-101", self.cur().line, self.cur().col, "enum 不支持 implements")
            }
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
                Bool hadParen = self.at(10)
                List<String> ps = self.parseParams()
                if !hadParen {
                    self.err("SYN-101", self.cur().line, self.cur().col, "协议不能声明字段（缺少 `()`）")
                }
                if self.at(1) { self.next() }
                if self.at(12) {
                    self.err("SYN-101", self.cur().line, self.cur().col, "协议方法不能有函数体")
                    self.parseBlock()
                }
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
        Bool sawDef = false
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
                if sawDef {
                    self.err("SYN-101", c.line, c.col, "switch 重复 default")
                }
                sawDef = true
                if self.atOp(":") { self.next() }
                List<String> ss = []
                while !self.atKw("case") && !self.atKw("default") && !self.at(13) && !self.eof() {
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
        // 大文件：native codegen 对类局部变量重新赋值不补根，跨安全点的
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
        // 大文件：同 parseBin，`e` 跨循环迭代被重新赋值，需容器生根。
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
