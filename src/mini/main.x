// XNull mini compiler —— M1 loader + lexer
package mini

List<String> loadedFiles = []
String loadBaseDir = ""
String loadRoot = ""
Bool xdkFullSource = false
List<String> ffiNames = []
List<String> ffiCNames = []
List<String> ffiRets = []
List<String> ffiParamSpecs = []
List<String> ffiErrParams = []
List<String> ffiErrRets = []

class Token {
    final String kind
    final String text
    final Int line
    final Int col

    Token(String kind, String text, Int line, Int col) {
        self.kind = kind
        self.text = text
        self.line = line
        self.col = col
    }
}



class AstNode {
    final String kind
    final String text
    final Int line
    final Int col
    final List<AstNode> kids

    AstNode(String kind, String text, Int line, Int col) {
        self.kind = kind
        self.text = text
        self.line = line
        self.col = col
        self.kids = []
    }

    Void add(AstNode kid) {
        kids.push(kid)
    }

    Void setKid(Int idx, AstNode v) {
        List<AstNode> tmp = []
        Int i = 0
        while i < kids.length() {
            if i == idx {
                tmp.push(v)
            } else {
                tmp.push(kids.get(i))
            }
            i = i + 1
        }
        while kids.length() > 0 {
            kids.remove(kids.length() - 1)
        }
        i = 0
        while i < tmp.length() {
            kids.push(tmp.get(i))
            i = i + 1
        }
    }

    Void dump(Int depth) {
        String pad = ""
        Int i = 0
        while i < depth {
            pad = pad + "  "
            i = i + 1
        }
        if text == "" {
            print(pad + kind)
        } else {
            print(pad + kind + ": " + text)
        }
        Int j = 0
        while j < kids.length() {
            AstNode kid = kids.get(j)
            kid.dump(depth + 1)
            j = j + 1
        }
    }
}

class Parser {
    final List<Token> ts
    Int pos
    String error
    String errorCode
    Int errorLine
    Int errorCol

    Parser(List<Token> ts) {
        self.ts = ts
        self.pos = 0
        self.error = ""
        self.errorCode = ""
        self.errorLine = 1
        self.errorCol = 1
    }

    Bool hasError() {
        return self.error != ""
    }

    Token peek() {
        if self.pos < self.ts.length() {
            return self.ts.get(self.pos)
        }
        return new Token("eof", "", 1, 1)
    }

    Token advance() {
        Token t = self.peek()
        if self.pos < self.ts.length() - 1 {
            self.pos = self.pos + 1
        }
        return t
    }

    Bool eof() {
        Token t = self.peek()
        return t.kind == "eof"
    }

    Bool at(String text) {
        if self.hasError() {
            return false
        }
        Token t = self.peek()
        return t.text == text
    }

    Bool kind(String k) {
        if self.hasError() {
            return false
        }
        Token t = self.peek()
        return t.kind == k
    }

    Bool eat(String text) {
        if self.at(text) {
            self.advance()
            return true
        }
        return false
    }

    Token expect(String text) {
        if self.at(text) {
            return self.advance()
        }
        self.fail("expected " + text)
        return self.peek()
    }

    Void fail(String msg) {
        if self.error == "" {
            Token t = self.peek()
            self.error = msg
            self.errorLine = t.line
            self.errorCol = t.col
        }
    }

    AstNode node(String kindName, String text, Token t) {
        return new AstNode(kindName, text, t.line, t.col)
    }

    AstNode parse() {
        AstNode program = new AstNode("Program", "", 1, 1)
        while !self.hasError() && !self.eof() {
            AstNode d = self.parseTop()
            if !self.hasError() && d.kind != "error" {
                program.add(d)
            }
        }
        return program
    }

    String parsePath() {
        String path = ""
        if !self.kind("ident") && !self.kind("kw") {
            self.fail("expected package/import name")
            return path
        }
        Token first = self.advance()
        path = first.text
        while self.eat(".") {
            if !self.kind("ident") && !self.kind("kw") {
                self.fail("expected name after .")
                return path
            }
            Token part = self.advance()
            path = path + "." + part.text
        }
        return path
    }

    AstNode parseTop() {
        Token t = self.peek()
        if self.at("package") {
            self.advance()
            String name = self.parsePath()
            AstNode n = self.node("Package", name, t)
            self.eat(";")
            return n
        }
        if self.at("import") {
            self.advance()
            String name = self.parsePath()
            AstNode n = self.node("Import", name, t)
            self.eat(";")
            return n
        }
        if self.at("final") || self.at("abstract") || self.at("public") {
            self.advance()
            return self.parseTop()
        }
        if self.at("class") {
            return self.parseClassDecl("Class")
        }
        if self.at("struct") {
            return self.parseClassDecl("Struct")
        }
        if self.at("enum") {
            return self.parseEnum()
        }
        if self.at("protocol") {
            return self.parseProtocol()
        }
        if self.at("static") {
            return self.parseFunc()
        }
        if self.kind("kw") {
            return self.parseFunc()
        }
        if self.kind("ident") {
            // 顶层字段：`List<String> names = []`，与函数声明区分。
            Int save = self.pos
            String ty = self.parseType()
            if self.kind("ident") {
                Token nt = self.advance()
                if self.at("=") || self.at(";") {
                    AstNode f = self.node("TopField", ty + " " + nt.text, nt)
                    if self.eat("=") {
                        f.add(self.parseExpr())
                    }
                    self.eat(";")
                    return f
                }
            }
            self.pos = save
            return self.parseFunc()
        }
        self.fail("unexpected top-level token: " + t.text)
        return self.node("error", t.text, t)
    }

    AstNode parseClassDecl(String kindName) {
        Token t = self.peek()
        self.advance()
        if !self.kind("ident") {
            self.fail("expected type name")
            return self.node("error", "", t)
        }
        Token nt = self.advance()
        String name = nt.text
        AstNode cls = self.node(kindName, name, t)
        if self.eat("<") {
            AstNode tp = self.node("TypeParams", "", t)
            while !self.hasError() && !self.at(">") {
                if !self.kind("ident") {
                    self.fail("expected type parameter")
                    break
                }
                Token pn = self.advance()
                tp.add(new AstNode("TypeParam", pn.text, pn.line, pn.col))
                if !self.eat(",") {
                    break
                }
            }
            self.expect(">")
            cls.add(tp)
        }
        if self.eat(":") {
            String base = self.parseType()
            cls.add(new AstNode("Base", base, t.line, t.col))
        }
        if self.eat("implements") {
            while !self.hasError() {
                String pn = self.parseType()
                cls.add(new AstNode("Implements", pn, t.line, t.col))
                if !self.eat(",") {
                    break
                }
            }
        }
        self.expect("{")
        while !self.hasError() && !self.at("}") && !self.eof() {
            Bool isStatic = false
            while self.at("static") || self.at("final") || self.at("public") || self.at("private") || self.at("protected") {
                if self.at("static") {
                    isStatic = true
                }
                self.advance()
            }
            String ty = self.parseType()
            if self.at("(") && ty == name {
                Token ct = self.peek()
                AstNode ctor = self.node("Ctor", name, ct)
                self.expect("(")
                if !self.at(")") {
                    while !self.hasError() {
                        String pt = self.parseType()
                        if !self.kind("ident") {
                            self.fail("expected constructor parameter name")
                            break
                        }
                        Token pn = self.advance()
                        ctor.add(new AstNode("Param", pt + " " + pn.text, ct.line, ct.col))
                        if !self.eat(",") {
                            break
                        }
                    }
                }
                self.expect(")")
                ctor.add(self.parseBlock())
                cls.add(ctor)
                continue
            }
            if !self.kind("ident") {
                self.fail("expected member name")
                break
            }
            Token mt = self.advance()
            String mn = mt.text
            if self.at("(") {
                AstNode m = self.node("Method", mn, mt)
                if isStatic {
                    m.add(new AstNode("Static", "", mt.line, mt.col))
                }
                m.add(new AstNode("Ret", ty, mt.line, mt.col))
                self.advance()
                if !self.at(")") {
                    while !self.hasError() {
                        String pt = self.parseType()
                        if !self.kind("ident") {
                            self.fail("expected parameter name")
                            break
                        }
                        Token pn = self.advance()
                        m.add(new AstNode("Param", pt + " " + pn.text, mt.line, mt.col))
                        if !self.eat(",") {
                            break
                        }
                    }
                }
                self.expect(")")
                m.add(self.parseBlock())
                cls.add(m)
            } else {
                AstNode f = self.node("Field", ty + " " + mn, mt)
                if isStatic {
                    f.add(new AstNode("Static", "", mt.line, mt.col))
                }
                if self.eat("=") {
                    f.add(self.parseExpr())
                }
                self.eat(";")
                cls.add(f)
            }
        }
        self.expect("}")
        return cls
    }

    AstNode parseEnum() {
        Token t = self.peek()
        self.advance()
        if !self.kind("ident") {
            self.fail("expected enum name")
            return self.node("error", "", t)
        }
        Token nt = self.advance()
        AstNode e = self.node("Enum", nt.text, t)
        self.expect("{")
        Bool data = false
        while !self.hasError() && !self.at("}") && !self.eof() {
            if !self.kind("ident") {
                self.fail("expected enum item")
                break
            }
            Token it = self.advance()
            AstNode item = self.node("EnumItem", it.text, it)
            if self.eat("(") {
                if !data {
                    e.add(new AstNode("Data", "", it.line, it.col))
                }
                data = true
                if !self.at(")") {
                    while !self.hasError() {
                        item.add(self.parseExpr())
                        if !self.eat(",") {
                            break
                        }
                    }
                }
                self.expect(")")
            } else if self.eat("=") {
                item.add(self.parseExpr())
            }
            e.add(item)
            if self.eat(",") {
                continue
            }
            if self.eat(";") {
                break
            }
            break
        }
        if !self.at("}") {
            data = true
            while !self.hasError() && !self.at("}") && !self.eof() {
                while self.at("static") || self.at("final") || self.at("public") ||
                      self.at("private") || self.at("protected") {
                    self.advance()
                }
                String ty = self.parseType()
                if self.at("(") && ty == e.text {
                    Token ct = self.peek()
                    AstNode ctor = self.node("Ctor", e.text, ct)
                    self.expect("(")
                    if !self.at(")") {
                        while !self.hasError() {
                            String pt = self.parseType()
                            if !self.kind("ident") {
                                self.fail("expected constructor parameter name")
                                break
                            }
                            Token pn = self.advance()
                            ctor.add(new AstNode("Param", pt + " " + pn.text, ct.line, ct.col))
                            if !self.eat(",") {
                                break
                            }
                        }
                    }
                    self.expect(")")
                    ctor.add(self.parseBlock())
                    e.add(ctor)
                    continue
                }
                if !self.kind("ident") {
                    self.fail("expected enum member")
                    break
                }
                Token mt = self.advance()
                if self.at("(") {
                    AstNode m = self.node("Method", mt.text, mt)
                    m.add(new AstNode("Ret", ty, mt.line, mt.col))
                    self.advance()
                    if !self.at(")") {
                        while !self.hasError() {
                            String pt = self.parseType()
                            if !self.kind("ident") {
                                self.fail("expected parameter name")
                                break
                            }
                            Token pn = self.advance()
                            m.add(new AstNode("Param", pt + " " + pn.text, mt.line, mt.col))
                            if !self.eat(",") {
                                break
                            }
                        }
                    }
                    self.expect(")")
                    m.add(self.parseBlock())
                    e.add(m)
                } else {
                    AstNode f = self.node("Field", ty + " " + mt.text, mt)
                    if self.eat("=") {
                        f.add(self.parseExpr())
                    }
                    self.eat(";")
                    e.add(f)
                }
            }
        }
        self.expect("}")
        return e
    }

    AstNode parseProtocol() {
        Token t = self.peek()
        self.advance()
        if !self.kind("ident") {
            self.fail("expected protocol name")
            return self.node("error", "", t)
        }
        Token nt = self.advance()
        AstNode p = self.node("Protocol", nt.text, t)
        if self.eat(":") {
            while !self.hasError() {
                String bn = self.parseType()
                p.add(new AstNode("Extends", bn, t.line, t.col))
                if !self.eat(",") {
                    break
                }
            }
        }
        self.expect("{")
        while !self.hasError() && !self.at("}") && !self.eof() {
            String rt = self.parseType()
            if !self.kind("ident") {
                self.fail("expected protocol method name")
                break
            }
            Token mn = self.advance()
            AstNode m = self.node("Sig", mn.text, mn)
            m.add(new AstNode("Ret", rt, mn.line, mn.col))
            self.expect("(")
            if !self.at(")") {
                while !self.hasError() {
                    String pt = self.parseType()
                    if !self.kind("ident") {
                        self.fail("expected parameter name")
                        break
                    }
                    Token pn = self.advance()
                    m.add(new AstNode("Param", pt + " " + pn.text, mn.line, mn.col))
                    if !self.eat(",") {
                        break
                    }
                }
            }
            self.expect(")")
            self.expect(";")
            p.add(m)
        }
        self.expect("}")
        return p
    }

    AstNode parseFunc() {
        Token t = self.peek()
        if self.eat("static") {
            // static is optional in this parser; visibility is not part of the AST yet.
        }
        String rt = self.parseType()
        if !self.kind("ident") {
            self.fail("expected function name")
            return self.node("error", "", t)
        }
        Token nameToken = self.advance()
        String name = nameToken.text
        AstNode fn = self.node("Func", name, t)
        fn.add(new AstNode("Ret", rt, t.line, t.col))
        if self.eat("<") {
            AstNode tp = new AstNode("TypeParams", "", t.line, t.col)
            while !self.hasError() && !self.at(">") {
                if !self.kind("ident") {
                    self.fail("expected type parameter")
                    break
                }
                Token pn = self.advance()
                tp.add(new AstNode("TypeParam", pn.text, pn.line, pn.col))
                if !self.eat(",") {
                    break
                }
            }
            fn.add(tp)
            self.expect(">")
        }
        self.expect("(")
        if !self.at(")") {
            while !self.hasError() {
                String pt = self.parseType()
                if !self.kind("ident") {
                    self.fail("expected parameter name")
                    break
                }
                Token pnToken = self.advance()
                String pn = pnToken.text
                fn.add(new AstNode("Param", pt + " " + pn, t.line, t.col))
                if !self.eat(",") {
                    break
                }
            }
        }
        self.expect(")")
        fn.add(self.parseBlock())
        return fn
    }

    Bool looksLikeTypeArgs() {
        if !self.at("<") {
            return false
        }
        Int depth = 0
        Int j = 0
        while true {
            Token t = self.look(j)
            if t.kind == "eof" {
                return false
            }
            if t.text == "<" {
                depth = depth + 1
            } else if t.text == ">" {
                depth = depth - 1
                if depth == 0 {
                    return self.look(j + 1).text == "("
                }
            }
            j = j + 1
        }
        return false
    }

    String parseTypeArgsText() {
        self.expect("<")
        String res = ""
        while !self.hasError() && !self.at(">") {
            if res != "" {
                res = res + ","
            }
            res = res + self.parseType()
            if !self.eat(",") {
                break
            }
        }
        self.expect(">")
        return res
    }

    Bool typeHasFuncSuffix() {
        if !self.at("(") {
            return false
        }
        Int depth = 0
        Int j = 0
        while true {
            Token t = self.look(j)
            if t.kind == "eof" {
                return false
            }
            if t.text == "(" {
                depth = depth + 1
            } else if t.text == ")" {
                depth = depth - 1
                if depth == 0 {
                    Token after = self.look(j + 1)
                    return after.kind == "ident"
                }
            }
            j = j + 1
        }
        return false
    }

    String parseType() {
        if self.at("final") {
            self.advance()
        }
        if !self.kind("ident") && !self.kind("kw") {
            self.fail("expected type")
            return ""
        }
        Token t = self.advance()
        String ty = t.text
        while self.eat(".") {
            Token part = self.advance()
            ty = ty + "." + part.text
        }
        if self.eat("<") {
            ty = ty + "<"
            Int depth = 1
            while !self.hasError() && depth > 0 {
                if self.eof() {
                    self.fail("unterminated type arguments")
                    return ty
                }
                if self.at("<") {
                    depth = depth + 1
                } else if self.at(">") {
                    depth = depth - 1
                }
                Token part = self.advance()
                ty = ty + part.text
            }
        }
        if self.typeHasFuncSuffix() {
            self.advance()
            ty = ty + "("
            if !self.at(")") {
                while !self.hasError() {
                    ty = ty + self.parseType()
                    if !self.eat(",") {
                        break
                    }
                    ty = ty + ","
                }
            }
            self.expect(")")
            ty = ty + ")"
        }
        if self.eat("[") {
            self.expect("]")
            ty = ty + "[]"
        }
        if self.eat("?") {
            ty = ty + "?"
        }
        return ty
    }

    String parseNewType() {
        if !self.kind("ident") && !self.kind("kw") {
            self.fail("expected type")
            return ""
        }
        Token t = self.advance()
        String ty = t.text
        while self.eat(".") {
            Token part = self.advance()
            ty = ty + "." + part.text
        }
        if self.eat("<") {
            ty = ty + "<"
            Int depth = 1
            while !self.hasError() && depth > 0 {
                if self.at("<") {
                    depth = depth + 1
                } else if self.at(">") {
                    depth = depth - 1
                }
                Token part = self.advance()
                ty = ty + part.text
            }
        }
        if self.eat("[") {
            self.expect("]")
            ty = ty + "[]"
        }
        return ty
    }

    AstNode parseBlock() {
        Token t = self.peek()
        AstNode block = self.node("Block", "", t)
        self.expect("{")
        while !self.hasError() && !self.at("}") && !self.eof() {
            block.add(self.parseStmt())
        }
        self.expect("}")
        return block
    }

    AstNode parseCaseBody() {
        Token t = self.peek()
        AstNode block = self.node("Block", "", t)
        while !self.hasError() && !self.at("case") && !self.at("default") &&
              !self.at("}") && !self.eof() {
            block.add(self.parseStmt())
        }
        return block
    }

    Token look(Int n) {
        Int i = self.pos + n
        if i >= 0 && i < self.ts.length() {
            return self.ts.get(i)
        }
        return new Token("eof", "", 1, 1)
    }

    Bool isLocalDecl() {
        Token a = self.look(0)
        Token b = self.look(1)
        Token c = self.look(2)
        if !(a.kind == "ident" || a.kind == "kw") {
            return false
        }
        if b.kind == "ident" {
            return c.text == "="
        }
        if b.text == "?" {
            return self.look(3).text == "=" || self.look(3).text == ";"
        }
        if b.text == "[" {
            Token d = self.look(2)
            Token e = self.look(3)
            if d.text == "]" && e.kind == "ident" {
                return true
            }
        }
        if b.text == "<" {
            Int depth = 1
            Int j = 2
            while depth > 0 {
                Token t = self.look(j)
                if t.kind == "eof" {
                    return false
                }
                if t.text == "<" {
                    depth = depth + 1
                }
                if t.text == ">" {
                    depth = depth - 1
                }
                j = j + 1
            }
            Token name = self.look(j)
            return name.kind == "ident"
        }
        if b.text == "(" {
            Int depth = 1
            Int j = 2
            while depth > 0 {
                Token t = self.look(j)
                if t.kind == "eof" {
                    return false
                }
                if t.text == "(" {
                    depth = depth + 1
                } else if t.text == ")" {
                    depth = depth - 1
                }
                j = j + 1
            }
            return self.look(j).kind == "ident" && self.look(j).line == a.line
        }
        return false
    }

    AstNode parseLocal() {
        Token t = self.peek()
        String ty = self.parseType()
        Token name = self.advance()
        self.expect("=")
        AstNode init = self.parseExpr()
        self.eat(";")
        AstNode n = self.node("Local", ty + " " + name.text, t)
        n.add(init)
        return n
    }

    AstNode parseStmt() {
        Token t = self.peek()
        if self.kind("ident") && self.look(1).text == ":" {
            Token name = self.advance()
            self.advance()
            AstNode n = self.node("Label", name.text, t)
            if !self.at("}") && !self.at(";") && !self.eof() {
                n.add(self.parseStmt())
            } else {
                self.eat(";")
            }
            return n
        }
        if self.isLocalDecl() {
            return self.parseLocal()
        }
        if self.eat("goto") {
            if !self.kind("ident") {
                self.fail("expected goto label")
                return self.node("error", "", t)
            }
            Token name = self.advance()
            self.eat(";")
            return self.node("Goto", name.text, t)
        }
        if self.eat("defer") || self.eat("errdefer") {
            Bool isErr = false
            if t.text == "errdefer" {
                isErr = true
            }
            AstNode n = self.node("Defer", t.text, t)
            n.add(self.parseStmt())
            return n
        }
        if self.eat("for") {
            if !self.kind("ident") {
                self.fail("expected for-in variable")
                return self.node("error", "", t)
            }
            Token v = self.advance()
            self.expect("in")
            AstNode first = self.parseExpr()
            if self.at("..") {
                self.advance()
                String op = ".."
                if self.eat(".") {
                    op = "..."
                } else if self.eat("<") {
                    op = "..<"
                } else {
                    self.fail("expected . or < after ..")
                    return self.node("error", "", t)
                }
                AstNode n = self.node("ForRange", op + " " + v.text, t)
                n.add(first)
                n.add(self.parseExpr())
                n.add(self.parseBlock())
                return n
            }
            AstNode n = self.node("ForIn", v.text, t)
            n.add(first)
            n.add(self.parseBlock())
            return n
        }
        if self.eat("return") {
            AstNode n = self.node("Return", "", t)
            if !self.at("}") && !self.at(";") && !self.eof() {
                n.add(self.parseExpr())
            }
            self.eat(";")
            return n
        }
        if self.eat("if") {
            AstNode n = self.node("If", "", t)
            n.add(self.parseExpr())
            n.add(self.parseBlock())
            if self.eat("else") {
                if self.at("if") {
                    AstNode eb = self.node("Block", "", t)
                    eb.add(self.parseStmt())
                    n.add(eb)
                } else {
                    n.add(self.parseBlock())
                }
            }
            return n
        }
        if self.eat("do") {
            AstNode n = self.node("DoWhile", "", t)
            n.add(self.parseBlock())
            self.expect("while")
            n.add(self.parseExpr())
            self.eat(";")
            return n
        }
        if self.eat("while") {
            AstNode n = self.node("While", "", t)
            n.add(self.parseExpr())
            n.add(self.parseBlock())
            return n
        }
        if self.eat("switch") {
            AstNode n = self.node("Switch", "", t)
            n.add(self.parseExpr())
            self.expect("{")
            Bool seenDefault = false
            while !self.hasError() && !self.at("}") && !self.eof() {
                if self.eat("case") {
                    if seenDefault {
                        self.fail("case after default")
                        break
                    }
                    AstNode c = self.node("Case", "", t)
                    c.add(self.parseExpr())
                    self.expect(":")
                    c.add(self.parseCaseBody())
                    n.add(c)
                } else if self.eat("default") {
                    if seenDefault {
                        self.fail("duplicate default")
                        break
                    }
                    seenDefault = true
                    self.expect(":")
                    AstNode d = self.node("Default", "", t)
                    d.add(self.parseCaseBody())
                    n.add(d)
                } else {
                    self.fail("expected case or default")
                    break
                }
            }
            self.expect("}")
            return n
        }
        if self.eat("throw") {
            AstNode n = self.node("Throw", "", t)
            n.add(self.parseExpr())
            self.eat(";")
            return n
        }
        if self.eat("break") {
            self.eat(";")
            return self.node("Break", "", t)
        }
        if self.eat("continue") {
            self.eat(";")
            return self.node("Continue", "", t)
        }
        AstNode e = self.parseExpr()
        if self.eat("=") {
            AstNode a = self.node("Assign", "=", t)
            a.add(e)
            a.add(self.parseExpr())
            self.eat(";")
            return a
        }
        self.eat(";")
        AstNode n = self.node("ExprStmt", "", t)
        n.add(e)
        return n
    }

    AstNode parseExpr() {
        AstNode cond = self.parseOr()
        if self.eat("?") {
            AstNode n = new AstNode("Ternary", "", cond.line, cond.col)
            n.add(cond)
            n.add(self.parseExpr())
            self.expect(":")
            n.add(self.parseExpr())
            return n
        }
        return cond
    }

    AstNode parseOr() {
        AstNode left = self.parseAnd()
        while !self.hasError() && self.at("||") {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parseAnd())
            left = n
        }
        return left
    }

    AstNode parseAnd() {
        AstNode left = self.parseEquality()
        while !self.hasError() && self.at("&&") {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parseEquality())
            left = n
        }
        return left
    }

    AstNode parseEquality() {
        AstNode left = self.parseRel()
        while !self.hasError() && (self.at("==") || self.at("!=")) {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parseRel())
            left = n
        }
        return left
    }

    AstNode parseRel() {
        AstNode left = self.parseBitOr()
        while !self.hasError() && (self.at("<") || self.at("<=") || self.at(">") || self.at(">=")) {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parseBitOr())
            left = n
        }
        return left
    }

    AstNode parseBitOr() {
        AstNode left = self.parseBitXor()
        while !self.hasError() && self.at("|") {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parseBitXor())
            left = n
        }
        return left
    }

    AstNode parseBitXor() {
        AstNode left = self.parseBitAnd()
        while !self.hasError() && self.at("^") {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parseBitAnd())
            left = n
        }
        return left
    }

    AstNode parseBitAnd() {
        AstNode left = self.parseShift()
        while !self.hasError() && self.at("&") {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parseShift())
            left = n
        }
        return left
    }

    AstNode parseShift() {
        AstNode left = self.parseAdd()
        while !self.hasError() {
            Bool right = self.at(">") && self.look(1).text == ">"
            if !self.at("<<") && !right {
                break
            }
            Token op = self.advance()
            String opt = op.text
            if right {
                self.advance()
                opt = ">>"
            }
            AstNode n = self.node("Binary", opt, op)
            n.add(left)
            n.add(self.parseAdd())
            left = n
        }
        return left
    }

    AstNode parseAdd() {
        AstNode left = self.parseMul()
        while !self.hasError() && (self.at("+") || self.at("-")) {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parseMul())
            left = n
        }
        return left
    }

    AstNode parseMul() {
        AstNode left = self.parseCast()
        while !self.hasError() && (self.at("*") || self.at("/") || self.at("%")) {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parseCast())
            left = n
        }
        return left
    }

    AstNode parseCast() {
        AstNode left = self.parsePrimary()
        while !self.hasError() && (self.at("as") || self.at("is")) {
            Token op = self.advance()
            String ty = self.parseType()
            AstNode n = self.node("Cast", ty, op)
            if op.text == "is" {
                n.kind = "Is"
            }
            n.add(left)
            left = n
        }
        return left
    }

    Bool hasCall(AstNode n) {
        if n.kind == "Call" || n.kind == "MethodCall" {
            return true
        }
        if n.kind == "Member" && n.kids.length() > 0 {
            return self.hasCall(n.kids.get(0))
        }
        return false
    }

    String memberPath(AstNode n) {
        if n.kind == "Name" {
            return n.text
        }
        if n.kind == "Member" && n.kids.length() > 0 {
            return self.memberPath(n.kids.get(0)) + "." + n.text
        }
        return n.text
    }

    String quoted(String s) {
        return "\"" + s + "\""
    }

    AstNode parseInterpolation(Token t) {
        String raw = t.text
        if raw.length() >= 2 && raw.substring(0, 1) == "\"" && raw.substring(raw.length() - 1, 1) == "\"" {
            raw = raw.substring(1, raw.length() - 2)
        }
        AstNode result = new AstNode("String", self.quoted(""), t.line, t.col)
        String seg = ""
        Int i = 0
        while i < raw.length() {
            String c = raw.substring(i, 1)
            if c == "{" {
                if seg != "" {
                    AstNode lit = new AstNode("String", self.quoted(seg), t.line, t.col)
                    AstNode bin = new AstNode("Binary", "+", t.line, t.col)
                    bin.add(result)
                    bin.add(lit)
                    result = bin
                    seg = ""
                }
                Int depth = 1
                Int j = i + 1
                while j < raw.length() && depth > 0 {
                    String d = raw.substring(j, 1)
                    if d == "{" {
                        depth = depth + 1
                    } else if d == "}" {
                        depth = depth - 1
                    }
                    if depth > 0 {
                        j = j + 1
                    }
                }
                if j < raw.length() {
                    String exprText = raw.substring(i + 1, j - i - 1)
                    Parser ep = new Parser(lex(exprText))
                    AstNode ex = ep.parseExpr()
                    AstNode strCall = new AstNode("Call", "str", t.line, t.col)
                    strCall.add(ex)
                    AstNode bin = new AstNode("Binary", "+", t.line, t.col)
                    bin.add(result)
                    bin.add(strCall)
                    result = bin
                    i = j
                }
            } else {
                seg = seg + c
            }
            i = i + 1
        }
        if seg != "" {
            AstNode lit = new AstNode("String", self.quoted(seg), t.line, t.col)
            AstNode bin = new AstNode("Binary", "+", t.line, t.col)
            bin.add(result)
            bin.add(lit)
            result = bin
        }
        return result
    }

    Bool looksLikeLambda() {
        if !self.at("(") {
            return false
        }
        Int depth = 0
        Int j = 0
        while true {
            Token t = self.look(j)
            if t.kind == "eof" {
                return false
            }
            if t.text == "(" {
                depth = depth + 1
            } else if t.text == ")" {
                depth = depth - 1
                if depth == 0 {
                    return self.look(j + 1).text == "->"
                }
            }
            j = j + 1
        }
        return false
    }

    AstNode parseLambda() {
        Token t = self.peek()
        AstNode n = self.node("Lambda", "", t)
        self.expect("(")
        if !self.at(")") {
            while !self.hasError() {
                if self.at("final") {
                    self.advance()
                }
                String pt = self.parseType()
                if !self.kind("ident") {
                    self.fail("expected lambda parameter name")
                    break
                }
                Token pn = self.advance()
                n.add(new AstNode("Param", pt + " " + pn.text, pn.line, pn.col))
                if !self.eat(",") {
                    break
                }
            }
        }
        self.expect(")")
        self.expect("->")
        if self.at("{") {
            n.add(self.parseBlock())
        } else {
            AstNode b = self.node("Block", "", self.peek())
            AstNode r = self.node("Return", "", self.peek())
            r.add(self.parseExpr())
            b.add(r)
            n.add(b)
        }
        return n
    }

    AstNode parsePrimary() {
        Token t = self.peek()
        if self.kind("int") {
            self.advance()
            return self.node("Int", t.text, t)
        }
        if self.kind("double") {
            self.advance()
            return self.node("Double", t.text, t)
        }
        if self.kind("string") {
            self.advance()
            AstNode n = self.node("String", t.text, t)
            while self.at(".") && (self.look(1).kind == "ident" || self.look(1).kind == "kw") {
                self.advance()
                Token m = self.advance()
                AstNode mc = self.node("MethodCall", m.text, t)
                mc.add(n)
                if self.eat("(") {
                    if !self.at(")") {
                        while !self.hasError() {
                            mc.add(self.parseExpr())
                            if !self.eat(",") {
                                break
                            }
                        }
                    }
                    self.expect(")")
                }
                n = mc
            }
            return n
        }
        if self.kind("interp") {
            self.advance()
            return self.parseInterpolation(t)
        }
        if self.kind("kw") && t.text == "null" {
            self.advance()
            return self.node("Null", "", t)
        }
        if self.kind("char") {
            self.advance()
            return self.node("Char", t.text, t)
        }
        if self.kind("kw") && (t.text == "true" || t.text == "false") {
            self.advance()
            return self.node("Bool", t.text, t)
        }
        if self.at("(") && self.looksLikeLambda() {
            return self.parseLambda()
        }
        if self.at("(") {
            self.advance()
            AstNode n = self.parseExpr()
            self.expect(")")
            return n
        }
        if self.at("-") || self.at("!") {
            Token op = self.advance()
            AstNode n = self.node("Unary", op.text, op)
            n.add(self.parsePrimary())
            return n
        }
        if self.kind("kw") && t.text == "try" {
            self.advance()
            AstNode n = self.node("Try", "", t)
            n.add(self.parseExpr())
            return n
        }
        if self.at("[") {
            self.advance()
            Token after = self.look(0)
            Token colon = self.look(1)
            if after.text == ":" && colon.text == "]" {
                self.advance()
                self.advance()
                return self.node("MapLit", "", t)
            }
            if after.kind == "string" && colon.text == ":" {
                AstNode m = self.node("MapLit", "", t)
                while !self.hasError() {
                    Token k = self.peek()
                    if k.kind != "string" {
                        self.fail("map key must be String")
                        break
                    }
                    self.advance()
                    m.add(self.node("String", k.text, k))
                    self.expect(":")
                    m.add(self.parseExpr())
                    if !self.eat(",") {
                        break
                    }
                }
                self.expect("]")
                return m
            }
            AstNode n = self.node("ArrayLit", "", t)
            if !self.at("]") {
                while !self.hasError() {
                    n.add(self.parseExpr())
                    if !self.eat(",") {
                        break
                    }
                }
            }
            self.expect("]")
            return n
        }
        if self.kind("kw") && t.text == "new" {
            self.advance()
            String ty = self.parseNewType()
            AstNode n = self.node("New", ty, t)
            if self.eat("(") {
                if !self.at(")") {
                    while !self.hasError() {
                        n.add(self.parseExpr())
                        if !self.eat(",") {
                            break
                        }
                    }
                }
                self.expect(")")
            }
            return n
        }
        if self.kind("ident") || self.kind("kw") {
            self.advance()
            AstNode n = self.node("Name", t.text, t)
            while !self.hasError() {
                if self.at("<") && self.looksLikeTypeArgs() {
                    Token gt = self.peek()
                    String targs = self.parseTypeArgsText()
                    AstNode call = self.node("GenericCall", n.text, t)
                    call.add(self.node("TypeArgs", targs, gt))
                    self.expect("(")
                    if !self.at(")") {
                        while !self.hasError() {
                            call.add(self.parseExpr())
                            if !self.eat(",") {
                                break
                            }
                        }
                    }
                    self.expect(")")
                    n = call
                } else if self.eat("(") {
                    if n.kind == "Member" {
                        AstNode recv = n.kids.get(0)
                        if self.hasCall(recv) {
                            AstNode call = self.node("MethodCall", n.text, t)
                            call.add(recv)
                            if !self.at(")") {
                                while !self.hasError() {
                                    call.add(self.parseExpr())
                                    if !self.eat(",") {
                                        break
                                    }
                                }
                            }
                            self.expect(")")
                            n = call
                        } else {
                            String cname = self.memberPath(n)
                            AstNode call = self.node("Call", cname, t)
                            if !self.at(")") {
                                while !self.hasError() {
                                    call.add(self.parseExpr())
                                    if !self.eat(",") {
                                        break
                                    }
                                }
                            }
                            self.expect(")")
                            n = call
                        }
                    } else {
                        AstNode call = self.node("Call", t.text, t)
                        if !self.at(")") {
                            while !self.hasError() {
                                call.add(self.parseExpr())
                                if !self.eat(",") {
                                    break
                                }
                            }
                        }
                        self.expect(")")
                        n = call
                    }
                } else if self.eat(".") {
                    if !self.kind("ident") && !self.kind("kw") {
                        self.fail("expected member name")
                        return n
                    }
                    Token m = self.advance()
                    AstNode mem = self.node("Member", m.text, t)
                    mem.add(n)
                    n = mem
                } else if self.eat("[") {
                    AstNode idx = self.node("Index", "", t)
                    idx.add(n)
                    idx.add(self.parseExpr())
                    self.expect("]")
                    n = idx
                } else {
                    break
                }
            }
            return n
        }
        self.fail("expected expression")
        return self.node("error", t.text, t)
    }
}


class Mono {
    final AstNode program

    Mono(AstNode p) {
        self.program = p
    }

    Bool hasTypeParams(AstNode n) {
        Int i = 0
        while i < n.kids.length() {
            if n.kids.get(i).kind == "TypeParams" {
                return true
            }
            i = i + 1
        }
        return false
    }

    List<String> typeParams(AstNode fn) {
        List<String> res = []
        Int i = 0
        while i < fn.kids.length() {
            AstNode k = fn.kids.get(i)
            if k.kind == "TypeParams" {
                Int j = 0
                while j < k.kids.length() {
                    if k.kids.get(j).kind == "TypeParam" {
                        res.push(k.kids.get(j).text)
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return res
    }

    Bool identChar(String c) {
        String alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz_"
        return alphabet.indexOf(c) >= 0
    }

    String subst(String text, String from, String to) {
        String res = ""
        Int i = 0
        while i < text.length() {
            if i + from.length() <= text.length() && text.substring(i, from.length()) == from {
                Bool leftOk = true
                Bool rightOk = true
                if i > 0 {
                    String ch = text.substring(i - 1, 1)
                    if self.identChar(ch) {
                        leftOk = false
                    }
                }
                if i + from.length() < text.length() {
                    String ch = text.substring(i + from.length(), 1)
                    if self.identChar(ch) {
                        rightOk = false
                    }
                }
                if leftOk && rightOk {
                    res = res + to
                    i = i + from.length()
                } else {
                    res = res + text.substring(i, 1)
                    i = i + 1
                }
            } else {
                res = res + text.substring(i, 1)
                i = i + 1
            }
        }
        return res
    }

    String substAll(String text, List<String> names, List<String> args) {
        String res = text
        Int i = 0
        while i < names.length() {
            res = self.subst(res, names.get(i), args.get(i))
            i = i + 1
        }
        return res
    }

    String mangle(String ty) {
        String res = ""
        Int i = 0
        while i < ty.length() {
            String c = ty.substring(i, 1)
            if self.identChar(c) {
                res = res + c
            } else {
                res = res + "_"
            }
            i = i + 1
        }
        return res
    }

    Bool isDataEnum(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" && n.text == name {
                Int j = 0
                while j < n.kids.length() {
                    if n.kids.get(j).kind == "Data" {
                        return true
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return false
    }

    AstNode findClass(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if ((n.kind == "Class" || n.kind == "Struct") && n.text == name) ||
               (n.kind == "Enum" && n.text == name && self.isDataEnum(name)) {
                return n
            }
            i = i + 1
        }
        return new AstNode("None", "", 1, 1)
    }

    List<String> splitArgs(String text) {
        List<String> res = []
        String cur = ""
        Int depth = 0
        Int i = 0
        while i < text.length() {
            String c = text.substring(i, 1)
            if c == "<" {
                depth = depth + 1
            } else if c == ">" {
                depth = depth - 1
            }
            if c == "," && depth == 0 {
                res.push(cur)
                cur = ""
            } else {
                cur = cur + c
            }
            i = i + 1
        }
        if cur != "" {
            res.push(cur)
        }
        return res
    }

    String instantiateClass(String cname, List<String> args) {
        AstNode cls = self.findClass(cname)
        if cls.kind == "None" || !self.hasTypeParams(cls) {
            return cname
        }
        List<String> names = self.typeParams(cls)
        if names.length() != args.length() {
            return cname
        }
        String suffix = ""
        Int i = 0
        while i < args.length() {
            if suffix != "" {
                suffix = suffix + "_"
            }
            suffix = suffix + self.mangle(args.get(i))
            i = i + 1
        }
        String sname = cname + "__" + suffix
        if self.findClass(sname).kind != "None" {
            return sname
        }
        AstNode clone = new AstNode(cls.kind, sname, cls.line, cls.col)
        i = 0
        while i < cls.kids.length() {
            if cls.kids.get(i).kind != "TypeParams" {
                clone.add(self.cloneSubst(cls.kids.get(i), names, args))
            }
            i = i + 1
        }
        self.program.add(clone)
        return sname
    }

    String rewriteType(String ty) {
        String res = ty
        Bool changed = true
        while changed {
            changed = false
            Int ci = 0
            while ci < self.program.kids.length() {
                AstNode cls = self.program.kids.get(ci)
                if (cls.kind == "Class" || cls.kind == "Struct") && self.hasTypeParams(cls) && self.typeParams(cls).length() > 0 {
                    String needle = cls.text + "<"
                    Int p = res.indexOf(needle)
                    if p >= 0 {
                        Int depth = 0
                        Int j = p + cls.text.length()
                        Int end = -1
                        while j < res.length() {
                            String c = res.substring(j, 1)
                            if c == "<" {
                                depth = depth + 1
                            } else if c == ">" {
                                depth = depth - 1
                                if depth == 0 {
                                    end = j
                                    break
                                }
                            }
                            j = j + 1
                        }
                        if end > p {
                            String inner = res.substring(p + needle.length(), end - p - needle.length())
                            String sname = self.instantiateClass(cls.text, self.splitArgs(inner))
                            res = res.substring(0, p) + sname + res.substring(end + 1, res.length() - end - 1)
                            changed = true
                        }
                    }
                }
                ci = ci + 1
            }
        }
        return res
    }

    AstNode cloneSubst(AstNode n, List<String> names, List<String> args) {
        String text = n.text
        if n.kind == "Ret" || n.kind == "Param" || n.kind == "Field" || n.kind == "Local" ||
           n.kind == "New" || n.kind == "TypeArgs" || n.kind == "Base" || n.kind == "Implements" {
            text = self.substAll(text, names, args)
        }
        AstNode c = new AstNode(n.kind, text, n.line, n.col)
        Int i = 0
        while i < n.kids.length() {
            if n.kids.get(i).kind != "TypeParams" {
                c.add(self.cloneSubst(n.kids.get(i), names, args))
            }
            i = i + 1
        }
        return c
    }

    AstNode findGeneric(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" && n.text == name && self.hasTypeParams(n) {
                return n
            }
            i = i + 1
        }
        return new AstNode("None", "", 1, 1)
    }

    Bool hasFunc(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" && n.text == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    String specialize(AstNode fn, List<String> args) {
        List<String> names = self.typeParams(fn)
        if names.length() != args.length() {
            return ""
        }
        String suffix = ""
        Int i = 0
        while i < args.length() {
            if suffix != "" {
                suffix = suffix + "_"
            }
            suffix = suffix + self.mangle(args.get(i))
            i = i + 1
        }
        String sname = fn.text + "__" + suffix
        if self.hasFunc(sname) {
            return sname
        }
        AstNode clone = new AstNode("Func", sname, fn.line, fn.col)
        i = 0
        while i < fn.kids.length() {
            if fn.kids.get(i).kind != "TypeParams" {
                clone.add(self.cloneSubst(fn.kids.get(i), names, args))
            }
            i = i + 1
        }
        self.program.add(clone)
        return sname
    }

    String argType(AstNode n) {
        if n.kind == "Int" {
            return "Int"
        }
        if n.kind == "Double" {
            return "Double"
        }
        if n.kind == "String" {
            return "String"
        }
        if n.kind == "Null" {
            return "Null"
        }
        if n.kind == "Bool" {
            return "Bool"
        }
        if n.kind == "Char" {
            return "Char"
        }
        if n.kind == "New" {
            return n.text
        }
        return "Any"
    }

    String typeArgsFor(AstNode call) {
        if call.kind == "GenericCall" && call.kids.length() > 0 {
            return call.kids.get(0).text
        }
        AstNode fn = self.findGeneric(call.text)
        if fn.kind != "Func" {
            return ""
        }
        List<String> names = self.typeParams(fn)
        if names.length() == 0 {
            return ""
        }
        List<String> actual = []
        Int ai = 0
        while ai < call.kids.length() {
            actual.push(self.argType(call.kids.get(ai)))
            ai = ai + 1
        }
        List<String> inferred = []
        Int ni = 0
        while ni < names.length() {
            inferred.push("")
            ni = ni + 1
        }
        Int pi = 0
        Int argi = 0
        while pi < fn.kids.length() {
            AstNode p = fn.kids.get(pi)
            if p.kind == "Param" {
                List<String> pp = p.text.split(" ")
                if pp.length() >= 1 && argi < actual.length() {
                    String pty = pp.get(0)
                    Int ii = 0
                    while ii < names.length() {
                        if pty == names.get(ii) && actual.get(argi) != "Any" {
                            if inferred.get(ii) == "" {
                                inferred.set(ii, actual.get(argi))
                            } else if inferred.get(ii) != actual.get(argi) {
                                return ""
                            }
                        }
                        ii = ii + 1
                    }
                }
                argi = argi + 1
            }
            pi = pi + 1
        }
        String res = ""
        Int i = 0
        while i < inferred.length() {
            if inferred.get(i) == "" {
                return ""
            }
            if res != "" {
                res = res + ","
            }
            res = res + inferred.get(i)
            i = i + 1
        }
        return res
    }

    AstNode walk(AstNode n) {
        if n.kind == "Ret" || n.kind == "Param" || n.kind == "Field" || n.kind == "Local" ||
           n.kind == "New" || n.kind == "TypeArgs" || n.kind == "Base" || n.kind == "Implements" {
            n.text = self.rewriteType(n.text)
        }
        if n.kind == "GenericCall" || (n.kind == "Call" && self.findGeneric(n.text).kind == "Func") {
            AstNode fn = self.findGeneric(n.text)
            if fn.kind == "Func" {
                String tas = self.typeArgsFor(n)
                if tas != "" {
                    List<String> args = tas.split(",")
                    String sname = self.specialize(fn, args)
                    if sname != "" {
                        n.kind = "Call"
                        n.text = sname
                        if n.kids.length() > 0 && n.kids.get(0).kind == "TypeArgs" {
                            n.kids.remove(0)
                        }
                    }
                }
            }
        }
        Int i = 0
        while i < n.kids.length() {
            n.setKid(i, self.walk(n.kids.get(i)))
            i = i + 1
        }
        return n
    }

    AstNode cloneAst(AstNode n) {
        AstNode c = new AstNode(n.kind, n.text, n.line, n.col)
        Int i = 0
        while i < n.kids.length() {
            c.add(self.cloneAst(n.kids.get(i)))
            i = i + 1
        }
        return c
    }

    Bool hasMember(AstNode cls, AstNode member) {
        Int i = 0
        while i < cls.kids.length() {
            AstNode k = cls.kids.get(i)
            if k.kind == member.kind && k.text == member.text {
                return true
            }
            if k.kind == "Field" && member.kind == "Field" {
                List<String> a = k.text.split(" ")
                List<String> b = member.text.split(" ")
                if a.length() >= 2 && b.length() >= 2 && a.get(1) == b.get(1) {
                    return true
                }
            }
            i = i + 1
        }
        return false
    }

    Void flattenClass(AstNode cls) {
        String baseName = ""
        Int i = 0
        while i < cls.kids.length() {
            AstNode k = cls.kids.get(i)
            if k.kind == "Base" {
                baseName = k.text
            }
            i = i + 1
        }
        if baseName == "" {
            return
        }
        AstNode base = self.findClass(baseName)
        if base.kind == "None" {
            return
        }
        self.flattenClass(base)
        i = 0
        while i < base.kids.length() {
            AstNode k = base.kids.get(i)
            if (k.kind == "Field" || k.kind == "Method") && !self.hasMember(cls, k) {
                cls.add(self.cloneAst(k))
            }
            i = i + 1
        }
    }

    AstNode run() {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if (n.kind == "Class" || n.kind == "Struct") && !self.hasTypeParams(n) {
                self.flattenClass(n)
            }
            i = i + 1
        }
        i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" && !self.hasTypeParams(n) {
                self.program.setKid(i, self.walk(n))
            }
            if (n.kind == "Class" || n.kind == "Struct") && !self.hasTypeParams(n) {
                self.program.setKid(i, self.walk(n))
            }
            i = i + 1
        }
        return self.program
    }
}

class Checker {
    final String file
    final AstNode program
    final List<String> fnNames
    final List<String> fnRets
    final List<String> fnParams
    final List<String> vars
    final List<String> varTypes
    final List<String> classNames
    final List<String> enumNames
    final List<String> protocolNames
    final List<String> fieldOwners
    final List<String> fieldNames
    final List<String> fieldTypes
    final List<String> methodOwners
    final List<String> methodNames
    final List<String> methodRets
    final List<String> methodParams
    String error
    String errorCode
    Int errorLine
    Int errorCol
    String curRet
    String curClass
    String expectedLambda

    Checker(String file, AstNode program) {
        self.file = file
        self.program = program
        self.fnNames = []
        self.fnRets = []
        self.fnParams = []
        self.vars = []
        self.varTypes = []
        self.classNames = []
        self.enumNames = []
        self.protocolNames = []
        self.fieldOwners = []
        self.fieldNames = []
        self.fieldTypes = []
        self.methodOwners = []
        self.methodNames = []
        self.methodRets = []
        self.methodParams = []
        self.error = ""
        self.errorCode = ""
        self.errorLine = 1
        self.errorCol = 1
        self.curRet = "Unit"
    }

    Bool hasError() {
        return self.error != ""
    }

    Void fail(String code, String msg, AstNode n) {
        if self.error == "" {
            self.error = msg
            self.errorCode = code
            self.errorLine = n.line
            self.errorCol = n.col
        }
    }

    Bool isFunctionType(String ty) {
        Int p = ty.indexOf("(")
        return p > 0 && ty.length() > p + 1 && ty.substring(ty.length() - 1, 1) == ")"
    }

    String fnRetType(String ty) {
        Int p = ty.indexOf("(")
        if p > 0 {
            return ty.substring(0, p)
        }
        return "Any"
    }

    List<String> fnParams(String ty) {
        List<String> res = []
        Int p = ty.indexOf("(")
        if p <= 0 || ty.substring(ty.length() - 1, 1) != ")" {
            return res
        }
        String inner = ty.substring(p + 1, ty.length() - p - 2)
        if inner.trim() == "" {
            return res
        }
        List<String> raw = inner.split(",")
        Int i = 0
        while i < raw.length() {
            res.push(raw.get(i).trim())
            i = i + 1
        }
        return res
    }

    Bool knownType(String ty) {
        if ty.length() > 1 && ty.substring(ty.length() - 1, 1) == "?" {
            return self.knownType(ty.substring(0, ty.length() - 1))
        }
        if ty == "Bytes" {
            return true
        }
        if ty == "AtomicInt" || ty == "AtomicBool" {
            return true
        }
        if self.isFunctionType(ty) {
            return true
        }
        if ty == "Int" || ty == "String" || ty == "Bool" ||
            ty == "Unit" || ty == "Char" || ty == "Double" ||
            ty == "Long" || ty == "Int64" || ty == "Int32" || ty == "UInt16" || ty == "void" {
            return true
        }
        if self.isListType(ty) {
            return self.knownType(self.elementType(ty))
        }
        if self.isMapType(ty) {
            return self.knownType(self.mapKeyType(ty)) && self.knownType(self.mapValueType(ty))
        }
        if self.isResultType(ty) {
            return self.knownType(self.resultValueType(ty)) && self.knownType(self.resultErrorType(ty))
        }
        if self.isSetType(ty) {
            return self.knownType(self.setElement(ty))
        }
        Int i = 0
        while i < self.classNames.length() {
            if self.classNames.get(i) == ty {
                return true
            }
            i = i + 1
        }
        i = 0
        while i < self.enumNames.length() {
            if self.enumNames.get(i) == ty {
                return true
            }
            i = i + 1
        }
        i = 0
        while i < self.protocolNames.length() {
            if self.protocolNames.get(i) == ty {
                return true
            }
            i = i + 1
        }
        return false
    }

    Bool isListType(String ty) {
        return (ty.length() >= 2 && ty.substring(ty.length() - 2, 2) == "[]") ||
            (ty.length() > 6 && ty.substring(0, 5) == "List<")
    }

    Bool isMapType(String ty) {
        return ty.length() > 5 && ty.substring(0, 4) == "Map<"
    }

    Bool isSetType(String ty) {
        return ty.length() > 5 && ty.substring(0, 4) == "Set<"
    }

    String setElement(String ty) {
        if self.isSetType(ty) {
            return ty.substring(4, ty.length() - 5)
        }
        return "Any"
    }

    String mapInner(String ty) {
        if self.isMapType(ty) {
            return ty.substring(4, ty.length() - 5)
        }
        return ""
    }

    String mapKeyType(String ty) {
        String inner = self.mapInner(ty)
        List<String> parts = inner.split(",")
        if parts.length() >= 1 {
            return parts.get(0)
        }
        return "Any"
    }

    String mapValueType(String ty) {
        String inner = self.mapInner(ty)
        List<String> parts = inner.split(",")
        if parts.length() >= 2 {
            return parts.get(1)
        }
        return "Any"
    }

    String elementType(String ty) {
        if ty.length() >= 2 && ty.substring(ty.length() - 2, 2) == "[]" {
            return ty.substring(0, ty.length() - 2)
        }
        if ty.length() > 6 && ty.substring(0, 5) == "List<" {
            return ty.substring(5, ty.length() - 6)
        }
        return "Any"
    }

    Bool isResultType(String ty) {
        return ty.length() > 8 && ty.substring(0, 7) == "Result<"
    }

    String resultValueType(String ty) {
        String inner = ""
        if self.isResultType(ty) {
            inner = ty.substring(7, ty.length() - 8)
        }
        List<String> parts = inner.split(",")
        if parts.length() >= 1 {
            return parts.get(0)
        }
        return "Any"
    }

    String resultErrorType(String ty) {
        String inner = ""
        if self.isResultType(ty) {
            inner = ty.substring(7, ty.length() - 8)
        }
        List<String> parts = inner.split(",")
        if parts.length() >= 2 {
            return parts.get(1)
        }
        return "Any"
    }

    Bool sameType(String a, String b) {
        if a == b {
            return true
        }
        if b == "Null" && (a == "Any" || (a.length() > 1 && a.substring(a.length() - 1, 1) == "?")) {
            return true
        }
        if a == "Null" && (b == "Any" || (b.length() > 1 && b.substring(b.length() - 1, 1) == "?")) {
            return true
        }
        if self.isListType(a) && self.isListType(b) {
            return self.elementType(a) == self.elementType(b)
        }
        if (a == "Int" || a == "Int32" || a == "Int64" || a == "Long") &&
           (b == "Int" || b == "Int32" || b == "Int64" || b == "Long") {
            return true
        }
        return false
    }

    Bool classIsA(String actual, String target) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode c = self.program.kids.get(i)
            if (c.kind == "Class" || c.kind == "Struct") && c.text == actual {
                Int j = 0
                while j < c.kids.length() {
                    AstNode k = c.kids.get(j)
                    if k.kind == "Base" {
                        if k.text == target {
                            return true
                        }
                        return self.classIsA(k.text, target)
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return false
    }

    Bool isAssignable(String target, String actual) {
        if self.sameType(target, actual) {
            return true
        }
        if target == "Any" || actual == "Any" || target == "Error" || actual == "Error" {
            return true
        }
        if target.length() > 1 && target.substring(target.length() - 1, 1) == "?" {
            String base = target.substring(0, target.length() - 1)
            if actual == "Null" || self.isAssignable(base, actual) {
                return true
            }
        }
        Int ci = self.findClass(actual)
        if ci >= 0 {
            if self.classIsA(actual, target) {
                return true
            }
            Int i = 0
            while i < self.program.kids.length() {
                AstNode c = self.program.kids.get(i)
                if (c.kind == "Class" || c.kind == "Struct") && c.text == actual {
                    Int j = 0
                    while j < c.kids.length() {
                        AstNode k = c.kids.get(j)
                        if k.kind == "Implements" && k.text == target {
                            return true
                        }
                        j = j + 1
                    }
                }
                i = i + 1
            }
        }
        return false
    }

    Int findFn(String name) {
        Int i = 0
        while i < self.fnNames.length() {
            if self.fnNames.get(i) == name {
                return i
            }
            i = i + 1
        }
        return -1
    }

    Int findVar(String name) {
        Int i = self.vars.length() - 1
        while i >= 0 {
            if self.vars.get(i) == name {
                return i
            }
            i = i - 1
        }
        return -1
    }

    Int findClass(String name) {
        Int i = 0
        while i < self.classNames.length() {
            if self.classNames.get(i) == name {
                return i
            }
            i = i + 1
        }
        return -1
    }

    Int findField(String cls, String name) {
        Int i = 0
        while i < self.fieldNames.length() {
            if self.fieldOwners.get(i) == cls && self.fieldNames.get(i) == name {
                return i
            }
            i = i + 1
        }
        return -1
    }

    Int findMethod(String cls, String name) {
        Int i = 0
        while i < self.methodNames.length() {
            if self.methodOwners.get(i) == cls && self.methodNames.get(i) == name {
                return i
            }
            i = i + 1
        }
        return -1
    }

    String retOf(AstNode fn) {
        Int i = 0
        while i < fn.kids.length() {
            AstNode k = fn.kids.get(i)
            if k.kind == "Ret" {
                return k.text
            }
            i = i + 1
        }
        return "Unit"
    }

    String paramTypes(AstNode fn) {
        String b = ""
        Int i = 0
        while i < fn.kids.length() {
            AstNode k = fn.kids.get(i)
            if k.kind == "Param" {
                List<String> parts = k.text.split(" ")
                if parts.length() > 0 {
                    if b != "" {
                        b = b + ","
                    }
                    b = b + parts.get(0)
                }
            }
            i = i + 1
        }
        return b
    }

    Void collect() {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" {
                if hasTypeParams(n) {
                    i = i + 1
                    continue
                }
                Int old = self.findFn(n.text)
                if old >= 0 {
                    self.fail("SEM-002", "duplicate function: " + n.text, n)
                } else {
                    String rt = self.retOf(n)
                    self.fnNames.push(n.text)
                    self.fnRets.push(rt)
                    self.fnParams.push(self.paramTypes(n))
                }
            }
            if n.kind == "TopField" {
                List<String> parts = n.text.split(" ")
                if parts.length() >= 2 {
                    self.vars.push(parts.get(1))
                    self.varTypes.push(parts.get(0))
                }
            }
            if n.kind == "Enum" {
                self.enumNames.push(n.text)
                if self.isDataEnum(n.text) {
                    if self.findClass(n.text) < 0 {
                        self.classNames.push(n.text)
                    }
                    Int dj = 0
                    while dj < n.kids.length() {
                        AstNode dk = n.kids.get(dj)
                        if dk.kind == "Field" {
                            List<String> dparts = dk.text.split(" ")
                            if dparts.length() >= 2 {
                                self.fieldOwners.push(n.text)
                                self.fieldNames.push(dparts.get(1))
                                self.fieldTypes.push(dparts.get(0))
                            }
                        }
                        if dk.kind == "Method" {
                            self.methodOwners.push(n.text)
                            self.methodNames.push(dk.text)
                            self.methodRets.push(self.retOf(dk))
                            self.methodParams.push(self.paramTypes(dk))
                        }
                        dj = dj + 1
                    }
                }
            }
            if n.kind == "Protocol" {
                self.protocolNames.push(n.text)
            }
            if (n.kind == "Class" || n.kind == "Struct") && !hasTypeParams(n) {
                if self.findClass(n.text) >= 0 {
                    self.fail("SEM-002", "duplicate class: " + n.text, n)
                } else {
                    self.classNames.push(n.text)
                    Int j = 0
                    while j < n.kids.length() {
                        AstNode k = n.kids.get(j)
                        if k.kind == "Field" {
                            List<String> parts = k.text.split(" ")
                            if parts.length() >= 2 {
                                self.fieldOwners.push(n.text)
                                self.fieldNames.push(parts.get(1))
                                self.fieldTypes.push(parts.get(0))
                            }
                        }
                        if k.kind == "Method" {
                            Int dup = self.findMethod(n.text, k.text)
                            if dup >= 0 {
                                self.fail("SEM-002", "duplicate method: " + k.text, k)
                            } else {
                                self.methodOwners.push(n.text)
                                self.methodNames.push(k.text)
                                self.methodRets.push(self.retOf(k))
                                self.methodParams.push(self.paramTypes(k))
                            }
                        }
                        j = j + 1
                    }
                }
            }
            i = i + 1
        }
    }

    Void addVar(String ty, String name, AstNode where) {
        if self.findVar(name) >= 0 {
            self.fail("SEM-002", "duplicate variable: " + name, where)
            return
        }
        self.vars.push(name)
        self.varTypes.push(ty)
    }

    Void popTo(Int mark) {
        while self.vars.length() > mark {
            self.vars.remove(self.vars.length() - 1)
            self.varTypes.remove(self.varTypes.length() - 1)
        }
    }

    Bool isEmptyArray(AstNode n) {
        return n.kind == "ArrayLit" && n.kids.length() == 0
    }

    Void check() {
        self.collect()
        Int i = 0
        while i < self.program.kids.length() && !self.hasError() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" {
                self.checkFunc(n)
            }
            if ((n.kind == "Class" || n.kind == "Struct") && !hasTypeParams(n)) ||
               (n.kind == "Enum" && self.isDataEnum(n.text)) {
                self.checkClass(n)
            }
            i = i + 1
        }
    }

    Void checkClass(AstNode cls) {
        self.curClass = cls.text
        Int i = 0
        while i < cls.kids.length() && !self.hasError() {
            AstNode k = cls.kids.get(i)
            if k.kind == "Field" {
                List<String> parts = k.text.split(" ")
                if parts.length() >= 2 {
                    if !self.knownType(parts.get(0)) {
                        self.fail("SEM-005", "unknown field type: " + parts.get(0), k)
                    }
                    if k.kids.length() > 0 {
                        String it = self.typeOf(k.kids.get(0))
                        if it != "Error" && it != parts.get(0) && !(self.isEmptyArray(k.kids.get(0)) && self.isListType(parts.get(0))) {
                            self.fail("SEM-003", "field " + parts.get(1) + " expects " + parts.get(0) + ", got " + it, k)
                        }
                    }
                }
            }
            if k.kind == "Method" || k.kind == "Ctor" {
                self.checkFunc(k)
            }
            i = i + 1
        }
        self.curClass = ""
    }

    Void checkFunc(AstNode fn) {
        if fn.kind == "Ctor" {
            self.curRet = "Unit"
        } else if fn.kind == "Method" {
            self.curRet = self.retOf(fn)
        } else {
            Int idx = self.findFn(fn.text)
            if idx < 0 {
                return
            }
            self.curRet = self.fnRets.get(idx)
        }
        Int mark = self.vars.length()
        Int i = 0
        while i < fn.kids.length() && !self.hasError() {
            AstNode k = fn.kids.get(i)
            if k.kind == "Param" {
                List<String> parts = k.text.split(" ")
                if parts.length() < 2 {
                    self.fail("SEM-005", "malformed parameter", k)
                } else {
                    String ty = parts.get(0)
                    String name = parts.get(1)
                    if !self.knownType(ty) {
                        self.fail("SEM-005", "unknown type: " + ty, k)
                    } else {
                        self.addVar(ty, name, k)
                    }
                }
            } else if k.kind == "Block" {
                self.checkBlock(k)
            }
            i = i + 1
        }
        self.popTo(mark)
    }

    Void checkBlock(AstNode block) {
        Int mark = self.vars.length()
        Int i = 0
        while i < block.kids.length() && !self.hasError() {
            self.checkStmt(block.kids.get(i))
            i = i + 1
        }
        self.popTo(mark)
    }

    Void checkStmt(AstNode st) {
        if st.kind == "Break" || st.kind == "Continue" || st.kind == "Goto" {
            return
        }
        if st.kind == "Label" {
            if st.kids.length() > 0 {
                self.checkStmt(st.kids.get(0))
            }
            return
        }
        if st.kind == "Throw" {
            if st.kids.length() > 0 {
                self.typeOf(st.kids.get(0))
            }
            return
        }
        if st.kind == "Assign" {
            if st.kids.length() < 2 {
                self.fail("SEM-005", "malformed assignment", st)
                return
            }
            String lt = self.typeOf(st.kids.get(0))
            String rt = self.typeOf(st.kids.get(1))
            if lt != "Error" && rt != "Error" && !self.isAssignable(lt, rt) && !(self.isEmptyArray(st.kids.get(1)) && self.isListType(lt)) {
                self.fail("SEM-003", "assignment " + lt + " = " + rt, st)
            }
            return
        }
        if st.kind == "Defer" {
            if st.kids.length() > 0 {
                self.checkStmt(st.kids.get(0))
            }
            return
        }
        if st.kind == "ForIn" {
            if st.kids.length() < 2 {
                self.fail("SEM-005", "malformed for-in", st)
                return
            }
            String at = self.typeOf(st.kids.get(0))
            if at != "Error" && self.elementType(at) == "Any" {
                self.fail("SEM-003", "for-in expects array, got " + at, st)
                return
            }
            Int mark = self.vars.length()
            self.addVar(self.elementType(at), st.text, st)
            self.checkBlock(st.kids.get(1))
            self.popTo(mark)
            return
        }
        if st.kind == "Switch" {
            if st.kids.length() < 2 {
                self.fail("SEM-005", "malformed switch", st)
                return
            }
            String vt = self.typeOf(st.kids.get(0))
            if vt == "Error" {
                return
            }
            if vt == "Double" || self.isResultType(vt) {
                self.fail("SEM-003", "unsupported switch value type: " + vt, st)
                return
            }
            Int si = 1
            Bool hasDefault = false
            List<String> covered = []
            while si < st.kids.length() && !self.hasError() {
                AstNode clause = st.kids.get(si)
                if clause.kind == "Case" {
                    if clause.kids.length() < 2 {
                        self.fail("SEM-005", "malformed case", clause)
                        return
                    }
                    String ct = self.typeOf(clause.kids.get(0))
                    if ct != "Error" && !self.sameType(vt, ct) {
                        self.fail("SEM-003", "case type " + ct + " does not match switch " + vt, clause)
                        return
                    }
                    String item = self.enumCaseItem(clause.kids.get(0), vt)
                    if item != "" {
                        covered.push(item)
                    }
                    self.checkBlock(clause.kids.get(1))
                } else if clause.kind == "Default" {
                    hasDefault = true
                    if clause.kids.length() > 0 {
                        self.checkBlock(clause.kids.get(0))
                    }
                }
                si = si + 1
            }
            if !hasDefault && vt != "Error" {
                List<String> all = self.enumItems(vt)
                if all.length() > 0 {
                    Int ei = 0
                    while ei < all.length() {
                        Bool found = false
                        Int ci = 0
                        while ci < covered.length() {
                            if covered.get(ci) == all.get(ei) {
                                found = true
                            }
                            ci = ci + 1
                        }
                        if !found {
                            self.fail("SEM-003", "non-exhaustive enum switch: missing " + all.get(ei), st)
                            return
                        }
                        ei = ei + 1
                    }
                }
            }
            return
        }
        if st.kind == "ForRange" {
            if st.kids.length() < 3 {
                self.fail("SEM-005", "malformed for-range", st)
                return
            }
            String a = self.typeOf(st.kids.get(0))
            String b = self.typeOf(st.kids.get(1))
            if a != "Error" && a != "Int" {
                self.fail("SEM-003", "for-range lower bound must be Int, got " + a, st)
                return
            }
            if b != "Error" && b != "Int" {
                self.fail("SEM-003", "for-range upper bound must be Int, got " + b, st)
                return
            }
            Int mark = self.vars.length()
            Int sp = st.text.indexOf(" ")
            self.addVar("Int", st.text.substring(sp + 1, st.text.length() - sp - 1), st)
            self.checkBlock(st.kids.get(2))
            self.popTo(mark)
            return
        }
        if st.kind == "DoWhile" {
            if st.kids.length() < 2 {
                self.fail("SEM-005", "malformed do-while", st)
                return
            }
            self.checkBlock(st.kids.get(0))
            String c = self.typeOf(st.kids.get(1))
            if c != "Error" && c != "Bool" {
                self.fail("SEM-003", "do-while condition must be Bool, got " + c, st)
            }
            return
        }
        if st.kind == "Local" {
            List<String> parts = st.text.split(" ")
            if parts.length() < 2 {
                self.fail("SEM-005", "malformed local declaration", st)
                return
            }
            String ty = parts.get(0)
            String name = parts.get(1)
            if !self.knownType(ty) {
                self.fail("SEM-005", "unknown type: " + ty, st)
                return
            }
            self.addVar(ty, name, st)
            if st.kids.length() > 0 {
                String it = ""
                if st.kids.get(0).kind == "Lambda" {
                    String oldExp = self.expectedLambda
                    self.expectedLambda = ty
                    it = self.typeOf(st.kids.get(0))
                    self.expectedLambda = oldExp
                } else {
                    it = self.typeOf(st.kids.get(0))
                }
                Bool setLit = self.isSetType(ty) && st.kids.get(0).kind == "ArrayLit" && self.elementType(it) == "Int"
                if it != "Error" && !self.isAssignable(ty, it) && !(self.isEmptyArray(st.kids.get(0)) && self.isListType(ty)) && !setLit {
                    self.fail("SEM-003", "cannot initialize " + ty + " with " + it, st)
                }
            }
            return
        }
        if st.kind == "Return" {
            if st.kids.length() == 0 {
                if self.curRet != "Unit" && self.curRet != "Void" && self.curRet != "void" {
                    self.fail("SEM-003", "return value required, got Unit", st)
                }
            } else {
                String t = self.argType(st.kids.get(0), self.curRet)
                if t != "Error" && !self.isAssignable(self.curRet, t) {
                    self.fail("SEM-003", "return type " + self.curRet + ", got " + t, st)
                }
            }
            return
        }
        if st.kind == "ExprStmt" {
            if st.kids.length() > 0 {
                self.typeOf(st.kids.get(0))
            }
            return
        }
        if st.kind == "If" {
            if st.kids.length() >= 1 {
                String c = self.typeOf(st.kids.get(0))
                if c != "Error" && c != "Bool" {
                    self.fail("SEM-003", "if condition must be Bool, got " + c, st)
                }
            }
            if st.kids.length() >= 2 {
                self.checkBlock(st.kids.get(1))
            }
            if st.kids.length() >= 3 {
                self.checkBlock(st.kids.get(2))
            }
            return
        }
        if st.kind == "While" {
            if st.kids.length() >= 1 {
                String c = self.typeOf(st.kids.get(0))
                if c != "Error" && c != "Bool" {
                    self.fail("SEM-003", "while condition must be Bool, got " + c, st)
                }
            }
            if st.kids.length() >= 2 {
                self.checkBlock(st.kids.get(1))
            }
            return
        }
        if st.kind == "Block" {
            self.checkBlock(st)
        }
    }

    Bool isClass(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if (n.kind == "Class" || n.kind == "Struct") && n.text == name {
                return true
            }
            if n.kind == "Enum" && n.text == name {
                Int j = 0
                while j < n.kids.length() {
                    if n.kids.get(j).kind == "Data" {
                        return true
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return false
    }

    Bool isDataEnum(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" && n.text == name {
                Int j = 0
                while j < n.kids.length() {
                    if n.kids.get(j).kind == "Data" {
                        return true
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return false
    }

    String protocolRet(String pname, String mname) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode p = self.program.kids.get(i)
            if p.kind == "Protocol" && p.text == pname {
                Int j = 0
                while j < p.kids.length() {
                    AstNode sig = p.kids.get(j)
                    if sig.kind == "Sig" && sig.text == mname {
                        Int k = 0
                        while k < sig.kids.length() {
                            if sig.kids.get(k).kind == "Ret" {
                                return sig.kids.get(k).text
                            }
                            k = k + 1
                        }
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return "Any"
    }

    String protocolParams(String pname, String mname) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode p = self.program.kids.get(i)
            if p.kind == "Protocol" && p.text == pname {
                Int j = 0
                while j < p.kids.length() {
                    AstNode sig = p.kids.get(j)
                    if sig.kind == "Sig" && sig.text == mname {
                        String res = ""
                        Int k = 0
                        while k < sig.kids.length() {
                            AstNode q = sig.kids.get(k)
                            if q.kind == "Param" {
                                List<String> ps = q.text.split(" ")
                                if ps.length() > 0 {
                                    if res != "" {
                                        res = res + ","
                                    }
                                    res = res + ps.get(0)
                                }
                            }
                            k = k + 1
                        }
                        return res
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return ""
    }

    Bool isProtocolName(String name) {
        Int i = 0
        while i < self.protocolNames.length() {
            if self.protocolNames.get(i) == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    List<String> enumItems(String name) {
        List<String> res = []
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" && n.text == name {
                Int j = 0
                while j < n.kids.length() {
                    AstNode it = n.kids.get(j)
                    if it.kind == "EnumItem" {
                        res.push(it.text)
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return res
    }

    String enumCaseItem(AstNode n, String enumName) {
        if n.kind != "Member" || n.kids.length() == 0 {
            return ""
        }
        if self.typeOf(n) != enumName {
            return ""
        }
        return n.text
    }

    AstNode classNode(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if ((n.kind == "Class" || n.kind == "Struct") && n.text == name) ||
               (n.kind == "Enum" && n.text == name && self.isDataEnum(name)) {
                return n
            }
            i = i + 1
        }
        return new AstNode("error", name, 1, 1)
    }

    String curFieldType(String fname) {
        if self.curClass == "" {
            return "Any"
        }
        Int fi = self.findField(self.curClass, fname)
        if fi >= 0 {
            return self.fieldTypes.get(fi)
        }
        return "Any"
    }

    String pathType(String path) {
        Int dot = path.indexOf(".")
        if dot < 0 {
            if path == "self" {
                return self.curClass
            }
            if path == "Bytes" {
                return "Bytes"
            }
            if self.findClass(path) >= 0 {
                return path
            }
            Int vi = self.findVar(path)
            if vi >= 0 {
                return self.varTypes.get(vi)
            }
            String ft = self.curFieldType(path)
            if ft != "Any" {
                return ft
            }
            return "Any"
        }
        String head = path.substring(0, dot)
        String rest = path.substring(dot + 1, path.length() - dot - 1)
        String bt = self.pathType(head)
        while bt != "Any" && rest.length() > 0 {
            Int d = rest.indexOf(".")
            String seg = rest
            if d >= 0 {
                seg = rest.substring(0, d)
                rest = rest.substring(d + 1, rest.length() - d - 1)
            } else {
                rest = ""
            }
            bt = self.fieldType(bt, seg)
        }
        return bt
    }


    String fieldType(String cls, String fname) {
        AstNode c = self.classNode(cls)
        Int i = 0
        while i < c.kids.length() {
            AstNode k = c.kids.get(i)
            if k.kind == "Field" {
                List<String> parts = k.text.split(" ")
                if parts.length() >= 2 && parts.get(1) == fname {
                    return parts.get(0)
                }
            }
            i = i + 1
        }
        return "Any"
    }

    Bool isStaticMethod(String cls, String mname) {
        AstNode c = self.classNode(cls)
        Int i = 0
        while i < c.kids.length() {
            AstNode k = c.kids.get(i)
            if k.kind == "Method" && k.text == mname {
                Int j = 0
                while j < k.kids.length() {
                    if k.kids.get(j).kind == "Static" {
                        return true
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return false
    }

    Bool methodStatic(AstNode m) {
        Int i = 0
        while i < m.kids.length() {
            if m.kids.get(i).kind == "Static" {
                return true
            }
            i = i + 1
        }
        return false
    }

    String methodRet(String cls, String mname) {
        AstNode c = self.classNode(cls)
        Int i = 0
        while i < c.kids.length() {
            AstNode k = c.kids.get(i)
            if k.kind == "Method" && k.text == mname {
                String r = self.retOf(k)
                return r
            }
            i = i + 1
        }
        return "Any"
    }

    Bool isGenericResult(String ty) {
        return self.isResult(ty) && ty != "Result<Int,String>"
    }

    String resultInitField(String ty, String val) {
        String vt = self.resultValue(ty)
        if vt == "Int" || vt == "Int32" || vt == "Int64" || vt == "Long" || vt == "Bool" || vt == "Char" {
            return ".i = (int64_t)(" + val + ")"
        }
        if vt == "Double" {
            return ".d = (double)(" + val + ")"
        }
        if vt == "String" {
            return ".s = (rt_string *)(" + val + ")"
        }
        return ".p = (void *)(" + val + ")"
    }

    String resultValueExpr(String ty, String bv) {
        String vt = self.resultValue(ty)
        if vt == "Int" || vt == "Int32" || vt == "Int64" || vt == "Long" || vt == "Bool" || vt == "Char" {
            return "(" + bv + ").i"
        }
        if vt == "Double" {
            return "(" + bv + ").d"
        }
        if vt == "String" {
            return "(" + bv + ").s"
        }
        return "(" + bv + ").p"
    }

    Bool isResult(String ty) {
        return ty.length() > 8 && ty.substring(0, 7) == "Result<"
    }

    String resultValue(String ty) {
        String inner = ty.substring(7, ty.length() - 8)
        List<String> parts = inner.split(",")
        if parts.length() >= 1 {
            return parts.get(0)
        }
        return "Any"
    }

    String typeOf(AstNode n) {
        if n.kind == "Int" {
            return "Int"
        }
        if n.kind == "Double" {
            return "Double"
        }
        if n.kind == "String" {
            return "String"
        }
        if n.kind == "Null" {
            return "Null"
        }
        if n.kind == "Char" {
            return "Char"
        }
        if n.kind == "Bool" {
            return "Bool"
        }
        if n.kind == "Ternary" {
            if n.kids.length() < 3 {
                return "Any"
            }
            return self.typeOf(n.kids.get(1))
        }
        if n.kind == "Cast" {
            return n.text
        }
        if n.kind == "Is" {
            return "Bool"
        }
        if n.kind == "Unary" {
            if n.kids.length() == 0 {
                return "Any"
            }
            if n.text == "!" {
                return "Bool"
            }
            return self.typeOf(n.kids.get(0))
        }
        if n.kind == "Try" {
            if n.kids.length() == 0 {
                return "Any"
            }
            String ct = self.typeOf(n.kids.get(0))
            return self.resultValueType(ct)
        }
        if n.kind == "ArrayLit" {
            if n.kids.length() == 0 {
                return "Int[]"
            }
            return self.typeOf(n.kids.get(0)) + "[]"
        }
        if n.kind == "MapLit" {
            if n.kids.length() >= 2 {
                return "Map<" + self.typeOf(n.kids.get(0)) + "," + self.typeOf(n.kids.get(1)) + ">"
            }
            return "Map<String,Int>"
        }
        if n.kind == "Index" {
            if n.kids.length() < 2 {
                return "Any"
            }
            String bt = self.typeOf(n.kids.get(0))
            if bt == "Error" {
                return "Error"
            }
            if self.isMapType(bt) {
                return self.mapValueType(bt)
            }
            return self.elementType(bt)
        }
        if n.kind == "Lambda" {
            String ft = self.expectedLambda
            if ft == "" {
                return "Any"
            }
            Int mark = self.vars.length()
            Int i = 0
            while i < n.kids.length() {
                AstNode p = n.kids.get(i)
                if p.kind == "Param" {
                    List<String> pp = p.text.split(" ")
                    if pp.length() >= 2 {
                        self.addVar(pp.get(0), pp.get(1), p)
                    }
                }
                i = i + 1
            }
            String oldRet = self.curRet
            self.curRet = self.fnRetType(ft)
            i = 0
            while i < n.kids.length() {
                if n.kids.get(i).kind == "Block" {
                    self.checkBlock(n.kids.get(i))
                }
                i = i + 1
            }
            self.curRet = oldRet
            self.popTo(mark)
            return ft
        }
        if n.kind == "New" {
            if !self.knownType(n.text) {
                self.fail("SEM-005", "unknown class: " + n.text, n)
                return "Error"
            }
            if self.isDataEnum(n.text) {
                self.fail("SEM-005", "new is not allowed for data enum: " + n.text, n)
                return "Error"
            }
            return n.text
        }
        if n.kind == "Name" {
            if n.text == "self" && self.curClass != "" {
                return self.curClass
            }
            Int eni = 0
            while eni < self.enumNames.length() {
                if self.enumNames.get(eni) == n.text {
                    return n.text
                }
                eni = eni + 1
            }
            Int idx = self.findVar(n.text)
            if idx < 0 {
                String ft = self.curFieldType(n.text)
                if ft != "Any" {
                    return ft
                }
                self.fail("SEM-001", "undefined symbol: " + n.text, n)
                return "Error"
            }
            return self.varTypes.get(idx)
        }
        if n.kind == "Binary" {
            String lt = self.typeOf(n.kids.get(0))
            String rt = self.typeOf(n.kids.get(1))
            if lt == "Error" || rt == "Error" {
                return "Error"
            }
            if n.text == "==" || n.text == "!=" || n.text == "<" ||
                n.text == "<=" || n.text == ">" || n.text == ">=" ||
                n.text == "&&" || n.text == "||" {
                return "Bool"
            }
            if n.text == "+" && lt == "String" && rt == "String" {
                return "String"
            }
            if (lt == "Double" || rt == "Double") && n.text != "%" {
                if (lt == "Double" || lt == "Int") && (rt == "Double" || rt == "Int") {
                    return "Double"
                }
            }
            if n.text == "&" || n.text == "|" || n.text == "^" || n.text == "<<" || n.text == ">>" {
                if lt != "Int" || rt != "Int" {
                    self.fail("SEM-003", "operator " + n.text + " needs Int, got " + lt + "/" + rt, n)
                    return "Error"
                }
                return "Int"
            }
            if (lt == "Int64" || lt == "Int32" || lt == "Long") && (rt == "Int" || rt == "Int32" || rt == "Int64" || rt == "Long") {
                return lt
            }
            if (rt == "Int64" || rt == "Int32" || rt == "Long") && (lt == "Int" || lt == "Int32" || lt == "Int64" || lt == "Long") {
                return rt
            }
            if lt != "Int" || rt != "Int" {
                self.fail("SEM-003", "operator " + n.text + " needs Int, got " + lt + "/" + rt, n)
                return "Error"
            }
            return "Int"
        }
        if n.kind == "MethodCall" {
            return self.checkMethodCall(n)
        }
        if n.kind == "Call" {
            return self.checkCall(n)
        }
        if n.kind == "Member" {
            if n.kids.length() == 0 {
                return "Any"
            }
            String bt = self.typeOf(n.kids.get(0))
            if bt == "Error" {
                return "Error"
            }
            Int fi = self.findField(bt, n.text)
            if fi >= 0 {
                return self.fieldTypes.get(fi)
            }
            Int ei = 0
            while ei < self.enumNames.length() {
                if self.enumNames.get(ei) == bt {
                    return bt
                }
                ei = ei + 1
            }
            return "Any"
        }
        self.fail("SEM-001", "unsupported expression: " + n.kind, n)
        return "Error"
    }

    String checkMethodCall(AstNode n) {
        if n.kids.length() < 1 {
            return "Error"
        }
        String bt = self.typeOf(n.kids.get(0))
        if bt == "Any" || bt == "Error" {
            return bt
        }
        String mth = n.text
        Int argc = n.kids.length() - 1
        if bt == "AtomicInt" {
            if mth == "load" { return "Int" }
            if mth == "store" {
                if argc != 1 { self.fail("SEM-004", "AtomicInt.store expects 1 argument", n) }
                return "Unit"
            }
            if mth == "cas" || mth == "compareExchange" { return "Bool" }
            self.fail("SEM-001", "undefined method: AtomicInt." + mth, n)
            return "Error"
        }
        if bt == "AtomicBool" {
            if mth == "load" { return "Bool" }
            if mth == "store" {
                if argc != 1 { self.fail("SEM-004", "AtomicBool.store expects 1 argument", n) }
                return "Unit"
            }
            if mth == "cas" || mth == "compareExchange" { return "Bool" }
            self.fail("SEM-001", "undefined method: AtomicBool." + mth, n)
            return "Error"
        }
        if bt == "Bytes" {
            if mth == "length" || mth == "get" {
                return "Int"
            }
            if mth == "slice" {
                return "Bytes"
            }
            if mth == "toString" {
                return "String"
            }
            if mth == "set" || mth == "append" || mth == "push" {
                return "Unit"
            }
        }
        if bt == "Bytes" {
            if mth == "length" || mth == "get" {
                return "Int"
            }
            if mth == "slice" {
                return "Bytes"
            }
            if mth == "toString" {
                return "String"
            }
            if mth == "set" || mth == "append" || mth == "push" {
                return "Unit"
            }
        }
        if bt == "String" {
            if mth == "length" || mth == "indexOf" || mth == "indexOfByte" || mth == "get" {
                return "Int"
            }
            if mth == "substring" || mth == "charAt" {
                return "String"
            }
            if mth == "trim" || mth == "replace" || mth == "toUpper" || mth == "toLower" {
                return "String"
            }
            if mth == "startsWith" || mth == "endsWith" {
                return "Bool"
            }
            if mth == "split" {
                return "List<String>"
            }
        }
        if self.isSetType(bt) {
            if mth == "length" {
                return "Int"
            }
            if mth == "has" {
                return "Bool"
            }
            if mth == "add" {
                return "Bool"
            }
        }
        if self.isResultType(bt) {
            if mth == "isOk" || mth == "isErr" {
                return "Bool"
            }
            if mth == "value" || mth == "unwrapOr" {
                return self.resultValueType(bt)
            }
            if mth == "error" {
                return self.resultErrorType(bt)
            }
        }
        if self.elementType(bt) != "Any" {
            if mth == "length" {
                return "Int"
            }
            if mth == "get" {
                return self.elementType(bt)
            }
            if mth == "push" || mth == "remove" || mth == "set" || mth == "insert" {
                return "Unit"
            }
            if mth == "join" {
                return "String"
            }
        }
        if self.isMapType(bt) {
            if mth == "length" {
                return "Int"
            }
            if mth == "has" {
                return "Bool"
            }
            if mth == "put" {
                return "Unit"
            }
            if mth == "getOr" {
                return self.mapValueType(bt)
            }
        }
        if self.isProtocolName(bt) {
            String pr = self.protocolRet(bt, mth)
            if pr != "Any" {
                String pps = self.protocolParams(bt, mth)
                List<String> pwant = []
                if pps != "" {
                    pwant = pps.split(",")
                }
                if pwant.length() != argc {
                    self.fail("SEM-004", mth + " expects " + str(pwant.length()) + " arguments, got " + str(argc), n)
                    return "Error"
                }
                Int pai = 0
                while pai < argc && !self.hasError() {
                    String pat = self.argType(n.kids.get(pai + 1), pwant.get(pai))
                    if pat != "Error" && !self.sameType(pat, pwant.get(pai)) {
                        self.fail("SEM-003", "argument " + str(pai + 1) + " of " + mth + ": expected " + pwant.get(pai) + ", got " + pat, n)
                    }
                    pai = pai + 1
                }
                return pr
            }
        }
        Int mi = self.findMethod(bt, mth)
        if mi < 0 {
            self.fail("SEM-001", "undefined method: " + bt + "." + mth, n)
            return "Error"
        }
        String ps = self.methodParams.get(mi)
        if ps == "" {
            if argc != 0 {
                self.fail("SEM-004", mth + " expects 0 arguments, got " + str(argc), n)
                return "Error"
            }
            return self.methodRets.get(mi)
        }
        List<String> want = ps.split(",")
        if want.length() != argc {
            self.fail("SEM-004", mth + " expects " + str(want.length()) + " arguments, got " + str(argc), n)
            return "Error"
        }
        Int ai = 0
        while ai < argc && !self.hasError() {
            String at = self.argType(n.kids.get(ai + 1), want.get(ai))
            if at != "Error" && !self.sameType(at, want.get(ai)) {
                self.fail("SEM-003", "argument " + str(ai + 1) + " of " + mth + ": expected " + want.get(ai) + ", got " + at, n)
            }
            ai = ai + 1
        }
        return self.methodRets.get(mi)
    }

    String argType(AstNode arg, String want) {
        if arg.kind == "Lambda" {
            String oldExp = self.expectedLambda
            self.expectedLambda = want
            String t = self.typeOf(arg)
            self.expectedLambda = oldExp
            return t
        }
        return self.typeOf(arg)
    }

    String checkCall(AstNode n) {
        Int argc = n.kids.length()
        if n.text == "AtomicInt" || n.text == "AtomicBool" {
            if argc > 1 {
                self.fail("SEM-004", n.text + " expects 0 or 1 argument", n)
                return "Error"
            }
            if argc == 1 {
                String at = self.typeOf(n.kids.get(0))
                String want = "Int"
                if n.text == "AtomicBool" { want = "Bool" }
                if at != "Error" && !self.sameType(at, want) {
                    self.fail("SEM-003", n.text + " expects " + want + ", got " + at, n)
                    return "Error"
                }
            }
            return n.text
        }
        if n.text == "diagnoseRaw" {
            if argc != 1 {
                self.fail("SEM-004", "diagnoseRaw expects 1 argument", n)
            } else {
                self.typeOf(n.kids.get(0))
            }
            return "Int"
        }
        if n.text == "exitRaw" {
            if argc != 1 {
                self.fail("SEM-004", "exitRaw expects 1 argument", n)
            } else {
                self.typeOf(n.kids.get(0))
            }
            return "Int"
        }
        if n.text == "listFiles" {
            if argc != 1 {
                self.fail("SEM-004", "listFiles expects 1 argument", n)
            } else {
                self.typeOf(n.kids.get(0))
            }
            return "String"
        }
        if n.text == "readFile" {
            if argc != 1 {
                self.fail("SEM-004", "readFile expects 1 argument", n)
            } else {
                self.typeOf(n.kids.get(0))
            }
            return "String"
        }
        if n.text == "nowMonoRaw" || n.text == "nowWallRaw" {
            if argc != 0 {
                self.fail("SEM-004", n.text + " expects 0 arguments", n)
            }
            return "Long"
        }
        if n.text == "resourceExistsRaw" {
            if argc != 1 { self.fail("SEM-004", "resourceExistsRaw expects 1 argument", n) } else { self.typeOf(n.kids.get(0)) }
            return "Int"
        }
        if n.text == "readResourceTextRaw" {
            if argc != 1 { self.fail("SEM-004", "readResourceTextRaw expects 1 argument", n) } else { self.typeOf(n.kids.get(0)) }
            return "String"
        }
        if n.text == "resourceCountRaw" {
            return "Int"
        }
        if n.text == "readFileTextRaw" {
            if argc != 1 {
                self.fail("SEM-004", "readFileTextRaw expects 1 argument", n)
            } else {
                self.typeOf(n.kids.get(0))
            }
            return "String"
        }
        if n.text == "readFileTextError" {
            return "Int"
        }
        if n.text == "fileExistsRaw" {
            if argc != 1 {
                self.fail("SEM-004", "fileExistsRaw expects 1 argument", n)
            } else {
                self.typeOf(n.kids.get(0))
            }
            return "Int"
        }
        if n.text == "platformRaw" {
            if argc != 0 {
                self.fail("SEM-004", "platformRaw expects 0 arguments", n)
            }
            return "String"
        }
        if n.text == "Set.of" {
            Int i = 0
            while i < argc {
                String at = self.typeOf(n.kids.get(i))
                if at != "Error" && at != "Int" {
                    self.fail("SEM-003", "Set.of expects Int, got " + at, n)
                }
                i = i + 1
            }
            return "Set<Int>"
        }
        if n.text == "Ok" || n.text == "Err" {
            if !self.isResultType(self.curRet) {
                self.fail("SEM-003", n.text + " requires Result return type", n)
                return "Error"
            }
            if argc > 1 {
                self.fail("SEM-004", n.text + " expects 0 or 1 argument, got " + str(argc), n)
                return "Error"
            }
            if argc > 0 {
                self.typeOf(n.kids.get(0))
            }
            return self.curRet
        }
        Int dot = lastDot(n.text)
        if dot >= 0 {
            String base = n.text.substring(0, dot)
            String mth = n.text.substring(dot + 1, n.text.length() - dot - 1)
            String bt = self.pathType(base)
            if bt == "Any" {
                self.fail("SEM-001", "undefined symbol: " + base, n)
                return "Error"
            }
            if bt == "AtomicInt" {
                if mth == "load" { return "Int" }
                if mth == "store" {
                    if argc != 1 { self.fail("SEM-004", "AtomicInt.store expects 1 argument", n) }
                    return "Unit"
                }
                if mth == "cas" || mth == "compareExchange" { return "Bool" }
                self.fail("SEM-001", "undefined method: AtomicInt." + mth, n)
                return "Error"
            }
            if bt == "AtomicBool" {
                if mth == "load" { return "Bool" }
                if mth == "store" {
                    if argc != 1 { self.fail("SEM-004", "AtomicBool.store expects 1 argument", n) }
                    return "Unit"
                }
                if mth == "cas" || mth == "compareExchange" { return "Bool" }
                self.fail("SEM-001", "undefined method: AtomicBool." + mth, n)
                return "Error"
            }
            if bt == "Bytes" {
                if mth == "fromString" {
                    return "Bytes"
                }
                if mth == "length" || mth == "get" {
                    return "Int"
                }
                if mth == "slice" {
                    return "Bytes"
                }
                if mth == "toString" {
                    return "String"
                }
                if mth == "set" || mth == "append" || mth == "push" {
                    return "Unit"
                }
            }
            if bt == "String" {
                if mth == "length" || mth == "get" {
                    return "Int"
                }
                if mth == "indexOf" || mth == "indexOfByte" {
                    return "Int"
                }
                if mth == "substring" || mth == "charAt" {
                    return "String"
                }
                if mth == "trim" || mth == "replace" || mth == "toUpper" || mth == "toLower" {
                    return "String"
                }
                if mth == "startsWith" || mth == "endsWith" {
                    return "Bool"
                }
                if mth == "split" {
                    return "List<String>"
                }
            }
            if self.isSetType(bt) {
                if mth == "length" {
                    return "Int"
                }
                if mth == "has" {
                    return "Bool"
                }
                if mth == "add" {
                    return "Bool"
                }
            }
            if self.isResultType(bt) {
                if mth == "isOk" || mth == "isErr" {
                    return "Bool"
                }
                if mth == "unwrapOr" {
                    return self.resultValueType(bt)
                }
                if mth == "value" {
                    return self.resultValueType(bt)
                }
                if mth == "error" {
                    return self.resultErrorType(bt)
                }
            }
            if self.elementType(bt) != "Any" {
                if mth == "length" {
                    return "Int"
                }
                if mth == "get" {
                    return self.elementType(bt)
                }
                if mth == "push" || mth == "set" || mth == "insert" {
                    return "Unit"
                }
                if mth == "remove" || mth == "insert" {
                    return "Unit"
                }
                if mth == "join" {
                    return "String"
                }
            }
            if self.isMapType(bt) {
                if mth == "length" {
                    return "Int"
                }
                if mth == "has" {
                    return "Bool"
                }
                if mth == "getOr" {
                    return self.mapValueType(bt)
                }
                if mth == "put" {
                    return "Unit"
                }
            }
            if self.isProtocolName(bt) {
                String pr = self.protocolRet(bt, mth)
                if pr != "Any" {
                    String pps = self.protocolParams(bt, mth)
                    List<String> pwant = []
                    if pps != "" {
                        pwant = pps.split(",")
                    }
                    if pwant.length() != argc {
                        self.fail("SEM-004", mth + " expects " + str(pwant.length()) + " arguments, got " + str(argc), n)
                        return "Error"
                    }
                    Int pai = 0
                    while pai < argc && !self.hasError() {
                        String pat = self.argType(n.kids.get(pai), pwant.get(pai))
                        if pat != "Error" && !self.sameType(pat, pwant.get(pai)) {
                            self.fail("SEM-003", "argument " + str(pai + 1) + " of " + mth + ": expected " + pwant.get(pai) + ", got " + pat, n)
                        }
                        pai = pai + 1
                    }
                    return pr
                }
            }
            String fty = self.fieldType(bt, mth)
            if self.isFunctionType(fty) {
                List<String> want = self.fnParams(fty)
                if want.length() != argc {
                    self.fail("SEM-004", mth + " expects " + str(want.length()) + " arguments, got " + str(argc), n)
                    return "Error"
                }
                Int ai = 0
                while ai < argc && !self.hasError() {
                    String at = self.argType(n.kids.get(ai), want.get(ai))
                    if at != "Error" && !self.sameType(at, want.get(ai)) {
                        self.fail("SEM-003", "argument " + str(ai + 1) + " of " + mth + ": expected " + want.get(ai) + ", got " + at, n)
                    }
                    ai = ai + 1
                }
                return self.fnRetType(fty)
            }
            Int mi = self.findMethod(bt, mth)
            if mi < 0 {
                self.fail("SEM-001", "undefined method: " + bt + "." + mth, n)
                return "Error"
            }
            String ps = self.methodParams.get(mi)
            if ps == "" {
                if argc != 0 {
                    self.fail("SEM-004", mth + " expects 0 arguments, got " + str(argc), n)
                    return "Error"
                }
                return self.methodRets.get(mi)
            }
            List<String> want = ps.split(",")
            if want.length() != argc {
                self.fail("SEM-004", mth + " expects " + str(want.length()) + " arguments, got " + str(argc), n)
                return "Error"
            }
            Int ai = 0
            while ai < argc && !self.hasError() {
                String at = self.argType(n.kids.get(ai), want.get(ai))
                if at != "Error" && at != want.get(ai) {
                    self.fail("SEM-003", "argument " + str(ai + 1) + " of " + mth + ": expected " + want.get(ai) + ", got " + at, n)
                }
                ai = ai + 1
            }
            return self.methodRets.get(mi)
        }
        Int ffi = ffiIndex(n.text)
        if ffi >= 0 {
            return ffiRet(n.text)
        }
        if n.text == "print" {
            if argc != 1 {
                self.fail("SEM-004", "print expects 1 argument, got " + str(argc), n)
            } else {
                self.typeOf(n.kids.get(0))
            }
            return "Unit"
        }
        if n.text == "str" {
            if argc != 1 {
                self.fail("SEM-004", "str expects 1 argument, got " + str(argc), n)
            } else {
                self.typeOf(n.kids.get(0))
            }
            return "String"
        }
        Int fvi = self.findVar(n.text)
        if fvi >= 0 && self.isFunctionType(self.varTypes.get(fvi)) {
            String ft = self.varTypes.get(fvi)
            List<String> want = self.fnParams(ft)
            if want.length() != argc {
                self.fail("SEM-004", n.text + " expects " + str(want.length()) + " arguments, got " + str(argc), n)
                return "Error"
            }
            Int ai = 0
            while ai < argc && !self.hasError() {
                String at = self.argType(n.kids.get(ai), want.get(ai))
                if at != "Error" && !self.sameType(at, want.get(ai)) {
                    self.fail("SEM-003", "argument " + str(ai + 1) + " of " + n.text + ": expected " + want.get(ai) + ", got " + at, n)
                }
                ai = ai + 1
            }
            return self.fnRetType(ft)
        }
        Int idx = self.findFn(n.text)
        if idx < 0 {
            self.fail("SEM-001", "undefined function: " + n.text, n)
            return "Error"
        }
        String ps = self.fnParams.get(idx)
        if ps == "" {
            if argc != 0 {
                self.fail("SEM-004", n.text + " expects 0 arguments, got " + str(argc), n)
                return "Error"
            }
            return self.fnRets.get(idx)
        }
        List<String> want = ps.split(",")
        if want.length() != argc {
            self.fail("SEM-004", n.text + " expects " + str(want.length()) + " arguments, got " + str(argc), n)
            return "Error"
        }
        Int i = 0
        while i < argc && !self.hasError() {
            String at = self.argType(n.kids.get(i), want.get(i))
            if at != "Error" && !self.sameType(at, want.get(i)) {
                self.fail("SEM-003", "argument " + str(i + 1) + " of " + n.text + ": expected " + want.get(i) + ", got " + at, n)
            }
            i = i + 1
        }
        return self.fnRets.get(idx)
    }
}


class CGen {
    final AstNode program
    final List<String> lines
    final List<String> vars
    final List<String> varTypes
    Int tmp
    String err
    String curClass
    String curRet
    final List<AstNode> defers
    final List<String> deferErrs
    final List<String> breakTargets
    final List<AstNode> lambdas
    final List<String> lambdaTypes
    final List<String> lambdaCaptures
    final List<String> lambdaCaptureTypes
    final List<String> lambdaCaptureScanned
    final List<String> lambdaOwners
    final List<String> ffiCallNames
    final List<String> ffiCallCNames
    final List<String> ffiCallRets
    final List<String> ffiCallSpecs
    final List<String> ffiCallErrParams
    final List<String> ffiCallErrRets

    CGen(AstNode program, List<String> callNames, List<String> callCNames, List<String> callRets, List<String> callSpecs, List<String> callErrParams, List<String> callErrRets) {
        self.program = program
        self.lines = []
        self.vars = []
        self.varTypes = []
        self.tmp = 0
        self.err = ""
        self.curClass = ""
        self.curRet = "Int"
        self.defers = []
        self.deferErrs = []
        self.breakTargets = []
        self.lambdas = []
        self.lambdaTypes = []
        self.lambdaCaptures = []
        self.lambdaCaptureTypes = []
        self.lambdaCaptureScanned = []
        self.lambdaOwners = []
        self.ffiCallNames = callNames
        self.ffiCallCNames = callCNames
        self.ffiCallRets = callRets
        self.ffiCallSpecs = callSpecs
        self.ffiCallErrParams = callErrParams
        self.ffiCallErrRets = callErrRets
    }

    Bool hasError() {
        return self.err != ""
    }

    Void fail(String msg) {
        if self.err == "" {
            self.err = msg
        }
    }

    Void emit(String line) {
        self.lines.push(line)
    }

    String temp() {
        self.tmp = self.tmp + 1
        return "xn_t" + str(self.tmp)
    }

    AstNode retNode(AstNode fn) {
        Int i = 0
        while i < fn.kids.length() {
            AstNode k = fn.kids.get(i)
            if k.kind == "Ret" {
                return k
            }
            i = i + 1
        }
        return new AstNode("Ret", "Unit", fn.line, fn.col)
    }

    List<AstNode> paramsOf(AstNode fn) {
        List<AstNode> ps = []
        Int i = 0
        while i < fn.kids.length() {
            AstNode k = fn.kids.get(i)
            if k.kind == "Param" {
                ps.push(k)
            }
            i = i + 1
        }
        return ps
    }

    Bool isProtocol(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Protocol" && n.text == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    String protoRet(String pname, String mname) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode p = self.program.kids.get(i)
            if p.kind == "Protocol" && p.text == pname {
                Int j = 0
                while j < p.kids.length() {
                    AstNode sig = p.kids.get(j)
                    if sig.kind == "Sig" && sig.text == mname {
                        Int k = 0
                        while k < sig.kids.length() {
                            if sig.kids.get(k).kind == "Ret" {
                                return sig.kids.get(k).text
                            }
                            k = k + 1
                        }
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return "Unit"
    }

    List<AstNode> protoParams(String pname, String mname) {
        List<AstNode> res = []
        Int i = 0
        while i < self.program.kids.length() {
            AstNode p = self.program.kids.get(i)
            if p.kind == "Protocol" && p.text == pname {
                Int j = 0
                while j < p.kids.length() {
                    AstNode sig = p.kids.get(j)
                    if sig.kind == "Sig" && sig.text == mname {
                        Int k = 0
                        while k < sig.kids.length() {
                            if sig.kids.get(k).kind == "Param" {
                                res.push(sig.kids.get(k))
                            }
                            k = k + 1
                        }
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return res
    }

    String ctype(String ty) {
        if ty.length() > 1 && ty.substring(ty.length() - 1, 1) == "?" {
            return self.ctype(ty.substring(0, ty.length() - 1))
        }
        if ty == "Int" {
            return "int64_t"
        }
        if ty == "String" {
            return "rt_string *"
        }
        if ty == "Bytes" {
            return "xrt_bytes_obj *"
        }
        if ty == "AtomicInt" {
            return "xrt_atomic_int *"
        }
        if ty == "AtomicBool" {
            return "xrt_atomic_bool *"
        }
        if ty == "Bool" {
            return "int"
        }
        if ty == "Char" {
            return "int32_t"
        }
        if ty == "Double" {
            return "double"
        }
        if ty == "Long" || ty == "Int64" || ty == "Int32" {
            return "int64_t"
        }
        if ty == "Void" || ty == "void" || ty == "Unit" {
            return "void"
        }
        if ty == "UInt16" {
            return "int64_t"
        }
        if self.isFunctionType(ty) {
            return "xn_closure"
        }
        if self.isArray(ty) || ty == "List<Int>" {
            return self.arrayCName(ty) + " *"
        }
        if ty == "Map<String,Int>" {
            return "xn_map_s_i *"
        }
        if self.isSet(ty) {
            return "xn_set_i *"
        }
        if ty == "Result<Int,String>" {
            return "xn_Result_Int_String"
        }
        if self.isResult(ty) {
            return "xn_Result"
        }
        if self.isClass(ty) {
            return "xn_Cls_" + ty + " *"
        }
        if self.isDataEnum(ty) {
            return "xn_Cls_" + ty + " *"
        }
        if self.isEnumName(ty) {
            return "int64_t"
        }
        if self.isProtocol(ty) {
            return "void *"
        }
        self.fail("unsupported type: " + ty)
        return "int64_t"
    }

    Bool isGenericResult(String ty) {
        return self.isResult(ty) && ty != "Result<Int,String>"
    }

    String resultInitField(String ty, String val) {
        String vt = self.resultValue(ty)
        if vt == "Int" || vt == "Int32" || vt == "Int64" || vt == "Long" || vt == "Bool" || vt == "Char" {
            return ".i = (int64_t)(" + val + ")"
        }
        if vt == "Double" {
            return ".d = (double)(" + val + ")"
        }
        if vt == "String" {
            return ".s = (rt_string *)(" + val + ")"
        }
        return ".p = (void *)(" + val + ")"
    }

    String resultValueExpr(String ty, String bv) {
        String vt = self.resultValue(ty)
        if vt == "Int" || vt == "Int32" || vt == "Int64" || vt == "Long" || vt == "Bool" || vt == "Char" {
            return "(" + bv + ").i"
        }
        if vt == "Double" {
            return "(" + bv + ").d"
        }
        if vt == "String" {
            return "(" + bv + ").s"
        }
        return "(" + bv + ").p"
    }

    Bool isResult(String ty) {
        return ty.length() > 8 && ty.substring(0, 7) == "Result<"
    }

    String resultValue(String ty) {
        String inner = ty.substring(7, ty.length() - 8)
        List<String> parts = inner.split(",")
        if parts.length() >= 1 {
            return parts.get(0)
        }
        return "Any"
    }

    Bool isArray(String ty) {
        return (ty.length() >= 2 && ty.substring(ty.length() - 2, 2) == "[]") ||
            (ty.length() > 6 && ty.substring(0, 5) == "List<")
    }

    String elementType(String ty) {
        if ty.length() >= 2 && ty.substring(ty.length() - 2, 2) == "[]" {
            return ty.substring(0, ty.length() - 2)
        }
        if ty.length() > 6 && ty.substring(0, 5) == "List<" {
            return ty.substring(5, ty.length() - 6)
        }
        return "Any"
    }

    String curFieldType(String fname) {
        if self.curClass == "" {
            return "Any"
        }
        return self.fieldType(self.curClass, fname)
    }

    String topFieldType(String fname) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "TopField" {
                List<String> parts = n.text.split(" ")
                if parts.length() >= 2 && parts.get(1) == fname {
                    return parts.get(0)
                }
            }
            i = i + 1
        }
        return "Any"
    }

    String pathType(String path) {
        Int dot = path.indexOf(".")
        if dot < 0 {
            if path == "self" {
                return self.curClass
            }
            if path == "Bytes" {
                return "Bytes"
            }
            if self.isClass(path) {
                return path
            }
            String vt = self.findVar(path)
            if vt != "Any" {
                return vt
            }
            String ft = self.curFieldType(path)
            if ft != "Any" {
                return ft
            }
            return self.topFieldType(path)
        }
        String head = path.substring(0, dot)
        String rest = path.substring(dot + 1, path.length() - dot - 1)
        String bt = self.pathType(head)
        while bt != "Any" && rest.length() > 0 {
            Int d = rest.indexOf(".")
            String seg = rest
            if d >= 0 {
                seg = rest.substring(0, d)
                rest = rest.substring(d + 1, rest.length() - d - 1)
            } else {
                rest = ""
            }
            bt = self.fieldType(bt, seg)
        }
        return bt
    }

    String pathExpr(String path) {
        Int dot = path.indexOf(".")
        if dot < 0 {
            return self.nameExpr(path)
        }
        String b = self.nameExpr(path.substring(0, dot))
        String rest = path.substring(0, dot)
        rest = path.substring(dot + 1, path.length() - dot - 1)
        while rest.length() > 0 {
            Int d = rest.indexOf(".")
            String seg = rest
            if d >= 0 {
                seg = rest.substring(0, d)
                rest = rest.substring(d + 1, rest.length() - d - 1)
            } else {
                rest = ""
            }
            b = b + "->" + seg
        }
        return b
    }


    String arrayCName(String ty) {
        String et = self.elementType(ty)
        if et == "Int" || et == "Long" || et == "Int64" || et == "UInt16" || self.isEnumName(et) {
            return "xn_arr_i"
        }
        if et == "Double" {
            return "xn_arr_d"
        }
        if et == "String" {
            return "xn_arr_s"
        }
        return "xn_arr_o"
    }

    String arrayNew(String ty, Int cap) {
        return self.arrayCName(ty) + "_new(" + str(cap) + ")"
    }

    String arrayPush(String ty, String arr, String val) {
        return self.arrayCName(ty) + "_push(" + arr + ", " + val + ")"
    }

    String arrayGet(String ty, String arr, String idx) {
        String ac = self.arrayCName(ty)
        String call = ac + "_get(" + arr + ", " + idx + ")"
        if ac == "xn_arr_o" {
            return "((xn_Cls_" + self.elementType(ty) + " *)" + call + ")"
        }
        return call
    }

    String nameExpr(String name) {
        if name == "self" {
            return "self"
        }
        if self.findVar(name) != "Any" || self.topFieldType(name) != "Any" {
            return name
        }
        if self.curFieldType(name) != "Any" {
            return "self->" + name
        }
        return name
    }

    String resultValueCExpr(String ty, String bv) {
        String vt = self.resultValue(ty)
        String base = self.resultValueExpr(ty, bv)
        if self.isArray(vt) || self.isMap(vt) || self.isSet(vt) ||
           self.isClass(vt) || self.isDataEnum(vt) || self.isProtocol(vt) ||
           vt == "Bytes" {
            return "((" + self.ctype(vt) + ")" + base + ")"
        }
        return base
    }

    Bool isGcRefType(String ty) {
        if ty == "String" || ty == "Bytes" || ty == "Any" {
            return true
        }
        if self.isArray(ty) || self.isMap(ty) || self.isSet(ty) {
            return true
        }
        if self.isClass(ty) || self.isDataEnum(ty) || self.isProtocol(ty) {
            return true
        }
        return false
    }

    Bool isMap(String ty) {
        return ty.length() > 5 && ty.substring(0, 4) == "Map<"
    }

    Bool isSet(String ty) {
        return ty.length() > 5 && ty.substring(0, 4) == "Set<"
    }

    String mapValue(String ty) {
        String inner = ty.substring(4, ty.length() - 5)
        List<String> parts = inner.split(",")
        if parts.length() >= 2 {
            return parts.get(1)
        }
        return "Any"
    }

    Bool isFunctionType(String ty) {
        Int p = ty.indexOf("(")
        return p > 0 && ty.length() > p + 1 && ty.substring(ty.length() - 1, 1) == ")"
    }

    String fnRetType(String ty) {
        Int p = ty.indexOf("(")
        if p > 0 {
            return ty.substring(0, p)
        }
        return "Any"
    }

    List<String> fnParams(String ty) {
        List<String> res = []
        Int p = ty.indexOf("(")
        if p <= 0 || ty.substring(ty.length() - 1, 1) != ")" {
            return res
        }
        String inner = ty.substring(p + 1, ty.length() - p - 2)
        if inner.trim() == "" {
            return res
        }
        List<String> raw = inner.split(",")
        Int i = 0
        while i < raw.length() {
            res.push(raw.get(i).trim())
            i = i + 1
        }
        return res
    }

    Int lambdaIndex(AstNode n) {
        Int i = 0
        while i < self.lambdas.length() {
            if self.lambdas.get(i) == n {
                return i
            }
            i = i + 1
        }
        return -1
    }

    AstNode findFunctionNode(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" && n.text == name {
                return n
            }
            i = i + 1
        }
        return new AstNode("None", "", 1, 1)
    }

    String callParamType(String name, Int argIndex) {
        AstNode f = self.findFunctionNode(name)
        if f.kind != "Func" {
            return ""
        }
        List<AstNode> ps = self.paramsOf(f)
        if argIndex < 0 || argIndex >= ps.length() {
            return ""
        }
        List<String> parts = ps.get(argIndex).text.split(" ")
        if parts.length() >= 2 {
            return parts.get(0)
        }
        return ""
    }

    String ctorParamType(String cls, Int argIndex) {
        AstNode c = self.classNode(cls)
        if c.kind == "error" {
            return ""
        }
        AstNode ctor = self.ctorOf(c)
        if ctor.kind != "Ctor" {
            return ""
        }
        List<AstNode> ps = self.paramsOf(ctor)
        if argIndex < 0 || argIndex >= ps.length() {
            return ""
        }
        List<String> parts = ps.get(argIndex).text.split(" ")
        if parts.length() >= 2 {
            return parts.get(0)
        }
        return ""
    }

    Void registerLambda(AstNode lam, String ty) {
        if ty == "" || self.lambdaIndex(lam) >= 0 {
            return
        }
        self.lambdas.push(lam)
        self.lambdaTypes.push(ty)
        self.lambdaCaptures.push("")
        self.lambdaCaptureTypes.push("")
        self.lambdaCaptureScanned.push("0")
        self.lambdaOwners.push("")
    }

    Void collectReturnLambdas(AstNode n, String retTy) {
        if n.kind == "Return" {
            if n.kids.length() > 0 {
                self.collectLambdas(n.kids.get(0), retTy)
            }
            return
        }
        if n.kind == "Lambda" {
            return
        }
        Int i = 0
        while i < n.kids.length() {
            self.collectReturnLambdas(n.kids.get(i), retTy)
            i = i + 1
        }
    }

    Void collectLambdas(AstNode n, String expected) {
        if n.kind == "Func" || n.kind == "Method" {
            String retTy = self.retNode(n).text
            Int ri = 0
            while ri < n.kids.length() {
                if n.kids.get(ri).kind == "Block" {
                    self.collectReturnLambdas(n.kids.get(ri), retTy)
                }
                ri = ri + 1
            }
        }
        if n.kind == "Lambda" {
            self.registerLambda(n, expected)
            if expected != "" {
                Int ri = 0
                while ri < n.kids.length() {
                    if n.kids.get(ri).kind == "Block" {
                        self.collectReturnLambdas(n.kids.get(ri), self.fnRetType(expected))
                    }
                    ri = ri + 1
                }
            }
            Int i = 0
            while i < n.kids.length() {
                self.collectLambdas(n.kids.get(i), "")
                i = i + 1
            }
            return
        }
        if n.kind == "Local" {
            List<String> parts = n.text.split(" ")
            String exp = ""
            if parts.length() >= 2 && self.isFunctionType(parts.get(0)) {
                exp = parts.get(0)
            }
            if n.kids.length() > 0 {
                self.collectLambdas(n.kids.get(0), exp)
            }
            return
        }
        if n.kind == "New" {
            Int i = 0
            while i < n.kids.length() {
                self.collectLambdas(n.kids.get(i), self.ctorParamType(n.text, i))
                i = i + 1
            }
            return
        }
        if n.kind == "Call" {
            Int i = 0
            while i < n.kids.length() {
                self.collectLambdas(n.kids.get(i), self.callParamType(n.text, i))
                i = i + 1
            }
            return
        }
        Int i = 0
        while i < n.kids.length() {
            self.collectLambdas(n.kids.get(i), "")
            i = i + 1
        }
    }

    List<String> splitCaps(String s) {
        if s == "" {
            List<String> empty = []
            return empty
        }
        return s.split("|")
    }

    String joinCaps(List<String> xs) {
        String s = ""
        Int i = 0
        while i < xs.length() {
            if i > 0 {
                s = s + "|"
            }
            s = s + xs.get(i)
            i = i + 1
        }
        return s
    }

    Bool listHas(List<String> xs, String v) {
        Int i = 0
        while i < xs.length() {
            if xs.get(i) == v {
                return true
            }
            i = i + 1
        }
        return false
    }

    Void collectShadows(AstNode n, List<String> out) {
        if n.kind == "Local" {
            List<String> parts = n.text.split(" ")
            if parts.length() >= 2 && !self.listHas(out, parts.get(1)) {
                out.push(parts.get(1))
            }
        }
        if n.kind == "ForIn" || n.kind == "ForRange" {
            if n.text.trim() != "" {
                List<String> parts = n.text.trim().split(" ")
                if parts.length() >= 1 && !self.listHas(out, parts.get(parts.length() - 1)) {
                    out.push(parts.get(parts.length() - 1))
                }
            }
        }
        Int i = 0
        while i < n.kids.length() {
            self.collectShadows(n.kids.get(i), out)
            i = i + 1
        }
    }

    Bool containsVarUse(AstNode n, String name) {
        if n.kind == "Name" && n.text == name {
            return true
        }
        if n.kind == "Call" && (n.text == name || n.text.startsWith(name + ".")) {
            return true
        }
        Int i = 0
        while i < n.kids.length() {
            if self.containsVarUse(n.kids.get(i), name) {
                return true
            }
            i = i + 1
        }
        return false
    }

    Void ensureLambdaCaptures(Int li, AstNode lam) {
        if li < 0 || li >= self.lambdaCaptures.length() {
            return
        }
        if self.lambdaCaptureScanned.get(li) == "1" {
            return
        }
        List<String> params = []
        Int i = 0
        while i < lam.kids.length() {
            AstNode k = lam.kids.get(i)
            if k.kind == "Param" {
                List<String> pp = k.text.split(" ")
                if pp.length() >= 2 {
                    params.push(pp.get(1))
                }
            }
            i = i + 1
        }
        List<String> shadows = []
        i = 0
        while i < lam.kids.length() {
            if lam.kids.get(i).kind == "Block" {
                self.collectShadows(lam.kids.get(i), shadows)
            }
            i = i + 1
        }
        List<String> names = self.splitCaps(self.lambdaCaptures.get(li))
        List<String> types = self.splitCaps(self.lambdaCaptureTypes.get(li))
        i = self.vars.length() - 1
        while i >= 0 {
            String vn = self.vars.get(i)
            if !self.listHas(params, vn) && !self.listHas(shadows, vn) &&
               !self.listHas(names, vn) && self.containsVarUse(lam, vn) {
                names.push(vn)
                types.push(self.varTypes.get(i))
            }
            i = i - 1
        }
        self.lambdaCaptures.set(li, self.joinCaps(names))
        self.lambdaCaptureTypes.set(li, self.joinCaps(types))
        self.lambdaCaptureScanned.set(li, "1")
    }

    String lambdaName(AstNode n) {
        Int i = self.lambdaIndex(n)
        if i < 0 {
            return "xn_lambda_missing"
        }
        return "xn_lambda_" + str(i)
    }

    String fnPtrDecl(String ty, String name) {
        return "xn_closure " + name
    }

    Bool ffiSpecial(String name) {
        return name == "diagnoseRaw" || name == "exitRaw" ||
            name == "nowMonoRaw" || name == "nowWallRaw" ||
            name == "resourceExistsRaw" || name == "resourceCountRaw" ||
            name == "readResourceTextRaw" || name == "fileExistsRaw" ||
            name == "readFile" || name == "listFiles" || name == "platformRaw" ||
            name == "readFileTextRaw" || name == "readFileTextError"
    }

    Bool ffiHardProto(String cname) {
        return cname == "xdkc_p_resource_exists" ||
            cname == "xdkc_p_read_resource_text" ||
            cname == "xdkc_p_resource_count" ||
            cname == "xdkc_read_file_text" ||
            cname == "xdkc_read_file_text_error" ||
            cname == "xdkc_diagnose_rc" ||
            cname == "xdkc_exit_rc" ||
            cname == "xdkc_now_mono_ms" ||
            cname == "xdkc_now_wall_ms"
    }

    Bool ffiTypeOk(String ty) {
        return ty == "Int" || ty == "Int32" || ty == "Int64" || ty == "Long" ||
            ty == "UInt16" || ty == "Bool" || ty == "Double" || ty == "Float" ||
            ty == "String" || ty == "Bytes" || ty == "Context" ||
            ty == "void" || ty == "Void" || ty == "Unit"
    }

    String ffiMiniType(String ty) {
        if ty == "Context" {
            return "void *"
        }
        if ty == "Bytes" {
            return "xrt_bytes_obj *"
        }
        if ty == "String" {
            return "rt_string *"
        }
        if ty == "Double" {
            return "double"
        }
        if ty == "Float" {
            return "double"
        }
        if ty == "Bool" {
            return "int"
        }
        if ty == "void" || ty == "Void" || ty == "Unit" {
            return "void"
        }
        return "int64_t"
    }

    String ffiAbiType(String ty) {
        if ty == "String" {
            return "const char *"
        }
        if ty == "Bytes" {
            return "const unsigned char *"
        }
        if ty == "Context" {
            return "void *"
        }
        if ty == "Int32" || ty == "Bool" {
            return "int32_t"
        }
        if ty == "Double" {
            return "double"
        }
        if ty == "Float" {
            return "float"
        }
        if ty == "void" || ty == "Void" || ty == "Unit" {
            return "void"
        }
        return "int64_t"
    }

    Int ffiParamCount(Int idx) {
        if idx < 0 || idx >= self.ffiCallSpecs.length() || self.ffiCallSpecs.get(idx) == "" {
            return 0
        }
        return self.ffiCallSpecs.get(idx).split(";").length()
    }

    String ffiParamType(Int idx, Int p) {
        if idx < 0 || idx >= self.ffiCallSpecs.length() || self.ffiCallSpecs.get(idx) == "" {
            return ""
        }
        List<String> segs = self.ffiCallSpecs.get(idx).split(";")
        if p < 0 || p >= segs.length() {
            return ""
        }
        List<String> parts = segs.get(p).split(":")
        if parts.length() >= 3 {
            return parts.get(2)
        }
        return ""
    }

    String ffiParamName(Int idx, Int p) {
        if idx < 0 || idx >= self.ffiCallSpecs.length() || self.ffiCallSpecs.get(idx) == "" {
            return ""
        }
        List<String> segs = self.ffiCallSpecs.get(idx).split(";")
        if p < 0 || p >= segs.length() {
            return ""
        }
        List<String> parts = segs.get(p).split(":")
        if parts.length() >= 1 {
            return parts.get(0)
        }
        return ""
    }

    String ffiErrParam(Int idx) {
        if idx < 0 || idx >= self.ffiCallErrParams.length() {
            return ""
        }
        return self.ffiCallErrParams.get(idx)
    }

    Int ffiErrParamIndex(Int idx) {
        String ep = self.ffiErrParam(idx)
        if ep == "" {
            return -1
        }
        Int n = self.ffiParamCount(idx)
        Int p = 0
        while p < n {
            if self.ffiParamName(idx, p) == ep {
                return p
            }
            p = p + 1
        }
        return -1
    }

    Bool ffiEntryOk(Int idx) {
        if idx < 0 || idx >= self.ffiCallNames.length() {
            return false
        }
        if !self.ffiTypeOk(self.ffiCallRets.get(idx)) {
            return false
        }
        Int n = self.ffiParamCount(idx)
        Int p = 0
        while p < n {
            if !self.ffiTypeOk(self.ffiParamType(idx, p)) {
                return false
            }
            p = p + 1
        }
        return true
    }

    String ffiAbiProto(Int idx) {
        String cname = self.ffiCallCNames.get(idx)
        String ret = self.ffiAbiType(self.ffiCallRets.get(idx))
        String sig = "extern " + ret + " " + cname + "("
        Int n = self.ffiParamCount(idx)
        Int epi = self.ffiErrParamIndex(idx)
        if n == 0 {
            sig = sig + "void"
        }
        Int p = 0
        while p < n {
            if p > 0 {
                sig = sig + ", "
            }
            String ty = self.ffiParamType(idx, p)
            if p == epi {
                sig = sig + "int32_t *a" + str(p)
            } else if ty == "String" {
                sig = sig + "const char *a" + str(p) + "_bytes, size_t a" + str(p) + "_len"
            } else if ty == "Bytes" {
                sig = sig + "const unsigned char *a" + str(p) + "_data, size_t a" + str(p) + "_len"
            } else {
                sig = sig + self.ffiAbiType(ty) + " a" + str(p)
            }
            p = p + 1
        }
        return sig + ");"
    }

    String ffiWrapperSig(Int idx) {
        String name = self.ffiCallNames.get(idx)
        String ret = self.ffiMiniType(self.ffiCallRets.get(idx))
        String sig = "static " + ret + " xn_ffi_" + name + "("
        Int n = self.ffiParamCount(idx)
        Int epi = self.ffiErrParamIndex(idx)
        if n == 0 {
            sig = sig + "void"
        }
        Int p = 0
        while p < n {
            if p > 0 {
                sig = sig + ", "
            }
            if p == epi {
                sig = sig + "int64_t *a" + str(p)
            } else {
                sig = sig + self.ffiMiniType(self.ffiParamType(idx, p)) + " a" + str(p)
            }
            p = p + 1
        }
        return sig + ")"
    }

    String ffiWrapperArgs(Int idx) {
        String args = ""
        Int n = self.ffiParamCount(idx)
        Int epi = self.ffiErrParamIndex(idx)
        Int p = 0
        while p < n {
            if p > 0 {
                args = args + ", "
            }
            String ty = self.ffiParamType(idx, p)
            if p == epi {
                args = args + "&xn_err"
            } else if ty == "String" {
                args = args + "a" + str(p) + "->bytes, a" + str(p) + "->len"
            } else if ty == "Bytes" {
                args = args + "xrt_bytes_data(a" + str(p) + "), xrt_bytes_len(a" + str(p) + ")"
            } else if ty == "Int32" || ty == "Bool" {
                args = args + "(int32_t)a" + str(p)
            } else if ty == "Context" {
                args = args + "(xrt_context *)a" + str(p)
            } else {
                args = args + "a" + str(p)
            }
            p = p + 1
        }
        return args
    }

    String ffiWrapperDef(Int idx) {
        String name = self.ffiCallNames.get(idx)
        String cname = self.ffiCallCNames.get(idx)
        String rt = self.ffiCallRets.get(idx)
        Int epi = self.ffiErrParamIndex(idx)
        String call = cname + "(" + self.ffiWrapperArgs(idx) + ")"
        String body = self.ffiWrapperSig(idx) + " {\n"
        if epi >= 0 {
            body = body + "  int32_t xn_err = 0;\n"
        }
        if rt == "void" || rt == "Void" || rt == "Unit" {
            body = body + "  " + call + ";\n"
        } else {
            String miniRet = self.ffiMiniType(rt)
            String out = call
            if rt == "String" {
                out = "rt_string_from_c((const char *)" + call + ")"
            } else if rt == "Bool" {
                out = "(" + call + ") ? 1 : 0"
            } else if rt != "Double" && rt != "Float" {
                out = "(int64_t)(" + call + ")"
            }
            body = body + "  " + miniRet + " xn_out = " + out + ";\n"
        }
        if epi >= 0 {
            body = body + "  *a" + str(epi) + " = (int64_t)xn_err;\n"
        }
        if rt == "void" || rt == "Void" || rt == "Unit" {
            body = body + "  return;\n"
        } else {
            body = body + "  return xn_out;\n"
        }
        return body + "}"
    }

    Void emitFfiDecls() {
        Int i = 0
        while i < self.ffiCallNames.length() {
            if !self.ffiSpecial(self.ffiCallNames.get(i)) && self.ffiEntryOk(i) && !self.ffiHardProto(self.ffiCallCNames.get(i)) {
                self.emit(self.ffiAbiProto(i))
            }
            i = i + 1
        }
        if self.ffiCallNames.length() > 0 {
            self.emit("")
        }
        i = 0
        while i < self.ffiCallNames.length() {
            if !self.ffiSpecial(self.ffiCallNames.get(i)) && self.ffiEntryOk(i) {
                self.emit(self.ffiWrapperDef(i))
            }
            i = i + 1
        }
        if self.ffiCallNames.length() > 0 {
            self.emit("")
        }
    }

    String closureCast(String ty) {
        String ret = self.ctype(self.fnRetType(ty))
        List<String> ps = self.fnParams(ty)
        String sig = ret + " (*)(void *"
        Int i = 0
        while i < ps.length() {
            sig = sig + ", " + self.ctype(ps.get(i))
            i = i + 1
        }
        return sig + ")"
    }

    String closureCall(String ty, String target, AstNode call) {
        String b = "((" + self.closureCast(ty) + ")" + target + ".fn)(" + target + ".env"
        Int i = 0
        while i < call.kids.length() {
            b = b + ", " + self.expr(call.kids.get(i))
            i = i + 1
        }
        return b + ")"
    }

    String lambdaProto(Int i) {
        AstNode lam = self.lambdas.get(i)
        String ft = self.lambdaTypes.get(i)
        String sig = "static " + self.ctype(self.fnRetType(ft)) + " xn_lambda_" + str(i) + "(void *xn_env"
        Int pi = 0
        while pi < lam.kids.length() {
            AstNode p = lam.kids.get(pi)
            if p.kind == "Param" {
                List<String> pp = p.text.split(" ")
                if pp.length() >= 2 {
                    sig = sig + ", " + self.ctype(pp.get(0)) + " " + pp.get(1)
                }
            }
            pi = pi + 1
        }
        return sig + ");"
    }

    Void emitLambdaDef(Int i) {
        AstNode lam = self.lambdas.get(i)
        String ft = self.lambdaTypes.get(i)
        self.emit(self.lambdaProto(i).substring(0, self.lambdaProto(i).length() - 1) + " {")
        self.curRet = self.fnRetType(ft)
        String oldClass = self.curClass
        String owner = self.lambdaOwners.get(i)
        if owner != "" {
            self.curClass = owner
        }
        self.popTo(0)
        List<String> caps = self.splitCaps(self.lambdaCaptures.get(i))
        List<String> capTypes = self.splitCaps(self.lambdaCaptureTypes.get(i))
        if caps.length() > 0 {
            self.emit("  void **xn_caps = (void **)xn_env;")
        }
        Int ci = 0
        while ci < caps.length() {
            String ct = self.ctype(capTypes.get(ci))
            self.emit("  " + ct + " " + caps.get(ci) + " = *(" + ct + " *)xn_caps[" + str(ci) + "];")
            self.addVar(capTypes.get(ci), caps.get(ci))
            ci = ci + 1
        }
        Int pi = 0
        while pi < lam.kids.length() {
            AstNode p = lam.kids.get(pi)
            if p.kind == "Param" {
                List<String> pp = p.text.split(" ")
                if pp.length() >= 2 {
                    self.addVar(pp.get(0), pp.get(1))
                }
            }
            pi = pi + 1
        }
        pi = 0
        while pi < lam.kids.length() {
            if lam.kids.get(pi).kind == "Block" {
                self.blockBody(lam.kids.get(pi), "  ")
            }
            pi = pi + 1
        }
        self.popTo(0)
        self.curClass = oldClass
        self.emit("}")
        self.emit("")
    }

    Bool isEnumName(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" && n.text == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    Int enumValue(String name, String item) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" && n.text == name {
                Int j = 0
                while j < n.kids.length() {
                    AstNode it = n.kids.get(j)
                    if it.kind == "EnumItem" && it.text == item {
                        return j
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return 0
    }

    List<String> enumItems(String name) {
        List<String> res = []
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" && n.text == name {
                Int j = 0
                while j < n.kids.length() {
                    AstNode it = n.kids.get(j)
                    if it.kind == "EnumItem" {
                        res.push(it.text)
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return res
    }

    String enumCaseItem(AstNode n, String enumName) {
        if n.kind != "Member" || n.kids.length() == 0 {
            return ""
        }
        if self.typeOf(n) != enumName {
            return ""
        }
        return n.text
    }

    Bool isClass(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if (n.kind == "Class" || n.kind == "Struct") && n.text == name {
                return true
            }
            if n.kind == "Enum" && n.text == name {
                Int j = 0
                while j < n.kids.length() {
                    if n.kids.get(j).kind == "Data" {
                        return true
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return false
    }

    Bool isDataEnum(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" && n.text == name {
                Int j = 0
                while j < n.kids.length() {
                    if n.kids.get(j).kind == "Data" {
                        return true
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return false
    }

    AstNode classNode(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if ((n.kind == "Class" || n.kind == "Struct") && n.text == name) ||
               (n.kind == "Enum" && n.text == name && self.isDataEnum(name)) {
                return n
            }
            i = i + 1
        }
        return new AstNode("error", name, 1, 1)
    }

    String fieldType(String cls, String fname) {
        AstNode c = self.classNode(cls)
        Int i = 0
        while i < c.kids.length() {
            AstNode k = c.kids.get(i)
            if k.kind == "Field" {
                List<String> parts = k.text.split(" ")
                if parts.length() >= 2 && parts.get(1) == fname {
                    return parts.get(0)
                }
            }
            i = i + 1
        }
        return "Any"
    }

    Bool isStaticMethod(String cls, String mname) {
        AstNode c = self.classNode(cls)
        Int i = 0
        while i < c.kids.length() {
            AstNode k = c.kids.get(i)
            if k.kind == "Method" && k.text == mname {
                Int j = 0
                while j < k.kids.length() {
                    if k.kids.get(j).kind == "Static" {
                        return true
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        return false
    }

    String methodRet(String cls, String mname) {
        AstNode c = self.classNode(cls)
        Int i = 0
        while i < c.kids.length() {
            AstNode k = c.kids.get(i)
            if k.kind == "Method" && k.text == mname {
                String r = self.retNode(k).text
                return r
            }
            i = i + 1
        }
        return "Any"
    }

    Int varIndex(String name) {
        Int i = self.vars.length() - 1
        while i >= 0 {
            if self.vars.get(i) == name {
                return i
            }
            i = i - 1
        }
        return -1
    }

    String findVar(String name) {
        Int i = self.vars.length() - 1
        while i >= 0 {
            if self.vars.get(i) == name {
                return self.varTypes.get(i)
            }
            i = i - 1
        }
        return "Any"
    }

    Void addVar(String ty, String name) {
        self.vars.push(name)
        self.varTypes.push(ty)
    }

    Void popTo(Int mark) {
        while self.vars.length() > mark {
            self.vars.remove(self.vars.length() - 1)
            self.varTypes.remove(self.varTypes.length() - 1)
        }
    }

    String methodType(String bt, String mth, AstNode n) {
        if bt == "AtomicInt" {
            if mth == "load" { return "Int" }
            if mth == "store" { return "Unit" }
            if mth == "cas" || mth == "compareExchange" { return "Bool" }
        }
        if bt == "AtomicBool" {
            if mth == "load" { return "Bool" }
            if mth == "store" { return "Unit" }
            if mth == "cas" || mth == "compareExchange" { return "Bool" }
        }
        if bt == "String" {
            if mth == "length" || mth == "indexOf" || mth == "indexOfByte" || mth == "get" {
                return "Int"
            }
            if mth == "substring" || mth == "charAt" {
                return "String"
            }
            if mth == "trim" || mth == "replace" || mth == "toUpper" || mth == "toLower" {
                return "String"
            }
            if mth == "startsWith" || mth == "endsWith" {
                return "Bool"
            }
            if mth == "split" {
                return "List<String>"
            }
        }
        if self.isSet(bt) {
            if mth == "length" {
                return "Int"
            }
            if mth == "has" {
                return "Bool"
            }
            if mth == "add" {
                return "Bool"
            }
        }
        if self.isResult(bt) {
            if mth == "isOk" || mth == "isErr" {
                return "Bool"
            }
            if mth == "value" || mth == "unwrapOr" {
                return self.resultValue(bt)
            }
            if mth == "error" {
                return "String"
            }
        }
        if self.isArray(bt) {
            if mth == "length" {
                return "Int"
            }
            if mth == "get" {
                return self.elementType(bt)
            }
            if mth == "push" || mth == "remove" || mth == "set" || mth == "insert" {
                return "Unit"
            }
            if mth == "join" {
                return "String"
            }
        }
        if self.isMap(bt) {
            if mth == "length" {
                return "Int"
            }
            if mth == "has" {
                return "Bool"
            }
            if mth == "put" {
                return "Unit"
            }
            if mth == "getOr" {
                return self.mapValue(bt)
            }
        }
        if self.isProtocol(bt) {
            return self.protoRet(bt, mth)
        }
        return self.methodRet(bt, mth)
    }

    String methodExpr(String bv, String bt, String mth, AstNode n, Int off) {
        if bt == "AtomicInt" {
            if mth == "load" { return "xrt_atomic_int_load(" + bv + ")" }
            if mth == "store" {
                return "xrt_atomic_int_store(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
            }
            if mth == "cas" {
                return "((xrt_atomic_int_cas(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ") != 0) ? 1 : 0)"
            }
        }
        if bt == "AtomicBool" {
            if mth == "load" { return "xrt_atomic_bool_load(" + bv + ")" }
            if mth == "store" {
                return "xrt_atomic_bool_store(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
            }
            if mth == "cas" {
                return "((xrt_atomic_bool_cas(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ") != 0) ? 1 : 0)"
            }
        }
        if bt == "Bytes" {
            if mth == "length" {
                return "((int64_t)xrt_bytes_len(" + bv + "))"
            }
            if mth == "get" {
                return "((int64_t)xrt_bytes_get(" + bv + ", " + self.expr(n.kids.get(off)) + "))"
            }
            if mth == "slice" {
                return "xrt_bytes_slice(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ")"
            }
            if mth == "set" {
                return "xrt_bytes_set(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ")"
            }
            if mth == "append" {
                return "xrt_bytes_append(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
            }
            if mth == "push" {
                return "xrt_bytes_push(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
            }
            if mth == "toString" {
                return "rt_string_from_c((const char *)xrt_bytes_data(" + bv + "))"
            }
        }
        if bt == "String" {
            if mth == "length" {
                return "((int64_t)" + bv + "->len)"
            }
            if mth == "get" {
                if n.kids.length() > off {
                    return "((int64_t)(unsigned char)" + bv + "->bytes[" + self.expr(n.kids.get(off)) + "])"
                }
                return "0"
            }
            if mth == "indexOf" || mth == "indexOfByte" {
                if n.kids.length() > off {
                    return "xn_str_indexof(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
                }
                return "-1"
            }
            if mth == "substring" {
                if n.kids.length() > off + 1 {
                    return "xn_str_substr(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ")"
                }
                return "rt_string_from_c(\"\")"
            }
            if mth == "charAt" {
                if n.kids.length() > off {
                    return "xn_str_substr(" + bv + ", " + self.expr(n.kids.get(off)) + ", 1)"
                }
                return "rt_string_from_c(\"\")"
            }
            if mth == "trim" {
                return "xn_str_trim(" + bv + ")"
            }
            if mth == "toUpper" || mth == "toLower" {
                String up = "0"
                if mth == "toUpper" {
                    up = "1"
                }
                return "xn_str_case(" + bv + ", " + up + ")"
            }
            if mth == "replace" && n.kids.length() > off + 1 {
                return "xn_str_replace(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ")"
            }
            if mth == "startsWith" {
                if n.kids.length() > off {
                    return "xn_str_startswith(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
                }
                return "0"
            }
            if mth == "endsWith" {
                if n.kids.length() > off {
                    return "xn_str_endswith(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
                }
                return "0"
            }
            if mth == "split" {
                if n.kids.length() > off {
                    return "xn_str_split(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
                }
                return "xn_arr_s_new(4)"
            }
        }
        if self.isSet(bt) {
            if mth == "length" {
                return "((int64_t)" + bv + "->len)"
            }
            if mth == "has" {
                if n.kids.length() > off {
                    return "xn_set_i_has(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
                }
                return "0"
            }
            if mth == "add" {
                if n.kids.length() > off {
                    return "xn_set_i_add(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
                }
                return "0"
            }
        }
        if self.isResult(bt) {
            if mth == "isOk" {
                return "((" + bv + ").ok != 0)"
            }
            if mth == "isErr" {
                return "((" + bv + ").ok == 0)"
            }
            if mth == "value" {
                if self.isGenericResult(bt) {
                    return self.resultValueCExpr(bt, bv)
                }
                return "((" + bv + ").value)"
            }
            if mth == "error" {
                if self.isGenericResult(bt) {
                    return "((" + bv + ").err)"
                }
                return "((" + bv + ").error)"
            }
            if mth == "unwrapOr" {
                String d = "0"
                if n.kids.length() > off {
                    d = self.expr(n.kids.get(off))
                }
                if self.isGenericResult(bt) {
                    return "((" + bv + ").ok ? " + self.resultValueExpr(bt, bv) + " : " + d + ")"
                }
                return "((" + bv + ").ok ? (" + bv + ").value : " + d + ")"
            }
        }
        if self.isArray(bt) {
            if mth == "length" {
                return "((int64_t)" + bv + "->len)"
            }
            if mth == "get" {
                if n.kids.length() > off {
                    return self.arrayGet(bt, bv, self.expr(n.kids.get(off)))
                }
                return "0"
            }
            if mth == "push" {
                if n.kids.length() > off {
                    return self.arrayPush(bt, bv, self.expr(n.kids.get(off)))
                }
                return "0"
            }
            if mth == "set" {
                if n.kids.length() > off + 1 {
                    return self.arrayCName(bt) + "_set(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ")"
                }
                return "0"
            }
            if mth == "insert" {
                if n.kids.length() > off + 1 {
                    return self.arrayCName(bt) + "_insert(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ")"
                }
                return "0"
            }
            if mth == "remove" {
                if n.kids.length() > off {
                    return self.arrayCName(bt) + "_remove(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
                }
                return "0"
            }
            if mth == "join" {
                if n.kids.length() > off {
                    return "xn_arr_s_join(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
                }
                return "rt_string_from_c(\"\")"
            }
        }
        if self.isMap(bt) {
            if mth == "length" {
                return "((int64_t)" + bv + "->len)"
            }
            if mth == "has" && n.kids.length() > off {
                return "xn_map_s_i_has(" + bv + ", " + self.expr(n.kids.get(off)) + ")"
            }
            if mth == "put" && n.kids.length() > off + 1 {
                return "xn_map_s_i_put(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ")"
            }
            if mth == "getOr" && n.kids.length() > off + 1 {
                return "xn_map_s_i_getOr(" + bv + ", " + self.expr(n.kids.get(off)) + ", " + self.expr(n.kids.get(off + 1)) + ")"
            }
        }
        if self.isProtocol(bt) {
            String pb = "xn_proto_" + bt + "_" + mth + "(" + bv
            Int pi = off
            while pi < n.kids.length() {
                pb = pb + ", " + self.expr(n.kids.get(pi))
                pi = pi + 1
            }
            return pb + ")"
        }
        String b = "xn_Cls_" + bt + "_" + mth + "(" + bv
        Int i = off
        while i < n.kids.length() {
            b = b + ", " + self.expr(n.kids.get(i))
            i = i + 1
        }
        return b + ")"
    }

    String fnRet(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" && n.text == name {
                return self.retNode(n).text
            }
            i = i + 1
        }
        return "Any"
    }

    String typeOf(AstNode n) {
        if n.kind == "Int" {
            return "Int"
        }
        if n.kind == "Double" {
            return "Double"
        }
        if n.kind == "String" {
            return "String"
        }
        if n.kind == "Null" {
            return "Null"
        }
        if n.kind == "Bool" {
            return "Bool"
        }
        if n.kind == "Char" {
            return "Char"
        }
        if n.kind == "Lambda" {
            Int li = self.lambdaIndex(n)
            if li >= 0 {
                return self.lambdaTypes.get(li)
            }
            return "Any"
        }
        if n.kind == "Ternary" {
            if n.kids.length() < 3 {
                return "Any"
            }
            return self.typeOf(n.kids.get(1))
        }
        if n.kind == "Cast" {
            return n.text
        }
        if n.kind == "Is" {
            return "Bool"
        }
        if n.kind == "Unary" {
            if n.kids.length() == 0 {
                return "Any"
            }
            if n.text == "!" {
                return "Bool"
            }
            return self.typeOf(n.kids.get(0))
        }
        if n.kind == "ArrayLit" {
            if n.kids.length() == 0 {
                return "Int[]"
            }
            return self.typeOf(n.kids.get(0)) + "[]"
        }
        if n.kind == "MapLit" {
            if n.kids.length() >= 2 {
                return "Map<" + self.typeOf(n.kids.get(0)) + "," + self.typeOf(n.kids.get(1)) + ">"
            }
            return "Map<String,Int>"
        }
        if n.kind == "Index" {
            if n.kids.length() < 2 {
                return "Any"
            }
            return self.elementType(self.typeOf(n.kids.get(0)))
        }
        if n.kind == "Name" {
            if self.isEnumName(n.text) {
                return n.text
            }
            if n.text == "self" && self.curClass != "" {
                return self.curClass
            }
            String vt = self.findVar(n.text)
            if vt != "Any" {
                return vt
            }
            String ft = self.curFieldType(n.text)
            if ft != "Any" {
                return ft
            }
            return self.topFieldType(n.text)
        }
        if n.kind == "New" {
            return n.text
        }
        if n.kind == "Binary" {
            if n.text == "==" || n.text == "!=" || n.text == "<" ||
                n.text == "<=" || n.text == ">" || n.text == ">=" ||
                n.text == "&&" || n.text == "||" {
                return "Bool"
            }
            if n.text == "+" && self.typeOf(n.kids.get(0)) == "String" {
                return "String"
            }
            if self.typeOf(n.kids.get(0)) == "Double" || self.typeOf(n.kids.get(1)) == "Double" {
                return "Double"
            }
            return "Int"
        }
        if n.kind == "Try" {
            if n.kids.length() == 0 {
                return "Any"
            }
            return self.resultValue(self.typeOf(n.kids.get(0)))
        }
        if n.kind == "MethodCall" {
            if n.kids.length() < 1 {
                return "Any"
            }
            return self.methodType(self.typeOf(n.kids.get(0)), n.text, n)
        }
        if n.kind == "Call" {
            if n.text == "readFile" || n.text == "listFiles" {
                return "String"
            }
            if n.text == "diagnoseRaw" || n.text == "exitRaw" || n.text == "resourceExistsRaw" || n.text == "resourceCountRaw" || n.text == "fileExistsRaw" {
                return "Int"
            }
            if n.text == "nowMonoRaw" || n.text == "nowWallRaw" {
                return "Long"
            }
            if n.text == "readResourceTextRaw" || n.text == "platformRaw" || n.text == "str" {
                return "String"
            }
            if n.text == "Set.of" {
                return "Set<Int>"
            }
            if ffiIndex(n.text) >= 0 {
                return ffiRet(n.text)
            }
            if n.text == "Ok" || n.text == "Err" {
                return self.curRet
            }
            if n.text == "print" {
                return "Unit"
            }
            Int fvi = self.varIndex(n.text)
            if fvi >= 0 && self.isFunctionType(self.varTypes.get(fvi)) {
                return self.fnRetType(self.varTypes.get(fvi))
            }
            Int dot = lastDot(n.text)
            if dot >= 0 {
                String base = n.text.substring(0, dot)
                String mth = n.text.substring(dot + 1, n.text.length() - dot - 1)
                String bt = self.pathType(base)
                if bt == "AtomicInt" {
                    if mth == "load" { return "Int" }
                    if mth == "store" { return "Unit" }
                    if mth == "cas" || mth == "compareExchange" { return "Bool" }
                }
                if bt == "AtomicBool" {
                    if mth == "load" { return "Bool" }
                    if mth == "store" { return "Unit" }
                    if mth == "cas" || mth == "compareExchange" { return "Bool" }
                }
                if bt == "Bytes" {
                    if mth == "fromString" {
                        return "Bytes"
                    }
                    if mth == "length" || mth == "get" {
                        return "Int"
                    }
                    if mth == "slice" || mth == "toString" {
                        return "Bytes"
                    }
                    if mth == "set" || mth == "append" || mth == "push" {
                        return "Unit"
                    }
                }
                if bt == "String" {
                    if mth == "length" || mth == "indexOf" || mth == "indexOfByte" || mth == "get" {
                        return "Int"
                    }
                    if mth == "substring" || mth == "charAt" {
                        return "String"
                    }
                    if mth == "trim" || mth == "replace" || mth == "toUpper" || mth == "toLower" {
                        return "String"
                    }
                    if mth == "startsWith" || mth == "endsWith" {
                        return "Bool"
                    }
                    if mth == "split" {
                        return "List<String>"
                    }
                }
                if self.isSet(bt) {
                    if mth == "length" {
                        return "Int"
                    }
                    if mth == "has" {
                        return "Bool"
                    }
                    if mth == "add" {
                        return "Bool"
                    }
                }
                if self.isResult(bt) {
                    if mth == "isOk" || mth == "isErr" {
                        return "Bool"
                    }
                    if mth == "value" || mth == "unwrapOr" {
                        return self.resultValue(bt)
                    }
                    if mth == "error" {
                        return "String"
                    }
                }
                if self.isArray(bt) {
                    if mth == "length" {
                        return "Int"
                    }
                    if mth == "get" {
                        return self.elementType(bt)
                    }
                    if mth == "push" || mth == "remove" {
                        return "Unit"
                    }
                    if mth == "join" {
                        return "String"
                    }
                }
                if self.isMap(bt) {
                    if mth == "length" {
                        return "Int"
                    }
                    if mth == "has" {
                        return "Bool"
                    }
                    if mth == "put" {
                        return "Unit"
                    }
                    if mth == "getOr" {
                        return self.mapValue(bt)
                    }
                }
                if self.isProtocol(bt) {
                    return self.protoRet(bt, mth)
                }
                if self.isClass(bt) {
                    String fty = self.fieldType(bt, mth)
                    if self.isFunctionType(fty) {
                        return self.fnRetType(fty)
                    }
                }
                String mr = self.methodRet(bt, mth)
                if mr != "Any" {
                    return mr
                }
            }
            String fr = self.fnRet(n.text)
            if fr != "Any" {
                return fr
            }
            return "Any"
        }
        if n.kind == "Member" {
            if n.kids.length() == 0 {
                return "Any"
            }
            String bt = self.typeOf(n.kids.get(0))
            if self.isClass(bt) {
                String ft = self.fieldType(bt, n.text)
                if ft != "Any" {
                    return ft
                }
            }
            return "Any"
        }
        return "Any"
    }

    String expr(AstNode n) {
        if n.kind == "Int" {
            return n.text
        }
        if n.kind == "Double" {
            return n.text
        }
        if n.kind == "String" {
            return "rt_string_from_c(" + n.text + ")"
        }
        if n.kind == "Null" {
            return "0"
        }
        if n.kind == "Bool" {
            if n.text == "true" {
                return "1"
            }
            return "0"
        }
        if n.kind == "Char" {
            return n.text
        }
        if n.kind == "Lambda" {
            Int li = self.lambdaIndex(n)
            if li < 0 {
                self.fail("lambda is missing a function type context")
                return "((xn_closure){0, 0})"
            }
            self.ensureLambdaCaptures(li, n)
            if self.lambdaOwners.get(li) == "" && self.curClass != "" {
                self.lambdaOwners.set(li, self.curClass)
            }
            List<String> caps = self.splitCaps(self.lambdaCaptures.get(li))
            List<String> capTypes = self.splitCaps(self.lambdaCaptureTypes.get(li))
            String selfTy = self.findVar("self")
            if self.curClass != "" && selfTy != "Any" && !self.listHas(caps, "self") {
                caps.push("self")
                capTypes.push(selfTy)
                self.lambdaCaptures.set(li, self.joinCaps(caps))
                self.lambdaCaptureTypes.set(li, self.joinCaps(capTypes))
            }
            if caps.length() == 0 {
                return "((xn_closure){0, (void*)" + self.lambdaName(n) + "})"
            }
            String env = self.temp()
            String cl = self.temp()
            String b = "(({ void **" + env + " = (void **)malloc(sizeof(void *) * " + str(caps.length()) + "); "
            Int ci = 0
            while ci < caps.length() {
                String box = self.temp()
                String ct = self.ctype(capTypes.get(ci))
                b = b + "{ " + ct + " *" + box + " = (" + ct + " *)malloc(sizeof(" + ct + ")); *" + box + " = " + caps.get(ci) + "; " + env + "[" + str(ci) + "] = " + box + "; } "
                if self.isGcRefType(capTypes.get(ci)) {
                    b = b + "rt_gc_root_add((void *)" + caps.get(ci) + "); "
                }
                ci = ci + 1
            }
            b = b + "xn_closure " + cl + " = { (void *)" + env + ", (void *)" + self.lambdaName(n) + " }; " + cl + "; }))"
            return b
        }
        if n.kind == "Ternary" {
            if n.kids.length() < 3 {
                return "0"
            }
            return "((" + self.expr(n.kids.get(0)) + ") ? (" + self.expr(n.kids.get(1)) + ") : (" + self.expr(n.kids.get(2)) + "))"
        }
        if n.kind == "Cast" {
            if n.kids.length() == 0 {
                return "0"
            }
            return "((" + self.ctype(n.text) + ")" + self.expr(n.kids.get(0)) + ")"
        }
        if n.kind == "Is" {
            if n.kids.length() == 0 {
                return "0"
            }
            return "1"
        }
        if n.kind == "Unary" {
            if n.kids.length() == 0 {
                return "0"
            }
            return "(" + n.text + self.expr(n.kids.get(0)) + ")"
        }
        if n.kind == "Index" {
            if n.kids.length() < 2 {
                return "0"
            }
            String bt = self.typeOf(n.kids.get(0))
            return self.arrayGet(bt, self.expr(n.kids.get(0)), self.expr(n.kids.get(1)))
        }
        if n.kind == "Name" {
            return self.nameExpr(n.text)
        }
        if n.kind == "New" {
            String b = "xn_Cls_" + n.text + "_new("
            Int ni = 0
            while ni < n.kids.length() {
                if ni > 0 {
                    b = b + ", "
                }
                b = b + self.expr(n.kids.get(ni))
                ni = ni + 1
            }
            return b + ")"
        }
        if n.kind == "Binary" {
            String lt = self.typeOf(n.kids.get(0))
            String rt = self.typeOf(n.kids.get(1))
            String a = self.expr(n.kids.get(0))
            String b = self.expr(n.kids.get(1))
            if n.text == "+" && lt == "String" && rt == "String" {
                return "xn_concat(" + a + ", " + b + ")"
            }
            if lt == "String" && rt == "String" {
                if n.text == "==" {
                    return "xn_str_eq(" + a + ", " + b + ")"
                }
                if n.text == "!=" {
                    return "(!xn_str_eq(" + a + ", " + b + "))"
                }
            }
            return "(" + a + " " + n.text + " " + b + ")"
        }
        if n.kind == "MethodCall" {
            if n.kids.length() < 1 {
                return "0"
            }
            String bv = self.expr(n.kids.get(0))
            String bt = self.typeOf(n.kids.get(0))
            return self.methodExpr(bv, bt, n.text, n, 1)
        }
        if n.kind == "Call" {
            Int fvi = self.varIndex(n.text)
            if fvi >= 0 && self.isFunctionType(self.varTypes.get(fvi)) {
                return self.closureCall(self.varTypes.get(fvi), self.nameExpr(n.text), n)
            }
            Int ffi = ffiIndex(n.text)
            if ffi >= 0 && n.text != "diagnoseRaw" && n.text != "exitRaw" &&
               n.text != "nowMonoRaw" && n.text != "nowWallRaw" &&
               n.text != "resourceExistsRaw" && n.text != "resourceCountRaw" &&
               n.text != "readResourceTextRaw" && n.text != "fileExistsRaw" &&
               n.text != "readFile" && n.text != "listFiles" && n.text != "platformRaw" &&
               n.text != "readFileTextRaw" && n.text != "readFileTextError" {
                if self.ffiEntryOk(ffi) {
                    String wb = "xn_ffi_" + n.text + "("
                    Int epi = self.ffiErrParamIndex(ffi)
                    Int fi = 0
                    while fi < n.kids.length() {
                        if fi > 0 {
                            wb = wb + ", "
                        }
                        String av = self.expr(n.kids.get(fi))
                        if fi == epi {
                            av = "&" + av
                        }
                        wb = wb + av
                        fi = fi + 1
                    }
                    return wb + ")"
                }
                String b = ffiCName(n.text) + "("
                Int fi = 0
                while fi < n.kids.length() {
                    if fi > 0 {
                        b = b + ", "
                    }
                    b = b + self.expr(n.kids.get(fi))
                    fi = fi + 1
                }
                return b + ")"
            }
            if n.text == "AtomicInt" || n.text == "AtomicBool" {
                String av = "0"
                if n.kids.length() > 0 { av = self.expr(n.kids.get(0)) }
                if n.text == "AtomicInt" { return "xrt_atomic_int_new((int64_t)(" + av + "))" }
                return "xrt_atomic_bool_new((int)(" + av + "))"
            }
            if n.text == "listFiles" {
                String a = "rt_string_from_c(\"\")"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                return "rt_string_from_c(mini_list_x(" + a + "->bytes, " + a + "->len))"
            }
            if n.text == "readFile" {
                String a = "rt_string_from_c(\"\")"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                return "rt_string_from_c(mini_read_file(" + a + "->bytes, " + a + "->len))"
            }
            if n.text == "diagnoseRaw" {
                String a = "rt_string_from_c(\"\")"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                return "xdkc_diagnose_rc(" + a + "->bytes, " + a + "->len)"
            }
            if n.text == "exitRaw" {
                String a = "0"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                return "xdkc_exit_rc((int32_t)" + a + ")"
            }
            if n.text == "nowMonoRaw" {
                return "xdkc_now_mono_ms()"
            }
            if n.text == "nowWallRaw" {
                return "xdkc_now_wall_ms()"
            }
            if n.text == "resourceExistsRaw" {
                String a = "rt_string_from_c(\"\")"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                return "xdkc_p_resource_exists(" + a + "->bytes, " + a + "->len)"
            }
            if n.text == "readResourceTextRaw" {
                String a = "rt_string_from_c(\"\")"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                return "rt_string_from_c(xdkc_p_read_resource_text(" + a + "->bytes, " + a + "->len))"
            }
            if n.text == "resourceCountRaw" {
                return "xdkc_p_resource_count()"
            }
            if n.text == "readFileTextRaw" {
                String a = "rt_string_from_c(\"\")"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                return "rt_string_from_c(xdkc_read_file_text(" + a + "->bytes, " + a + "->len))"
            }
            if n.text == "readFileTextError" {
                return "xdkc_read_file_text_error()"
            }
            if n.text == "fileExistsRaw" {
                String a = "rt_string_from_c(\"\")"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                return "mini_file_exists(" + a + "->bytes, " + a + "->len)"
            }
            if n.text == "platformRaw" {
                return "mini_platform()"
            }
            if n.text == "Ok" {
                String a = "0"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                if self.isGenericResult(self.curRet) {
                    return "(xn_Result){ .ok = 1, " + self.resultInitField(self.curRet, a) + " }"
                }
                return "(" + self.ctype(self.curRet) + "){1, " + a + ", 0}"
            }
            if n.text == "Err" {
                String a = "rt_string_from_c(\"\")"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
                }
                if self.isGenericResult(self.curRet) {
                    return "(xn_Result){ .ok = 0, .err = (void *)(" + a + ") }"
                }
                return "(" + self.ctype(self.curRet) + "){0, 0, " + a + "}"
            }
            if n.text == "print" {
                String at = "Any"
                if n.kids.length() > 0 {
                    at = self.typeOf(n.kids.get(0))
                }
                String av = "0"
                if n.kids.length() > 0 {
                    av = self.expr(n.kids.get(0))
                }
                if at == "Int" || at == "Long" || at == "Int64" {
                    return "xn_print_int(" + av + ")"
                }
                if at == "Double" {
                    return "xn_print_double(" + av + ")"
                }
                if at == "Bool" {
                    return "xn_print_bool(" + av + ")"
                }
                if at == "Char" {
                    return "xn_print_str(xn_str_char(" + av + "))"
                }
                return "xn_print_str(" + av + ")"
            }
            if n.text == "str" {
                if n.kids.length() == 0 {
                    return "rt_string_from_c(\"\")"
                }
                String at = self.typeOf(n.kids.get(0))
                String av = self.expr(n.kids.get(0))
                if at == "String" {
                    return av
                }
                if at == "Double" {
                    return "xn_str_double(" + av + ")"
                }
                if at == "Bool" {
                    return "xn_str_bool(" + av + ")"
                }
                if at == "Char" {
                    return "xn_str_char(" + av + ")"
                }
                return "xn_str_int(" + av + ")"
            }
            Int dot = lastDot(n.text)
            if dot >= 0 {
                String base = n.text.substring(0, dot)
                String mth = n.text.substring(dot + 1, n.text.length() - dot - 1)
                String bv = self.pathExpr(base)
                String bt = self.pathType(base)
                if bt == "AtomicInt" {
                    if mth == "load" { return "xrt_atomic_int_load(" + bv + ")" }
                    if mth == "store" {
                        return "xrt_atomic_int_store(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                    }
                    if mth == "cas" || mth == "compareExchange" {
                        return "((xrt_atomic_int_cas(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ") != 0) ? 1 : 0)"
                    }
                }
                if bt == "AtomicBool" {
                    if mth == "load" { return "xrt_atomic_bool_load(" + bv + ")" }
                    if mth == "store" {
                        return "xrt_atomic_bool_store(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                    }
                    if mth == "cas" || mth == "compareExchange" {
                        return "((xrt_atomic_bool_cas(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ") != 0) ? 1 : 0)"
                    }
                }
                if bt == "Bytes" {
                    if mth == "fromString" {
                        if n.kids.length() > 0 {
                            return "xrt_bytes_from_string(" + self.expr(n.kids.get(0)) + "->bytes, " + self.expr(n.kids.get(0)) + "->len)"
                        }
                        return "xrt_bytes_new()"
                    }
                    if mth == "length" {
                        return "((int64_t)xrt_bytes_len(" + bv + "))"
                    }
                    if mth == "get" {
                        return "((int64_t)xrt_bytes_get(" + bv + ", " + self.expr(n.kids.get(0)) + "))"
                    }
                    if mth == "slice" {
                        return "xrt_bytes_slice(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ")"
                    }
                    if mth == "set" {
                        return "xrt_bytes_set(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ")"
                    }
                    if mth == "append" {
                        return "xrt_bytes_append(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                    }
                    if mth == "push" {
                        return "xrt_bytes_push(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                    }
                    if mth == "toString" {
                        return "rt_string_from_c((const char *)xrt_bytes_data(" + bv + "))"
                    }
                }
                if bt == "String" {
                    if mth == "length" {
                        return "((int64_t)" + bv + "->len)"
                    }
                    if mth == "get" {
                        if n.kids.length() > 0 {
                            return "((int64_t)(unsigned char)" + bv + "->bytes[" + self.expr(n.kids.get(0)) + "])"
                        }
                        return "0"
                    }
                    if mth == "indexOf" || mth == "indexOfByte" {
                        if n.kids.length() > 0 {
                            return "xn_str_indexof(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                        }
                        return "-1"
                    }
                    if mth == "substring" {
                        if n.kids.length() >= 2 {
                            return "xn_str_substr(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ")"
                        }
                        return "rt_string_from_c(\"\")"
                    }
                    if mth == "charAt" {
                        if n.kids.length() > 0 {
                            return "xn_str_substr(" + bv + ", " + self.expr(n.kids.get(0)) + ", 1)"
                        }
                        return "rt_string_from_c(\"\")"
                    }
                    if mth == "trim" {
                        return "xn_str_trim(" + bv + ")"
                    }
                    if mth == "toUpper" || mth == "toLower" {
                        String up = "0"
                        if mth == "toUpper" {
                            up = "1"
                        }
                        return "xn_str_case(" + bv + ", " + up + ")"
                    }
                    if mth == "replace" && n.kids.length() > 1 {
                        return "xn_str_replace(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ")"
                    }
                    if mth == "startsWith" {
                        if n.kids.length() > 0 {
                            return "xn_str_startswith(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                        }
                        return "0"
                    }
                    if mth == "endsWith" {
                        if n.kids.length() > 0 {
                            return "xn_str_endswith(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                        }
                        return "0"
                    }
                    if mth == "split" {
                        if n.kids.length() > 0 {
                            return "xn_str_split(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                        }
                        return "xn_arr_s_new(4)"
                    }
                }
                if self.isSet(bt) {
                    if mth == "length" {
                        return "((int64_t)" + bv + "->len)"
                    }
                    if mth == "has" {
                        if n.kids.length() > 0 {
                            return "xn_set_i_has(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                        }
                        return "0"
                    }
                    if mth == "add" {
                        if n.kids.length() > 0 {
                            return "xn_set_i_add(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                        }
                        return "0"
                    }
                }
                if self.isResult(bt) {
                    if mth == "isOk" {
                        return "((" + bv + ").ok != 0)"
                    }
                    if mth == "isErr" {
                        return "((" + bv + ").ok == 0)"
                    }
                    if mth == "value" {
                        if self.isGenericResult(bt) {
                            return self.resultValueCExpr(bt, bv)
                        }
                        return "((" + bv + ").value)"
                    }
                    if mth == "error" {
                        if self.isGenericResult(bt) {
                            return "((" + bv + ").err)"
                        }
                        return "((" + bv + ").error)"
                    }
                    if mth == "unwrapOr" {
                        String d = "0"
                        if n.kids.length() > 0 {
                            d = self.expr(n.kids.get(0))
                        }
                        if self.isGenericResult(bt) {
                            return "((" + bv + ").ok ? " + self.resultValueExpr(bt, bv) + " : " + d + ")"
                        }
                        return "((" + bv + ").ok ? (" + bv + ").value : " + d + ")"
                    }
                }
                if self.isArray(bt) {
                    if mth == "length" {
                        return "((int64_t)" + bv + "->len)"
                    }
                    if mth == "get" {
                        if n.kids.length() > 0 {
                            return self.arrayGet(bt, bv, self.expr(n.kids.get(0)))
                        }
                        return "0"
                    }
                    if mth == "push" {
                        if n.kids.length() > 0 {
                            return self.arrayPush(bt, bv, self.expr(n.kids.get(0)))
                        }
                        return "0"
                    }
                    if mth == "set" {
                        if n.kids.length() > 1 {
                            return self.arrayCName(bt) + "_set(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ")"
                        }
                        return "0"
                    }
                    if mth == "insert" {
                        if n.kids.length() > 1 {
                            return self.arrayCName(bt) + "_insert(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ")"
                        }
                        return "0"
                    }
                    if mth == "remove" {
                        if n.kids.length() > 0 {
                            return self.arrayCName(bt) + "_remove(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                        }
                        return "0"
                    }
                    if mth == "join" {
                        if n.kids.length() > 0 {
                            return "xn_arr_s_join(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                        }
                        return "rt_string_from_c(\"\")"
                    }
                }
                if self.isMap(bt) {
                    if mth == "length" {
                        return "((int64_t)" + bv + "->len)"
                    }
                    if mth == "has" {
                        if n.kids.length() > 0 {
                            return "xn_map_s_i_has(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
                        }
                        return "0"
                    }
                    if mth == "put" {
                        if n.kids.length() >= 2 {
                            return "xn_map_s_i_put(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ")"
                        }
                        return "0"
                    }
                    if mth == "getOr" {
                        if n.kids.length() >= 2 {
                            return "xn_map_s_i_getOr(" + bv + ", " + self.expr(n.kids.get(0)) + ", " + self.expr(n.kids.get(1)) + ")"
                        }
                        return "0"
                    }
                }
                if self.isClass(bt) {
                    String fty = self.fieldType(bt, mth)
                    if self.isFunctionType(fty) {
                        return self.closureCall(fty, bv + "->" + mth, n)
                    }
                }
                if self.isProtocol(bt) {
                    String pb = "xn_proto_" + bt + "_" + mth + "(" + bv
                    Int pi = 0
                    while pi < n.kids.length() {
                        pb = pb + ", " + self.expr(n.kids.get(pi))
                        pi = pi + 1
                    }
                    return pb + ")"
                }
                String b = "xn_Cls_" + bt + "_" + mth + "("
                if self.isClass(bt) && !self.isStaticMethod(bt, mth) {
                    b = b + bv
                }
                Int di = 0
                Bool firstArg = !(self.isClass(bt) && !self.isStaticMethod(bt, mth))
                if self.isClass(bt) && self.isStaticMethod(bt, mth) {
                    firstArg = true
                }
                while di < n.kids.length() {
                    if firstArg {
                        firstArg = false
                    } else {
                        b = b + ", "
                    }
                    b = b + self.expr(n.kids.get(di))
                    di = di + 1
                }
                return b + ")"
            }
            String b = "xn_" + n.text + "("
            Int i = 0
            while i < n.kids.length() {
                if i > 0 {
                    b = b + ", "
                }
                b = b + self.expr(n.kids.get(i))
                i = i + 1
            }
            return b + ")"
        }
        if n.kind == "Member" {
            if n.kids.length() == 0 {
                return "0"
            }
            AstNode mb = n.kids.get(0)
            if mb.kind == "Name" && self.isDataEnum(mb.text) {
                return "xn_enum_" + mb.text + "_" + n.text
            }
            if mb.kind == "Name" && self.isEnumName(mb.text) {
                return "xn_enum_" + mb.text + "_" + n.text
            }
            String bt = self.typeOf(n.kids.get(0))
            String b = self.expr(n.kids.get(0))
            if self.isClass(bt) || (n.kids.get(0).kind == "Name" && n.kids.get(0).text == "self") {
                return b + "->" + n.text
            }
            return b + "." + n.text
        }
        self.fail("unsupported expression: " + n.kind)
        return "0"
    }

    Void local(AstNode st, String indent) {
        List<String> parts = st.text.split(" ")
        if parts.length() < 2 {
            self.fail("malformed local")
            return
        }
        String ty = parts.get(0)
        String name = parts.get(1)
        if self.isFunctionType(ty) {
            AstNode initNode = new AstNode("None", "", st.line, st.col)
            if st.kids.length() > 0 {
                initNode = st.kids.get(0)
            }
            if initNode.kind == "Lambda" {
                Int li = self.lambdaIndex(initNode)
                self.ensureLambdaCaptures(li, initNode)
                List<String> caps = []
                List<String> capTypes = []
                if li >= 0 {
                    caps = self.splitCaps(self.lambdaCaptures.get(li))
                    capTypes = self.splitCaps(self.lambdaCaptureTypes.get(li))
                    if self.lambdaOwners.get(li) == "" && self.curClass != "" {
                        self.lambdaOwners.set(li, self.curClass)
                    }
                }
                String selfTy = self.findVar("self")
                if self.curClass != "" && selfTy != "Any" && !self.listHas(caps, "self") {
                    caps.push("self")
                    capTypes.push(selfTy)
                    if li >= 0 {
                        self.lambdaCaptures.set(li, self.joinCaps(caps))
                        self.lambdaCaptureTypes.set(li, self.joinCaps(capTypes))
                    }
                }
                Bool selfCap = self.containsVarUse(initNode, name)
                if selfCap {
                    List<String> keepNames = []
                    List<String> keepTypes = []
                    Int ki = 0
                    while ki < caps.length() {
                        if caps.get(ki) != name {
                            keepNames.push(caps.get(ki))
                            keepTypes.push(capTypes.get(ki))
                        }
                        ki = ki + 1
                    }
                    caps = keepNames
                    capTypes = keepTypes
                    caps.push(name)
                    capTypes.push(ty)
                    if li >= 0 {
                        self.lambdaCaptures.set(li, self.joinCaps(caps))
                        self.lambdaCaptureTypes.set(li, self.joinCaps(capTypes))
                    }
                }
                Int selfIdx = -1
                Int sci = 0
                while sci < caps.length() {
                    if caps.get(sci) == name {
                        selfIdx = sci
                    }
                    sci = sci + 1
                }
                self.emit(indent + self.fnPtrDecl(ty, name) + ";")
                String env = name + "_env"
                if caps.length() > 0 {
                    self.emit(indent + "void **" + env + " = (void **)malloc(sizeof(void *) * " + str(caps.length()) + ");")
                    Int ci = 0
                    while ci < caps.length() {
                        if ci != selfIdx {
                            String box = self.temp()
                            String ct = self.ctype(capTypes.get(ci))
                            self.emit(indent + "{ " + ct + " *" + box + " = (" + ct + " *)malloc(sizeof(" + ct + ")); *" + box + " = " + caps.get(ci) + "; " + env + "[" + str(ci) + "] = " + box + "; }")
                            if self.isGcRefType(capTypes.get(ci)) {
                                self.emit(indent + "rt_gc_root_add((void *)" + caps.get(ci) + ");")
                            }
                        }
                        ci = ci + 1
                    }
                    self.emit(indent + name + ".env = (void *)" + env + ";")
                } else {
                    self.emit(indent + name + ".env = 0;")
                }
                self.emit(indent + name + ".fn = (void *)" + self.lambdaName(initNode) + ";")
                if selfIdx >= 0 {
                    String selfBox = self.temp()
                    String selfCt = self.ctype(ty)
                    self.emit(indent + "{ " + selfCt + " *" + selfBox + " = (" + selfCt + " *)malloc(sizeof(" + selfCt + ")); *" + selfBox + " = " + name + "; " + env + "[" + str(selfIdx) + "] = " + selfBox + "; }")
                }
            } else {
                String init = "{0, 0}"
                if st.kids.length() > 0 {
                    init = self.expr(initNode)
                }
                self.emit(indent + self.fnPtrDecl(ty, name) + " = " + init + ";")
            }
            self.addVar(ty, name)
            return
        }
        if self.isSet(ty) && st.kids.length() > 0 && st.kids.get(0).kind == "ArrayLit" {
            AstNode lit = st.kids.get(0)
            self.emit(indent + "xn_set_i *" + name + " = xn_set_i_new();")
            Int si = 0
            while si < lit.kids.length() {
                self.emit(indent + "xn_set_i_add(" + name + ", " + self.expr(lit.kids.get(si)) + ");")
                si = si + 1
            }
            self.addVar(ty, name)
            return
        }
        if self.isSet(ty) && st.kids.length() > 0 && st.kids.get(0).kind == "Call" && st.kids.get(0).text == "Set.of" {
            AstNode call = st.kids.get(0)
            self.emit(indent + "xn_set_i *" + name + " = xn_set_i_new();")
            Int si = 0
            while si < call.kids.length() {
                self.emit(indent + "xn_set_i_add(" + name + ", " + self.expr(call.kids.get(si)) + ");")
                si = si + 1
            }
            self.addVar(ty, name)
            return
        }
        if st.kids.length() > 0 && st.kids.get(0).kind == "Try" {
            AstNode tr = st.kids.get(0)
            if tr.kids.length() > 0 {
                String rt = self.typeOf(tr.kids.get(0))
                String tv = self.temp()
                self.emit(indent + self.ctype(rt) + " " + tv + " = " + self.expr(tr.kids.get(0)) + ";")
                self.emit(indent + "if (!" + tv + ".ok) {")
                self.emitDefers(indent + "  ", true)
                self.emit(indent + "  return " + tv + ";")
                self.emit(indent + "}")
                self.emit(indent + self.ctype(ty) + " " + name + " = " + tv + ".value;")
                self.addVar(ty, name)
                return
            }
        }
        if ty == "Map<String,Int>" && st.kids.length() > 0 && st.kids.get(0).kind == "MapLit" {
            AstNode lit = st.kids.get(0)
            self.emit(indent + "xn_map_s_i *" + name + " = xn_map_s_i_new(4);")
            Int mi = 0
            while mi + 1 < lit.kids.length() {
                self.emit(indent + "xn_map_s_i_put(" + name + ", " + self.expr(lit.kids.get(mi)) + ", " + self.expr(lit.kids.get(mi + 1)) + ");")
                mi = mi + 2
            }
            self.addVar(ty, name)
            return
        }
        if self.isArray(ty) && st.kids.length() > 0 && st.kids.get(0).kind == "ArrayLit" {
            AstNode lit = st.kids.get(0)
            String ac = self.arrayCName(ty)
            self.emit(indent + ac + " *" + name + " = " + ac + "_new(" + str(lit.kids.length()) + ");")
            Int ai = 0
            while ai < lit.kids.length() {
                self.emit(indent + ac + "_push(" + name + ", " + self.expr(lit.kids.get(ai)) + ");")
                ai = ai + 1
            }
            self.addVar(ty, name)
            return
        }
        String init = "0"
        if st.kids.length() > 0 {
            init = self.expr(st.kids.get(0))
        }
        self.emit(indent + self.ctype(ty) + " " + name + " = " + init + ";")
        self.addVar(ty, name)
    }

    Void stmt(AstNode st, String indent) {
        if st.kind == "Goto" {
            self.emit(indent + "goto " + st.text + ";")
            return
        }
        if st.kind == "Label" {
            self.emit(indent + st.text + ": ;")
            if st.kids.length() > 0 {
                self.stmt(st.kids.get(0), indent)
            }
            return
        }
        if st.kind == "Break" {
            if self.breakTargets.length() > 0 {
                String target = self.breakTargets.get(self.breakTargets.length() - 1)
                if target == "loop" {
                    self.emit(indent + "break;")
                } else {
                    self.emit(indent + "goto " + target + ";")
                }
            } else {
                self.emit(indent + "break;")
            }
            return
        }
        if st.kind == "Continue" {
            self.emit(indent + "continue;")
            return
        }
        if st.kind == "Throw" {
            if st.kids.length() > 0 {
                String v = self.expr(st.kids.get(0))
                self.emit(indent + "rt_fatal(" + v + "->bytes);")
            } else {
                self.emit(indent + "rt_fatal(\"throw\");")
            }
            self.emit(indent + "abort();")
            return
        }
        if st.kind == "Assign" {
            if st.kids.length() >= 2 {
                String lhs = self.expr(st.kids.get(0))
                AstNode rv = st.kids.get(1)
                AstNode lv = st.kids.get(0)
                if lv.kind == "Index" && lv.kids.length() >= 2 {
                    String at = self.typeOf(lv.kids.get(0))
                    if self.isArray(at) {
                        String ac = self.arrayCName(at)
                        self.emit(indent + ac + "_set(" + self.expr(lv.kids.get(0)) + ", " + self.expr(lv.kids.get(1)) + ", " + self.expr(rv) + ");")
                        return
                    }
                }
                if rv.kind == "ArrayLit" {
                    String lt = self.typeOf(st.kids.get(0))
                    if self.isArray(lt) {
                        String ac = self.arrayCName(lt)
                        self.emit(indent + lhs + " = " + ac + "_new(" + str(rv.kids.length()) + ");")
                        Int ai = 0
                        while ai < rv.kids.length() {
                            self.emit(indent + ac + "_push(" + lhs + ", " + self.expr(rv.kids.get(ai)) + ");")
                            ai = ai + 1
                        }
                        return
                    }
                }
                self.emit(indent + lhs + " = " + self.expr(rv) + ";")
            }
            return
        }
        if st.kind == "Switch" {
            if st.kids.length() < 2 {
                self.fail("malformed switch")
                return
            }
            String vt = self.typeOf(st.kids.get(0))
            String sv = self.temp()
            String swEnd = self.temp()
            self.breakTargets.push(swEnd)
            self.emit(indent + "{")
            self.emit(indent + "  " + self.ctype(vt) + " " + sv + " = " + self.expr(st.kids.get(0)) + ";")
            Int si = 1
            Bool hasDefault = false
            Bool first = true
            while si < st.kids.length() {
                AstNode clause = st.kids.get(si)
                if clause.kind == "Case" && clause.kids.length() >= 2 {
                    String cond = sv + " == " + self.expr(clause.kids.get(0))
                    if vt == "String" {
                        cond = "xn_str_eq(" + sv + ", " + self.expr(clause.kids.get(0)) + ")"
                    }
                    if first {
                        self.emit(indent + "  if (" + cond + ") {")
                        first = false
                    } else {
                        self.emit(indent + "  else if (" + cond + ") {")
                    }
                    self.blockBody(clause.kids.get(1), indent + "    ")
                    self.emit(indent + "  }")
                } else if clause.kind == "Default" {
                    hasDefault = true
                    if first {
                        self.emit(indent + "  if (1) {")
                    } else {
                        self.emit(indent + "  else {")
                    }
                    if clause.kids.length() > 0 {
                        self.blockBody(clause.kids.get(0), indent + "    ")
                    }
                    self.emit(indent + "  }")
                }
                si = si + 1
            }
            if !hasDefault && first {
                self.emit(indent + "  {}")
            }
            self.emit(indent + "  " + swEnd + ": ;")
            self.emit(indent + "}")
            self.breakTargets.remove(self.breakTargets.length() - 1)
            return
        }
        if st.kind == "ForRange" {
            if st.kids.length() < 3 {
                self.fail("malformed for-range")
                return
            }
            String sstart = self.temp()
            String send = self.temp()
            String svar = st.text.substring(st.text.indexOf(" ") + 1, st.text.length() - st.text.indexOf(" ") - 1)
            Bool inclusive = st.text.startsWith("...")
            self.emit(indent + "{")
            self.emit(indent + "  int64_t " + sstart + " = " + self.expr(st.kids.get(0)) + ";")
            self.emit(indent + "  int64_t " + send + " = " + self.expr(st.kids.get(1)) + ";")
            String cmp = inclusive ? " <= " : " < "
            self.emit(indent + "  for (int64_t " + svar + " = " + sstart + "; " + svar + cmp + send + "; " + svar + "++) {")
            Int mark = self.vars.length()
            self.addVar("Int", svar)
            self.breakTargets.push("loop")
            self.blockBody(st.kids.get(2), indent + "    ")
            self.breakTargets.remove(self.breakTargets.length() - 1)
            self.popTo(mark)
            self.emit(indent + "  }")
            self.emit(indent + "}")
            return
        }
        if st.kind == "ForIn" {
            if st.kids.length() < 2 {
                self.fail("malformed for-in")
                return
            }
            String arr = self.expr(st.kids.get(0))
            String et = self.elementType(self.typeOf(st.kids.get(0)))
            if et == "Any" {
                self.fail("for-in expects array")
                return
            }
            String it = self.temp()
            String ix = self.temp()
            String aty = self.typeOf(st.kids.get(0))
            String ac = self.arrayCName(aty)
            self.emit(indent + "{")
            self.emit(indent + "  " + ac + " *" + it + " = " + arr + ";")
            self.emit(indent + "  for (size_t " + ix + " = 0; " + ix + " < " + it + "->len; " + ix + "++) {")
            self.emit(indent + "    " + self.ctype(et) + " " + st.text + " = " + self.arrayGet(aty, it, ix) + ";")
            Int mark = self.vars.length()
            self.addVar(et, st.text)
            self.breakTargets.push("loop")
            self.blockBody(st.kids.get(1), indent + "    ")
            self.breakTargets.remove(self.breakTargets.length() - 1)
            self.popTo(mark)
            self.emit(indent + "  }")
            self.emit(indent + "}")
            return
        }
        if st.kind == "Local" {
            self.local(st, indent)
            return
        }
        if st.kind == "Return" {
            Bool err = false
            if st.kids.length() > 0 {
                AstNode rv = st.kids.get(0)
                if rv.kind == "Call" && rv.text == "Err" {
                    err = true
                }
            }
            self.emitDefers(indent, err)
            if st.kids.length() == 0 {
                self.emit(indent + "return;")
            } else {
                self.emit(indent + "return " + self.expr(st.kids.get(0)) + ";")
            }
            return
        }
        if st.kind == "ExprStmt" {
            if st.kids.length() > 0 {
                self.emit(indent + self.expr(st.kids.get(0)) + ";")
            }
            return
        }
        if st.kind == "If" {
            if st.kids.length() < 2 {
                self.fail("malformed if")
                return
            }
            self.emit(indent + "if (" + self.expr(st.kids.get(0)) + ") {")
            self.blockBody(st.kids.get(1), indent + "  ")
            self.emit(indent + "}")
            if st.kids.length() >= 3 {
                self.emit(indent + "else {")
                self.blockBody(st.kids.get(2), indent + "  ")
                self.emit(indent + "}")
            }
            return
        }
        if st.kind == "DoWhile" {
            if st.kids.length() < 2 {
                self.fail("malformed do-while")
                return
            }
            self.emit(indent + "do {")
            self.breakTargets.push("loop")
            self.blockBody(st.kids.get(0), indent + "  ")
            self.breakTargets.remove(self.breakTargets.length() - 1)
            self.emit(indent + "} while (" + self.expr(st.kids.get(1)) + ");")
            return
        }
        if st.kind == "While" {
            if st.kids.length() < 2 {
                self.fail("malformed while")
                return
            }
            self.emit(indent + "while (" + self.expr(st.kids.get(0)) + ") {")
            self.breakTargets.push("loop")
            self.blockBody(st.kids.get(1), indent + "  ")
            self.breakTargets.remove(self.breakTargets.length() - 1)
            self.emit(indent + "}")
            return
        }
        if st.kind == "Block" {
            self.emit(indent + "{")
            self.blockBody(st, indent + "  ")
            self.emit(indent + "}")
            return
        }
        self.fail("unsupported statement: " + st.kind)
    }

    Void emitDefers(String indent, Bool includeErr) {
        Int i = self.defers.length() - 1
        while i >= 0 {
            String isErr = self.deferErrs.get(i)
            if isErr != "errdefer" || includeErr {
                self.stmt(self.defers.get(i).kids.get(0), indent)
            }
            i = i - 1
        }
    }

    Void blockBody(AstNode block, String indent) {
        Int mark = self.vars.length()
        Int dmark = self.defers.length()
        Int i = 0
        while i < block.kids.length() && !self.hasError() {
            AstNode st = block.kids.get(i)
            if st.kind == "Defer" {
                self.defers.push(st)
                self.deferErrs.push(st.text)
            } else {
                self.stmt(st, indent)
            }
            i = i + 1
        }
        Int j = self.defers.length() - 1
        while j >= dmark {
            AstNode d = self.defers.get(j)
            self.stmt(d.kids.get(0), indent)
            j = j - 1
        }
        while self.defers.length() > dmark {
            self.defers.remove(self.defers.length() - 1)
            self.deferErrs.remove(self.deferErrs.length() - 1)
        }
        self.popTo(mark)
    }

    Bool methodStatic(AstNode m) {
        Int i = 0
        while i < m.kids.length() {
            if m.kids.get(i).kind == "Static" {
                return true
            }
            i = i + 1
        }
        return false
    }

    String methodSig(AstNode m, String cls) {
        String ret = self.ctype(self.retNode(m).text)
        Bool st = self.methodStatic(m)
        String sig = "static " + ret + " xn_Cls_" + cls + "_" + m.text + "("
        List<AstNode> ps = self.paramsOf(m)
        if st {
            if ps.length() == 0 {
                sig = sig + "void"
            }
        } else {
            sig = sig + "xn_Cls_" + cls + " *self"
        }
        Int i = 0
        while i < ps.length() {
            List<String> parts = ps.get(i).text.split(" ")
            if parts.length() >= 2 {
                if !st || i > 0 {
                    sig = sig + ", "
                }
                sig = sig + self.ctype(parts.get(0)) + " " + parts.get(1)
            }
            i = i + 1
        }
        return sig + ")"
    }

    Void method(AstNode m, String cls) {
        self.curClass = cls
        self.curRet = self.retNode(m).text
        String sig = self.methodSig(m, cls) + " {"
        self.emit(sig)
        self.popTo(0)
        if !self.methodStatic(m) {
            self.addVar(cls, "self")
        }
        List<AstNode> ps = self.paramsOf(m)
        Int pi = 0
        while pi < ps.length() {
            List<String> pps = ps.get(pi).text.split(" ")
            if pps.length() >= 2 {
                self.addVar(pps.get(0), pps.get(1))
            }
            pi = pi + 1
        }
        Int i = 0
        while i < m.kids.length() {
            AstNode k = m.kids.get(i)
            if k.kind == "Block" {
                self.blockBody(k, "  ")
            }
            i = i + 1
        }
        self.emit("}")
        self.emit("")
        self.curClass = ""
        self.curRet = "Int"
    }

    AstNode ctorOf(AstNode cls) {
        Int i = 0
        while i < cls.kids.length() {
            AstNode k = cls.kids.get(i)
            if k.kind == "Ctor" {
                return k
            }
            i = i + 1
        }
        return new AstNode("None", "", cls.line, cls.col)
    }

    Void genClass(AstNode cls) {
        String cn = cls.text
        self.emit("struct xn_Cls_" + cn + " {")
        self.emit("  rt_header hdr;")
        Int i = 0
        while i < cls.kids.length() {
            AstNode k = cls.kids.get(i)
            if k.kind == "Field" {
                List<String> parts = k.text.split(" ")
                if parts.length() >= 2 {
                    self.emit("  " + self.ctype(parts.get(0)) + " " + parts.get(1) + ";")
                }
            }
            i = i + 1
        }
        self.emit("};")
        self.emit("")
        self.emit("static const rt_type RT_TYPE_XN_" + cn + " = { \"" + cn + "\", sizeof(xn_Cls_" + cn + "), NULL, NULL };")
        self.emit("")
        AstNode ctor = self.ctorOf(cls)
        String csig = "static xn_Cls_" + cn + " *xn_Cls_" + cn + "_new("
        List<AstNode> cps = self.paramsOf(ctor)
        if cps.length() == 0 {
            csig = csig + "void"
        } else {
            Int ci = 0
            while ci < cps.length() {
                if ci > 0 {
                    csig = csig + ", "
                }
                List<String> cpp = cps.get(ci).text.split(" ")
                if cpp.length() >= 2 {
                    csig = csig + self.ctype(cpp.get(0)) + " " + cpp.get(1)
                }
                ci = ci + 1
            }
        }
        self.emit(csig + ") {")
        self.emit("  xn_Cls_" + cn + " *xn_obj = (xn_Cls_" + cn + " *)rt_gc_new(&RT_TYPE_XN_" + cn + ");")
        self.emit("  memset((char *)xn_obj + sizeof(rt_header), 0, sizeof(xn_Cls_" + cn + ") - sizeof(rt_header));")
        self.curClass = cn
        i = 0
        while i < cls.kids.length() {
            AstNode k = cls.kids.get(i)
            if k.kind == "Field" {
                List<String> parts = k.text.split(" ")
                if parts.length() >= 2 {
                    String ty = parts.get(0)
                    String fn = parts.get(1)
                    String init = "0"
                    if ty == "String" {
                        init = "rt_string_from_c(\"\")"
                    }
                    if self.isFunctionType(ty) {
                        init = "(xn_closure){0, 0}"
                    }
                    if self.isArray(ty) {
                        init = self.arrayNew(ty, 4)
                    }
                    if k.kids.length() > 0 {
                        if self.isArray(ty) && k.kids.get(0).kind == "ArrayLit" {
                            AstNode lit = k.kids.get(0)
                            init = self.arrayNew(ty, lit.kids.length())
                        } else {
                            init = self.expr(k.kids.get(0))
                        }
                    }
                    self.emit("  xn_obj->" + fn + " = " + init + ";")
                }
            }
            i = i + 1
        }
        if ctor.kind == "Ctor" {
            self.curClass = cn
            self.emit("  xn_Cls_" + cn + " *self = xn_obj;")
            self.popTo(0)
            self.addVar(cn, "self")
            Int pi = 0
            while pi < cps.length() {
                List<String> cpp = cps.get(pi).text.split(" ")
                if cpp.length() >= 2 {
                    self.addVar(cpp.get(0), cpp.get(1))
                }
                pi = pi + 1
            }
            Int bi = 0
            while bi < ctor.kids.length() {
                AstNode ck = ctor.kids.get(bi)
                if ck.kind == "Block" {
                    self.blockBody(ck, "  ")
                }
                bi = bi + 1
            }
            self.popTo(0)
        }
        self.curClass = ""
        self.emit("  return xn_obj;")
        self.emit("}")
        self.emit("")
        i = 0
        while i < cls.kids.length() {
            AstNode k = cls.kids.get(i)
            if k.kind == "Method" {
                self.emit(self.methodSig(k, cn) + ";")
            }
            i = i + 1
        }
        self.emit("")
        i = 0
        while i < cls.kids.length() {
            AstNode k = cls.kids.get(i)
            if k.kind == "Method" {
                self.method(k, cn)
            }
            i = i + 1
        }
    }

    String funcProto(AstNode fn) {
        String ret = self.ctype(self.retNode(fn).text)
        String sig = "static " + ret + " xn_" + fn.text + "("
        List<AstNode> ps = self.paramsOf(fn)
        if ps.length() == 0 {
            sig = sig + "void"
        } else {
            Int i = 0
            while i < ps.length() {
                if i > 0 {
                    sig = sig + ", "
                }
                List<String> parts = ps.get(i).text.split(" ")
                if parts.length() >= 2 {
                    sig = sig + self.ctype(parts.get(0)) + " " + parts.get(1)
                }
                i = i + 1
            }
        }
        return sig + ");"
    }

    Void func(AstNode fn) {
        String name = fn.text
        String ret = self.ctype(self.retNode(fn).text)
        String sig = "static " + ret + " xn_" + name + "("
        List<AstNode> ps = self.paramsOf(fn)
        if ps.length() == 0 {
            sig = sig + "void"
        } else {
            Int i = 0
            while i < ps.length() {
                if i > 0 {
                    sig = sig + ", "
                }
                List<String> parts = ps.get(i).text.split(" ")
                if parts.length() < 2 {
                    self.fail("malformed parameter")
                    return
                }
                sig = sig + self.ctype(parts.get(0)) + " " + parts.get(1)
                i = i + 1
            }
        }
        sig = sig + ") {"
        self.emit(sig)
        self.curRet = self.retNode(fn).text
        self.popTo(0)
        Int pi = 0
        while pi < ps.length() {
            List<String> pps = ps.get(pi).text.split(" ")
            if pps.length() >= 2 {
                self.addVar(pps.get(0), pps.get(1))
            }
            pi = pi + 1
        }
        Int i = 0
        while i < fn.kids.length() {
            AstNode k = fn.kids.get(i)
            if k.kind == "Block" {
                self.blockBody(k, "  ")
            }
            i = i + 1
        }
        self.emit("}")
        self.emit("")
    }

    Void gen() {
        Int lci = 0
        while lci < self.program.kids.length() {
            self.collectLambdas(self.program.kids.get(lci), "")
            lci = lci + 1
        }
        self.emit("#include \"rt.h\"")
        self.emit("#include \"rt_gc.h\"")
        self.emit("#include \"xrt.h\"")
        self.emit("#include <stdint.h>")
        self.emit("#include <stdio.h>")
        self.emit("#include <stdlib.h>")
        self.emit("#include <unistd.h>")
        self.emit("#include <string.h>")
        self.emit("")
        self.emit("typedef struct { void *env; void *fn; } xn_closure;")
        self.emit("")
        self.emit("static void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }")
        self.emit("static void xn_print_bool(int v) { printf(v ? \"true\\n\" : \"false\\n\"); }")
        self.emit("static void xn_print_double(double v) { printf(\"%g\\n\", v); }")
        self.emit("static void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }")
        self.emit("static rt_string *xn_str_int(int64_t v) { char buf[32]; snprintf(buf, sizeof(buf), \"%lld\", (long long)v); return rt_string_from_c(buf); }")
        self.emit("static rt_string *xn_str_double(double v) { char buf[64]; snprintf(buf, sizeof(buf), \"%g\", v); return rt_string_from_c(buf); }")
        self.emit("static rt_string *xn_str_bool(int v) { return rt_string_from_c(v ? \"true\" : \"false\"); }")
        self.emit("static rt_string *xn_str_char(int32_t cp) { char b[5]; int n = 0; if (cp < 0) { cp = 0xFFFD; } if (cp < 0x80) { b[n++] = (char)cp; } else if (cp < 0x800) { b[n++] = (char)(0xC0 | (cp >> 6)); b[n++] = (char)(0x80 | (cp & 0x3F)); } else if (cp < 0x10000) { b[n++] = (char)(0xE0 | (cp >> 12)); b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); b[n++] = (char)(0x80 | (cp & 0x3F)); } else { b[n++] = (char)(0xF0 | (cp >> 18)); b[n++] = (char)(0x80 | ((cp >> 12) & 0x3F)); b[n++] = (char)(0x80 | ((cp >> 6) & 0x3F)); b[n++] = (char)(0x80 | (cp & 0x3F)); } b[n] = 0; return rt_string_from_c(b); }")
        self.emit("static rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) { if (start < 0) { start = 0; } if (n < 0) { n = 0; } if ((size_t)start > s->len) { start = (int64_t)s->len; } if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; } rt_string *out = rt_string_alloc((size_t)n); if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); } out->bytes[n] = 0; return out; }")
        self.emit("static int64_t xn_str_indexof(rt_string *s, rt_string *sub) { if (sub->len == 0) { return 0; } if (sub->len > s->len) { return -1; } for (size_t i = 0; i + sub->len <= s->len; i++) { if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; } } return -1; }")
        self.emit("static int xn_str_eq(rt_string *a, rt_string *b) { return (a->len == b->len && memcmp(a->bytes, b->bytes, a->len) == 0) ? 1 : 0; }")
        self.emit("static rt_string *xn_concat(rt_string *a, rt_string *b) { size_t n = a->len + b->len; rt_string *r = rt_string_alloc(n); memcpy(r->bytes, a->bytes, a->len); memcpy(r->bytes + a->len, b->bytes, b->len); r->bytes[n] = 0; return r; }")
        self.emit("")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;")
        self.emit("static const rt_type RT_TYPE_XN_ARR_I = { \"List\", sizeof(xn_arr_i), NULL, NULL };")
        self.emit("static xn_arr_i *xn_arr_i_new(size_t cap) { xn_arr_i *a = (xn_arr_i *)rt_gc_new(&RT_TYPE_XN_ARR_I); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (int64_t *)malloc(sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } return a; }")
        self.emit("static void xn_arr_i_push(xn_arr_i *a, int64_t v) { if (a->len == a->cap) { a->cap *= 2; a->data = (int64_t *)realloc(a->data, sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }")
        self.emit("static int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }")
        self.emit("static void xn_arr_i_remove(xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }")
        self.emit("static void xn_arr_i_set(xn_arr_i *a, int64_t i, int64_t v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }")
        self.emit("static void xn_arr_i_insert(xn_arr_i *a, int64_t i, int64_t v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (int64_t *)realloc(a->data, sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; double *data; } xn_arr_d;")
        self.emit("static const rt_type RT_TYPE_XN_ARR_D = { \"List\", sizeof(xn_arr_d), NULL, NULL };")
        self.emit("static xn_arr_d *xn_arr_d_new(size_t cap) { xn_arr_d *a = (xn_arr_d *)rt_gc_new(&RT_TYPE_XN_ARR_D); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_d) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (double *)malloc(sizeof(double) * a->cap); if (a->data == NULL) { abort(); } return a; }")
        self.emit("static void xn_arr_d_push(xn_arr_d *a, double v) { if (a->len == a->cap) { a->cap *= 2; a->data = (double *)realloc(a->data, sizeof(double) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }")
        self.emit("static double xn_arr_d_get(const xn_arr_d *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }")
        self.emit("static void xn_arr_d_remove(xn_arr_d *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }")
        self.emit("static void xn_arr_d_set(xn_arr_d *a, int64_t i, double v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }")
        self.emit("static void xn_arr_d_insert(xn_arr_d *a, int64_t i, double v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (double *)realloc(a->data, sizeof(double) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **data; } xn_arr_s;")
        self.emit("static const rt_type RT_TYPE_XN_ARR_S = { \"List\", sizeof(xn_arr_s), NULL, NULL };")
        self.emit("static xn_arr_s *xn_arr_s_new(size_t cap) { xn_arr_s *a = (xn_arr_s *)rt_gc_new(&RT_TYPE_XN_ARR_S); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_s) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (rt_string **)malloc(sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } return a; }")
        self.emit("static void xn_arr_s_push(xn_arr_s *a, rt_string *v) { if (a->len == a->cap) { a->cap *= 2; a->data = (rt_string **)realloc(a->data, sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }")
        self.emit("static rt_string *xn_arr_s_get(const xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }")
        self.emit("static void xn_arr_s_remove(xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }")
        self.emit("static void xn_arr_s_set(xn_arr_s *a, int64_t i, rt_string *v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }")
        self.emit("static void xn_arr_s_insert(xn_arr_s *a, int64_t i, rt_string *v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (rt_string **)realloc(a->data, sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; void **data; } xn_arr_o;")
        self.emit("static const rt_type RT_TYPE_XN_ARR_O = { \"List\", sizeof(xn_arr_o), NULL, NULL };")
        self.emit("static xn_arr_o *xn_arr_o_new(size_t cap) { xn_arr_o *a = (xn_arr_o *)rt_gc_new(&RT_TYPE_XN_ARR_O); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_o) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (void **)malloc(sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } return a; }")
        self.emit("static void xn_arr_o_push(xn_arr_o *a, void *v) { if (a->len == a->cap) { a->cap *= 2; a->data = (void **)realloc(a->data, sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }")
        self.emit("static void *xn_arr_o_get(const xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }")
        self.emit("static void xn_arr_o_remove(xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }")
        self.emit("static void xn_arr_o_set(xn_arr_o *a, int64_t i, void *v) { if (i < 0 || (size_t)i >= a->len) { abort(); } a->data[i] = v; }")
        self.emit("static void xn_arr_o_insert(xn_arr_o *a, int64_t i, void *v) { if (i < 0 || (size_t)i > a->len) { abort(); } if (a->len == a->cap) { a->cap *= 2; a->data = (void **)realloc(a->data, sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } } for (size_t j = a->len; j > (size_t)i; j--) { a->data[j] = a->data[j - 1]; } a->data[i] = v; a->len++; }")
        self.emit("static int xn_str_startswith(rt_string *s, rt_string *p) { if (p->len > s->len) { return 0; } return memcmp(s->bytes, p->bytes, p->len) == 0 ? 1 : 0; }")
        self.emit("static int xn_str_endswith(rt_string *s, rt_string *p) { if (p->len > s->len) { return 0; } return memcmp(s->bytes + (s->len - p->len), p->bytes, p->len) == 0 ? 1 : 0; }")
        self.emit("static rt_string *xn_str_trim(rt_string *s) { size_t a = 0, b = s->len; while (a < b && (s->bytes[a] == ' ' || s->bytes[a] == '\\t' || s->bytes[a] == '\\n' || s->bytes[a] == '\\r' || s->bytes[a] == '\\v' || s->bytes[a] == '\\f')) { a++; } while (b > a && (s->bytes[b-1] == ' ' || s->bytes[b-1] == '\\t' || s->bytes[b-1] == '\\n' || s->bytes[b-1] == '\\r' || s->bytes[b-1] == '\\v' || s->bytes[b-1] == '\\f')) { b--; } rt_string *r = rt_string_alloc(b - a); if (b > a) { memcpy(r->bytes, s->bytes + a, b - a); } r->bytes[b-a] = 0; return r; }")
        self.emit("static rt_string *xn_str_case(rt_string *s, int upper) { rt_string *r = rt_string_alloc(s->len); for (size_t i = 0; i < s->len; i++) { unsigned char c = (unsigned char)s->bytes[i]; if (upper && c >= 'a' && c <= 'z') { c = (unsigned char)(c - 32); } else if (!upper && c >= 'A' && c <= 'Z') { c = (unsigned char)(c + 32); } r->bytes[i] = (char)c; } r->bytes[s->len] = 0; return r; }")
        self.emit("static rt_string *xn_str_replace(rt_string *s, rt_string *from, rt_string *to) { if (from->len == 0) { return s; } size_t cap = s->len + 8, n = 0; char *buf = (char *)malloc(cap); if (buf == NULL) { abort(); } for (size_t i = 0; i < s->len; ) { if (i + from->len <= s->len && memcmp(s->bytes + i, from->bytes, from->len) == 0) { while (n + to->len + 1 > cap) { cap *= 2; buf = (char *)realloc(buf, cap); if (buf == NULL) { abort(); } } memcpy(buf + n, to->bytes, to->len); n += to->len; i += from->len; } else { while (n + 2 > cap) { cap *= 2; buf = (char *)realloc(buf, cap); if (buf == NULL) { abort(); } } buf[n++] = s->bytes[i++]; } } buf[n] = 0; rt_string *r = rt_string_from_c(buf); free(buf); return r; }")
        self.emit("static xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) { xn_arr_s *out = xn_arr_s_new(4); if (sep->len == 0) { xn_arr_s_push(out, s); return out; } size_t start = 0; size_t i = 0; while (i + sep->len <= s->len) { if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) { size_t n = i - start; rt_string *p = rt_string_alloc(n); if (n > 0) { memcpy(p->bytes, s->bytes + start, n); } p->bytes[n] = 0; xn_arr_s_push(out, p); i = i + sep->len; start = i; } else { i++; } } { size_t n = s->len - start; rt_string *p = rt_string_alloc(n); if (n > 0) { memcpy(p->bytes, s->bytes + start, n); } p->bytes[n] = 0; xn_arr_s_push(out, p); } return out; }")
        self.emit("static rt_string *xn_arr_s_join(xn_arr_s *a, rt_string *sep) { size_t n = 0; for (size_t i = 0; i < a->len; i++) { n += a->data[i]->len; if (i > 0) { n += sep->len; } } rt_string *r = rt_string_alloc(n); size_t off = 0; for (size_t i = 0; i < a->len; i++) { if (i > 0) { memcpy(r->bytes + off, sep->bytes, sep->len); off += sep->len; } memcpy(r->bytes + off, a->data[i]->bytes, a->data[i]->len); off += a->data[i]->len; } r->bytes[n] = 0; return r; }")
        self.emit("")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **keys; int64_t *vals; } xn_map_s_i;")
        self.emit("static const rt_type RT_TYPE_XN_MAP_S_I = { \"Map\", sizeof(xn_map_s_i), NULL, NULL };")
        self.emit("static xn_map_s_i *xn_map_s_i_new(size_t cap) { xn_map_s_i *m = (xn_map_s_i *)rt_gc_new(&RT_TYPE_XN_MAP_S_I); memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_s_i) - sizeof(rt_header)); m->cap = cap ? cap : 4; m->keys = (rt_string **)malloc(sizeof(rt_string *) * m->cap); m->vals = (int64_t *)malloc(sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } return m; }")
        self.emit("static long xn_map_s_i_find(const xn_map_s_i *m, rt_string *key) { for (size_t i = 0; i < m->len; i++) { if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; } } return -1; }")
        self.emit("static int xn_map_s_i_has(const xn_map_s_i *m, rt_string *key) { return xn_map_s_i_find(m, key) >= 0 ? 1 : 0; }")
        self.emit("static void xn_map_s_i_put(xn_map_s_i *m, rt_string *key, int64_t val) { long i = xn_map_s_i_find(m, key); if (i >= 0) { m->vals[i] = val; return; } if (m->len == m->cap) { m->cap *= 2; m->keys = (rt_string **)realloc(m->keys, sizeof(rt_string *) * m->cap); m->vals = (int64_t *)realloc(m->vals, sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; }")
        self.emit("static int64_t xn_map_s_i_getOr(const xn_map_s_i *m, rt_string *key, int64_t dflt) { long i = xn_map_s_i_find(m, key); return i >= 0 ? m->vals[i] : dflt; }")
        self.emit("")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_set_i;")
        self.emit("static const rt_type RT_TYPE_XN_SET_I = { \"Set\", sizeof(xn_set_i), NULL, NULL };")
        self.emit("static xn_set_i *xn_set_i_new(void) { xn_set_i *s = (xn_set_i *)rt_gc_new(&RT_TYPE_XN_SET_I); memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_i) - sizeof(rt_header)); s->cap = 4; s->data = (int64_t *)malloc(sizeof(int64_t) * s->cap); if (s->data == NULL) { abort(); } return s; }")
        self.emit("static int xn_set_i_has(const xn_set_i *s, int64_t v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i] == v) { return 1; } } return 0; }")
        self.emit("static int xn_set_i_add(xn_set_i *s, int64_t v) { if (xn_set_i_has(s, v)) { return 0; } if (s->len == s->cap) { s->cap *= 2; s->data = (int64_t *)realloc(s->data, sizeof(int64_t) * s->cap); if (s->data == NULL) { abort(); } } s->data[s->len++] = v; return 1; }")
        self.emit("")
        self.emit("const char *mini_read_file(const char *path, size_t len);")
        self.emit("const char *mini_list_x(const char *path, size_t len);")
        self.emit("static const char *mini_platform(void) { return \"darwin\"; }")
        self.emit("static int32_t mini_file_exists(const char *path_bytes, size_t path_len) { char *p = (char *)malloc(path_len + 1); if (p == NULL) { return 0; } memcpy(p, path_bytes, path_len); p[path_len] = 0; int ok = access(p, F_OK) == 0; free(p); return ok ? 1 : 0; }")
        self.emit("int32_t xdkc_p_resource_exists(const char *path, size_t len);")
        self.emit("const char *xdkc_p_read_resource_text(const char *path, size_t len);")
        self.emit("int64_t xdkc_p_resource_count(void);")
        self.emit("const char *xdkc_read_file_text(const char *bytes, size_t len);")
        self.emit("int32_t xdkc_read_file_text_error(void);")
        self.emit("int32_t xdkc_diagnose_rc(const char *bytes, size_t len);")
        self.emit("int32_t xdkc_exit_rc(int32_t code);")
        self.emit("int64_t xdkc_now_mono_ms(void);")
        self.emit("int64_t xdkc_now_wall_ms(void);")
        self.emit("typedef struct { int ok; int64_t value; rt_string *error; } xn_Result_Int_String;")
        self.emit("typedef struct { int ok; int64_t i; double d; rt_string *s; void *p; void *err; } xn_Result;")
        self.emit("")
        self.emitFfiDecls()
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Class" || n.kind == "Struct" || (n.kind == "Enum" && self.isDataEnum(n.text)) {
                self.emit("typedef struct xn_Cls_" + n.text + " xn_Cls_" + n.text + ";")
            }
            i = i + 1
        }
        i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "TopField" {
                List<String> parts = n.text.split(" ")
                if parts.length() >= 2 {
                    self.emit("static " + self.ctype(parts.get(0)) + " " + parts.get(1) + ";")
                }
            }
            i = i + 1
        }
        self.emit("")
        i = 0
        while i < self.lambdas.length() {
            self.emit(self.lambdaProto(i))
            i = i + 1
        }
        self.emit("")
        i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" && !hasTypeParams(n) {
                self.emit(self.funcProto(n))
            }
            i = i + 1
        }
        self.emit("")
        i = 0
        while i < self.program.kids.length() && !self.hasError() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" {
                Int j = 0
                while j < n.kids.length() {
                    AstNode it = n.kids.get(j)
                    if it.kind == "EnumItem" {
                        if self.isDataEnum(n.text) {
                            self.emit("static xn_Cls_" + n.text + " *xn_enum_" + n.text + "_" + it.text + ";")
                        } else {
                            self.emit("static const int64_t xn_enum_" + n.text + "_" + it.text + " = " + str(self.enumValue(n.text, it.text)) + ";")
                        }
                    }
                    j = j + 1
                }
            }
            if (n.kind == "Class" || n.kind == "Struct" || (n.kind == "Enum" && self.isDataEnum(n.text))) && !hasTypeParams(n) {
                self.genClass(n)
            }
            i = i + 1
        }
        i = 0
        while i < self.program.kids.length() {
            AstNode p = self.program.kids.get(i)
            if p.kind == "Protocol" {
                Int si = 0
                while si < p.kids.length() {
                    AstNode sig = p.kids.get(si)
                    if sig.kind == "Sig" {
                        String rt = self.protoRet(p.text, sig.text)
                        List<AstNode> pps = self.protoParams(p.text, sig.text)
                        String fsig = "static " + self.ctype(rt) + " xn_proto_" + p.text + "_" + sig.text + "(void *xn_obj"
                        Int pi = 0
                        while pi < pps.length() {
                            List<String> pp = pps.get(pi).text.split(" ")
                            if pp.length() >= 2 {
                                fsig = fsig + ", " + self.ctype(pp.get(0)) + " " + pp.get(1)
                            }
                            pi = pi + 1
                        }
                        fsig = fsig + ") {"
                        self.emit(fsig)
                        Int ci = 0
                        while ci < self.program.kids.length() {
                            AstNode c = self.program.kids.get(ci)
                            if (c.kind == "Class" || c.kind == "Struct") && !hasTypeParams(c) {
                                Bool impl = false
                                Int ck = 0
                                while ck < c.kids.length() {
                                    if c.kids.get(ck).kind == "Implements" && c.kids.get(ck).text == p.text {
                                        impl = true
                                    }
                                    ck = ck + 1
                                }
                                if impl {
                                    String call = "return xn_Cls_" + c.text + "_" + sig.text + "((xn_Cls_" + c.text + " *)xn_obj"
                                    Int ai = 0
                                    while ai < pps.length() {
                                        List<String> pp = pps.get(ai).text.split(" ")
                                        if pp.length() >= 2 {
                                            call = call + ", " + pp.get(1)
                                        }
                                        ai = ai + 1
                                    }
                                    call = call + ");"
                                    self.emit("  if (((rt_header *)xn_obj)->type == &RT_TYPE_XN_" + c.text + ") " + call)
                                }
                            }
                            ci = ci + 1
                        }
                        self.emit("  rt_fatal(\"protocol dispatch failed: " + p.text + "." + sig.text + "\");")
                        if rt == "Unit" || rt == "void" || rt == "Void" {
                            self.emit("  return;")
                        } else {
                            self.emit("  return 0;")
                        }
                        self.emit("}")
                        self.emit("")
                    }
                    si = si + 1
                }
            }
            i = i + 1
        }
        i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "TopField" {
                List<String> parts = n.text.split(" ")
                if parts.length() >= 2 {
                    self.emit("static " + self.ctype(parts.get(0)) + " " + parts.get(1) + ";")
                }
            }
            i = i + 1
        }
        self.emit("")
        self.emit("static void xn_init_globals(void) {")
        i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "TopField" {
                List<String> parts = n.text.split(" ")
                if parts.length() >= 2 {
                    String ty = parts.get(0)
                    String name = parts.get(1)
                    String init = "0"
                    if ty == "String" {
                        init = "rt_string_from_c(\"\")"
                    }
                    if self.isFunctionType(ty) {
                        init = "(xn_closure){0, 0}"
                    }
                    if self.isArray(ty) {
                        init = self.arrayNew(ty, 4)
                    }
                    if n.kids.length() > 0 {
                        if self.isArray(ty) && n.kids.get(0).kind == "ArrayLit" {
                            AstNode lit = n.kids.get(0)
                            init = self.arrayNew(ty, lit.kids.length())
                        } else {
                            init = self.expr(n.kids.get(0))
                        }
                    }
                    self.emit("  " + name + " = " + init + ";")
                }
            }
            i = i + 1
        }
        i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" && self.isDataEnum(n.text) {
                Int j = 0
                while j < n.kids.length() {
                    AstNode it = n.kids.get(j)
                    if it.kind == "EnumItem" {
                        String args = ""
                        Int ai = 0
                        while ai < it.kids.length() {
                            if ai > 0 {
                                args = args + ", "
                            }
                            args = args + self.expr(it.kids.get(ai))
                            ai = ai + 1
                        }
                        self.emit("  xn_enum_" + n.text + "_" + it.text + " = xn_Cls_" + n.text + "_new(" + args + ");")
                    }
                    j = j + 1
                }
            }
            i = i + 1
        }
        self.emit("}")
        self.emit("")
        i = 0
        while i < self.program.kids.length() && !self.hasError() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" && !hasTypeParams(n) {
                self.func(n)
            }
            i = i + 1
        }
        i = 0
        while i < self.lambdas.length() && !self.hasError() {
            self.emitLambdaDef(i)
            i = i + 1
        }
        Bool mainArgs = false
        i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Func" && n.text == "main" && self.paramsOf(n).length() > 0 {
                mainArgs = true
            }
            i = i + 1
        }
        if mainArgs {
            self.emit("int main(int argc, char **argv) {")
        } else {
            self.emit("int main(void) {")
        }
        self.emit("  xrt_runtime_init();")
        self.emit("  xn_init_globals();")
        if mainArgs {
            self.emit("  xn_arr_s *args = xn_arr_s_new(argc > 1 ? (size_t)(argc - 1) : 1);")
            self.emit("  for (int ai = 1; ai < argc; ai++) { xn_arr_s_push(args, rt_string_from_c(argv[ai])); }")
            self.emit("  int64_t xn_result = xn_main(args);")
        } else {
            self.emit("  int64_t xn_result = xn_main();")
        }
        self.emit("  rt_gc_collect();")
        self.emit("  return (int)xn_result;")
        self.emit("}")
    }

    String text() {
        return self.lines.join("\n")
    }
}

static Int usage() {
    print("usage: mini --emit-c <entry.x> [-o out.c] | --check <entry.x> | --ast <entry.x> | --sema <entry.x> | --supports <entry.x> | --version")
    return 2
}

static String at(String s, Int i) {
    if i < 0 || i >= s.length() {
        return ""
    }
    return s.substring(i, 1)
}

static Bool starts(String s, Int i, String lit) {
    if i < 0 || i + lit.length() > s.length() {
        return false
    }
    return s.substring(i, lit.length()) == lit
}

static Bool isDigit(String c) {
    return c == "0" || c == "1" || c == "2" || c == "3" || c == "4" ||
        c == "5" || c == "6" || c == "7" || c == "8" || c == "9"
}
static Bool isHex(String c) {
    return isDigit(c) || c == "a" || c == "b" || c == "c" || c == "d" || c == "e" || c == "f" ||
        c == "A" || c == "B" || c == "C" || c == "D" || c == "E" || c == "F"
}

static Bool isLower(String c) {
    return c == "a" || c == "b" || c == "c" || c == "d" || c == "e" ||
        c == "f" || c == "g" || c == "h" || c == "i" || c == "j" ||
        c == "k" || c == "l" || c == "m" || c == "n" || c == "o" ||
        c == "p" || c == "q" || c == "r" || c == "s" || c == "t" ||
        c == "u" || c == "v" || c == "w" || c == "x" || c == "y" ||
        c == "z"
}

static Bool isUpper(String c) {
    return c == "A" || c == "B" || c == "C" || c == "D" || c == "E" ||
        c == "F" || c == "G" || c == "H" || c == "I" || c == "J" ||
        c == "K" || c == "L" || c == "M" || c == "N" || c == "O" ||
        c == "P" || c == "Q" || c == "R" || c == "S" || c == "T" ||
        c == "U" || c == "V" || c == "W" || c == "X" || c == "Y" ||
        c == "Z"
}

static Bool isIdentStart(String c) {
    return isLower(c) || isUpper(c) || c == "_"
}

static Bool isIdentPart(String c) {
    return isIdentStart(c) || isDigit(c)
}

static Bool isSpace(String c) {
    return c == " " || c == "\t" || c == "\r" || c == "\n"
}

static Bool isKeyword(String s) {
    return s == "package" || s == "import" || s == "static" || s == "final" ||
        s == "public" || s == "private" || s == "protected" || s == "class" ||
        s == "struct" || s == "enum" || s == "protocol" || s == "interface" ||
        s == "extends" || s == "implements" || s == "new" || s == "self" ||
        s == "super" || s == "this" || s == "return" || s == "if" || s == "else" ||
        s == "while" || s == "do" || s == "for" || s == "in" || s == "switch" ||
        s == "case" || s == "default" || s == "break" || s == "continue" ||
        s == "goto" || s == "try" || s == "catch" || s == "throw" || s == "defer" ||
        s == "errdefer" || s == "true" || s == "false" || s == "null" ||
        s == "is" || s == "as" || s == "void" || s == "factory" || s == "deinit"
}

static List<Token> lex(String src) {
    List<Token> tokens = []
    Int i = 0
    Int line = 1
    Int col = 1

    while i < src.length() {
        String c = at(src, i)
        String next = at(src, i + 1)

        if c == "\n" {
            i = i + 1
            line = line + 1
            col = 1
            continue
        }
        if isSpace(c) {
            i = i + 1
            col = col + 1
            continue
        }
        if c == "/" && next == "/" {
            i = i + 2
            col = col + 2
            while i < src.length() && at(src, i) != "\n" {
                i = i + 1
                col = col + 1
            }
            continue
        }
        if c == "/" && next == "*" {
            i = i + 2
            col = col + 2
            while i < src.length() && !(at(src, i) == "*" && at(src, i + 1) == "/") {
                if at(src, i) == "\n" {
                    line = line + 1
                    col = 1
                } else {
                    col = col + 1
                }
                i = i + 1
            }
            if i < src.length() {
                i = i + 2
                col = col + 2
            }
            continue
        }

        Int start = i
        Int startLine = line
        Int startCol = col

        if isIdentStart(c) {
            i = i + 1
            col = col + 1
            while i < src.length() && isIdentPart(at(src, i)) {
                i = i + 1
                col = col + 1
            }
            String ident = src.substring(start, i - start)
            String kind = "ident"
            if isKeyword(ident) {
                kind = "kw"
            }
            tokens.push(new Token(kind, ident, startLine, startCol))
            continue
        }

        if isDigit(c) {
            if c == "0" && i + 1 < src.length() && (at(src, i + 1) == "x" || at(src, i + 1) == "X") {
                i = i + 2
                col = col + 2
                while i < src.length() && isHex(at(src, i)) {
                    i = i + 1
                    col = col + 1
                }
                tokens.push(new Token("int", src.substring(start, i - start), startLine, startCol))
                continue
            }
            i = i + 1
            col = col + 1
            while i < src.length() && isDigit(at(src, i)) {
                i = i + 1
                col = col + 1
            }
            Bool isDouble = false
            if i < src.length() && at(src, i) == "." && i + 1 < src.length() && isDigit(at(src, i + 1)) {
                isDouble = true
                i = i + 1
                col = col + 1
                while i < src.length() && isDigit(at(src, i)) {
                    i = i + 1
                    col = col + 1
                }
            }
            if isDouble {
                tokens.push(new Token("double", src.substring(start, i - start), startLine, startCol))
            } else {
                tokens.push(new Token("int", src.substring(start, i - start), startLine, startCol))
            }
            continue
        }

        Bool interp = false
        if c == "$" && next == "\"" {
            interp = true
            i = i + 1
            col = col + 1
            c = "\""
            start = i
        }
        if c == "\"" {
            i = i + 1
            col = col + 1
            Bool closed = false
            while i < src.length() {
                String d = at(src, i)
                if d == "\\" {
                    i = i + 2
                    col = col + 2
                    continue
                }
                if d == "\"" {
                    i = i + 1
                    col = col + 1
                    closed = true
                    break
                }
                if d == "\n" {
                    line = line + 1
                    col = 1
                } else {
                    col = col + 1
                }
                i = i + 1
            }
            if !closed {
                tokens.push(new Token("error", "unterminated string", startLine, startCol))
                return tokens
            }
            if interp {
                tokens.push(new Token("interp", src.substring(start, i - start), startLine, startCol))
            } else {
                tokens.push(new Token("string", src.substring(start, i - start), startLine, startCol))
            }
            continue
        }

        if c == "'" {
            i = i + 1
            col = col + 1
            Bool closed = false
            while i < src.length() {
                String d = at(src, i)
                if d == "\\" {
                    i = i + 2
                    col = col + 2
                    continue
                }
                if d == "'" {
                    i = i + 1
                    col = col + 1
                    closed = true
                    break
                }
                if d == "\n" {
                    line = line + 1
                    col = 1
                } else {
                    col = col + 1
                }
                i = i + 1
            }
            if !closed {
                tokens.push(new Token("error", "unterminated char", startLine, startCol))
                return tokens
            }
            tokens.push(new Token("char", src.substring(start, i - start), startLine, startCol))
            continue
        }

        String op = c
        if starts(src, i, "==") || starts(src, i, "!=") ||
            starts(src, i, "<=") || starts(src, i, ">=") ||
            starts(src, i, "<<") ||
            starts(src, i, "&&") || starts(src, i, "||") ||
            starts(src, i, "->") || starts(src, i, "=>") ||
            starts(src, i, "::") || starts(src, i, "..") ||
            starts(src, i, "+=") || starts(src, i, "-=") ||
            starts(src, i, "*=") || starts(src, i, "/=") ||
            starts(src, i, "++") || starts(src, i, "--") {
            op = src.substring(i, 2)
            i = i + 2
            col = col + 2
        } else if c == "(" || c == ")" || c == "{" || c == "}" ||
            c == "[" || c == "]" || c == "," || c == ";" || c == ":" ||
            c == "." || c == "+" || c == "-" || c == "*" || c == "/" ||
            c == "%" || c == "=" || c == "<" || c == ">" || c == "!" ||
            c == "&" || c == "|" || c == "^" || c == "?" || c == "@" {
            i = i + 1
            col = col + 1
        } else {
            tokens.push(new Token("error", "unexpected character: " + c, startLine, startCol))
            return tokens
        }
        tokens.push(new Token("punct", op, startLine, startCol))
    }

    tokens.push(new Token("eof", "", line, col))
    return tokens
}

static Bool hasTypeParams(AstNode fn) {
    Int i = 0
    while i < fn.kids.length() {
        if fn.kids.get(i).kind == "TypeParams" {
            return true
        }
        i = i + 1
    }
    return false
}

static Int dumpTokens(List<Token> ts, String path) {
    Int i = 0
    while i < ts.length() {
        Token t = ts.get(i)
        if t.kind == "error" {
            print(path + ":" + str(t.line) + ":" + str(t.col) + ": " + t.text)
            return 1
        }
        print(t.kind + "\t" + t.text + "\t" + str(t.line) + ":" + str(t.col))
        i = i + 1
    }
    return 0
}

static Int ffiIndex(String name) {
    Int i = 0
    while i < ffiNames.length() {
        if ffiNames.get(i) == name {
            return i
        }
        i = i + 1
    }
    return -1
}

static String ffiRet(String name) {
    Int i = ffiIndex(name)
    if i >= 0 {
        return ffiRets.get(i)
    }
    return "Any"
}

static String ffiCName(String name) {
    Int i = ffiIndex(name)
    if i >= 0 {
        return ffiCNames.get(i)
    }
    return name
}

static Void loadProject(String path) {
    if path == "" {
        return
    }
    String src = readFile(path)
    if src.length() == 0 {
        return
    }
    List<String> lines = src.split("\n")
    Int i = 0
    while i < lines.length() {
        String line = lines.get(i)
        if line.length() > 2 && line.substring(0, 2) == "E|" {
            List<String> f = line.split("|")
            if f.length() >= 6 && ffiIndex(f.get(2)) < 0 {
                ffiNames.push(f.get(2))
                ffiCNames.push(f.get(3))
                ffiRets.push(f.get(5))
                if f.length() >= 10 {
                    ffiParamSpecs.push(f.get(9))
                } else {
                    ffiParamSpecs.push("")
                }
                if f.length() >= 8 {
                    ffiErrParams.push(f.get(6))
                    ffiErrRets.push(f.get(7))
                } else {
                    ffiErrParams.push("")
                    ffiErrRets.push("")
                }
            }
        }
        i = i + 1
    }
}

static Int lastDot(String s) {
    Int i = 0
    Int found = -1
    while i < s.length() {
        if s.substring(i, 1) == "." {
            found = i
        }
        i = i + 1
    }
    return found
}

static String localImportFile(String pkg) {
    String rel = pkg.replace(".", "/") + ".x"
    String path = loadBaseDir + "/" + rel
    if readFile(path).length() > 0 { return path }
    return ""
}

static String xdkFile(String pkg) {
    if pkg == "xdk.errors" || pkg.startsWith("xdk.errors.") {
        return "core/errors/Errors.x"
    }
    if pkg == "xdk.meta" || pkg.startsWith("xdk.meta.") {
        return "core/meta/Meta.x"
    }
    if pkg == "xdk.runtime" || pkg.startsWith("xdk.runtime.") {
        return "core/runtime/Runtime.x"
    }
    if pkg == "xdk.math" || pkg.startsWith("xdk.math.") {
        return "core/math/Math.x"
    }
    if pkg == "xdk.collections" || pkg.startsWith("xdk.collections.") {
        return "core/collections/Collections.x"
    }
    if pkg == "xdk.bytes" || pkg.startsWith("xdk.bytes.") {
        return "core/bytes/Bytes.x"
    }
    if pkg == "xdk.io" || pkg.startsWith("xdk.io.") {
        return "io/IO.x"
    }
    if pkg == "xdk.sync" || pkg.startsWith("xdk.sync.") {
        return "concurrent/sync/Sync.x"
    }
    if pkg == "xdk.tasks" || pkg.startsWith("xdk.tasks.") {
        return "concurrent/tasks/Tasks.x"
    }
    if pkg == "xdk.time" || pkg.startsWith("xdk.time.") {
        return "core/time/Time.x"
    }
    if pkg == "xdk.text" || pkg.startsWith("xdk.text.") {
        return "text/full/Text.x"
    }
    if pkg == "xdk.sys" || pkg.startsWith("xdk.sys.") {
        if xdkFullSource {
            return "io/system/Sys.x"
        }
        return "io/base/Sys.x"
    }
    return ""
}

static Bool endsWithX(String s) {
    return s.length() >= 2 && s.substring(s.length() - 2, 2) == ".x"
}

static String dirName(String path) {
    Int i = path.length() - 1
    while i >= 0 {
        if path.substring(i, 1) == "/" {
            return path.substring(0, i)
        }
        i = i - 1
    }
    return "."
}

static Bool loaded(String path) {
    Int i = 0
    while i < loadedFiles.length() {
        if loadedFiles.get(i) == path {
            return true
        }
        i = i + 1
    }
    return false
}

static Void mergeDecls(AstNode program, AstNode parsed) {
    Int i = 0
    while i < parsed.kids.length() {
        AstNode d = parsed.kids.get(i)
        if d.kind != "Package" && d.kind != "Import" {
            program.add(d)
        }
        i = i + 1
    }
}

static Void loadUnit(String path, AstNode program) {
    if loaded(path) {
        return
    }
    loadedFiles.push(path)
    String isrc = readFile(path)
    if isrc.length() == 0 {
        return
    }
    Parser ip = new Parser(lex(isrc))
    AstNode iprogram = ip.parse()
    if ip.hasError() {
        return
    }
    Int ii = 0
    while ii < iprogram.kids.length() {
        AstNode idep = iprogram.kids.get(ii)
        if idep.kind == "Import" {
            String drel = xdkFile(idep.text)
            if drel != "" {
                loadUnit(loadRoot + "/" + drel, program)
            } else {
                String dlocal = localImportFile(idep.text)
                if dlocal != "" { loadUnit(dlocal, program) }
            }
        }
        ii = ii + 1
    }
    mergeDecls(program, iprogram)
    String dir = dirName(path)
    String names = listFiles(dir)
    List<String> files = names.split("\n")
    Int i = 0
    while i < files.length() {
        String name = files.get(i)
        if name != "" && endsWithX(name) {
            String p2 = dir + "/" + name
            if !loaded(p2) && p2 != path {
                loadUnit(p2, program)
            }
        }
        i = i + 1
    }
}

static Void loadSiblings(String path, AstNode program) {
    String dir = dirName(path)
    String names = listFiles(dir)
    List<String> files = names.split("\n")
    Int i = 0
    while i < files.length() {
        String name = files.get(i)
        if name != "" && endsWithX(name) {
            String p2 = dir + "/" + name
            if p2 != path && !loaded(p2) {
                loadUnit(p2, program)
            }
        }
        i = i + 1
    }
}

static AstNode loadProgram(String entry, String root) {
    String src = readFile(entry)
    if src.length() == 0 {
        print("mini: cannot read input or input is empty")
        return new AstNode("Program", "", 1, 1)
    }
    Parser p = new Parser(lex(src))
    AstNode program = p.parse()
    if p.hasError() {
        print(entry + ":" + str(p.errorLine) + ":" + str(p.errorCol) + ": " + p.error)
        return program
    }
    loadedFiles.push(entry)
    loadRoot = root
    loadBaseDir = dirName(entry)
    if entry.indexOf("/xdk/") >= 0 {
        loadSiblings(entry, program)
    }
    Int i = 0
    while i < program.kids.length() {
        AstNode imp = program.kids.get(i)
        if imp.kind == "Import" {
            String rel = xdkFile(imp.text)
            String path = ""
            if rel != "" {
                path = root + "/" + rel
            } else {
                path = localImportFile(imp.text)
                if path == "" {
                    print("mini: unsupported import: " + imp.text)
                    return program
                }
            }
            if loaded(path) {
                i = i + 1
                continue
            }
            loadUnit(path, program)
        }
        i = i + 1
    }
    Mono mono = new Mono(program)
    return mono.run()
}

static String argAfter(String[] args, String flag) {
    Int i = 0
    while i + 1 < args.length() {
        if args.get(i) == flag {
            return args.get(i + 1)
        }
        i = i + 1
    }
    return ""
}

static Bool hasArg(String[] args, String flag) {
    Int i = 0
    while i < args.length() {
        if args.get(i) == flag {
            return true
        }
        i = i + 1
    }
    return false
}

static Int main(String[] args) {
    if args.length() == 0 {
        return usage()
    }
    String cmd = args[0]
    String xdkRoot = argAfter(args, "--xdk-root")
    if xdkRoot == "" {
        xdkRoot = "src/xdk"
    }
    loadProject(argAfter(args, "--project-file"))
    xdkFullSource = hasArg(args, "--xdk-full")
    if cmd == "--version" {
        print("mini 0.2.0")
        return 0
    }
    if cmd == "--supports" {
        if args.length() < 2 {
            return 3
        }
        AstNode program = loadProgram(args[1], xdkRoot)
        if program.kids.length() == 0 {
            return 3
        }
        Checker c = new Checker(args[1], program)
        c.check()
        if c.hasError() {
            return 3
        }
        return 0
    }
    if cmd == "--check" {
        if args.length() < 2 {
            return usage()
        }
        String src = readFile(args[1])
        if src.length() == 0 {
            print("mini: cannot read input or input is empty")
            return 1
        }
        return dumpTokens(lex(src), args[1])
    }
    if cmd == "--ast" {
        if args.length() < 2 {
            return usage()
        }
        AstNode program = loadProgram(args[1], xdkRoot)
        if program.kids.length() == 0 {
            return 1
        }
        program.dump(0)
        return 0
    }
    if cmd == "--sema" {
        if args.length() < 2 {
            return usage()
        }
        AstNode program = loadProgram(args[1], xdkRoot)
        if program.kids.length() == 0 {
            return 1
        }
        Checker c = new Checker(args[1], program)
        c.check()
        if c.hasError() {
            print(args[1] + ":" + str(c.errorLine) + ":" + str(c.errorCol) + ": [" + c.errorCode + "] " + c.error)
            return 1
        }
        print("sema ok")
        return 0
    }
    if cmd == "--emit-c" {
        if args.length() < 2 {
            return usage()
        }
        AstNode program = loadProgram(args[1], xdkRoot)
        if program.kids.length() == 0 {
            return 1
        }
        Checker c = new Checker(args[1], program)
        c.check()
        if c.hasError() {
            print(args[1] + ":" + str(c.errorLine) + ":" + str(c.errorCol) + ": [" + c.errorCode + "] " + c.error)
            return 1
        }
        CGen g = new CGen(program, ffiNames, ffiCNames, ffiRets, ffiParamSpecs, ffiErrParams, ffiErrRets)
        g.gen()
        if g.hasError() {
            print(args[1] + ": " + g.err)
            return 1
        }
        print(g.text())
        return 0
    }
    return usage()
}
