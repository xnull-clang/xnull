// XNull mini compiler —— M1 loader + lexer
package mini

List<String> ffiNames = []
List<String> ffiCNames = []
List<String> ffiRets = []

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
        while !self.hasError() && !self.at("}") && !self.eof() {
            if !self.kind("ident") {
                self.fail("expected enum item")
                break
            }
            Token it = self.advance()
            AstNode item = self.node("EnumItem", it.text, it)
            if self.eat("=") {
                item.add(self.parseExpr())
            }
            e.add(item)
            if !self.eat(",") {
                break
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
            fn.add(new AstNode("TypeParams", "", t.line, t.col))
            Int depth = 1
            while !self.hasError() && depth > 0 {
                if self.at("<") {
                    depth = depth + 1
                } else if self.at(">") {
                    depth = depth - 1
                }
                if depth > 0 {
                    self.advance()
                }
            }
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
        if self.isLocalDecl() {
            return self.parseLocal()
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
            AstNode n = self.node("ForIn", v.text, t)
            n.add(self.parseExpr())
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
        if self.eat("while") {
            AstNode n = self.node("While", "", t)
            n.add(self.parseExpr())
            n.add(self.parseBlock())
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
        return self.parseOr()
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
        AstNode left = self.parseAdd()
        while !self.hasError() && (self.at("<") || self.at("<=") || self.at(">") || self.at(">=")) {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
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
        AstNode left = self.parsePrimary()
        while !self.hasError() && (self.at("*") || self.at("/") || self.at("%")) {
            Token op = self.advance()
            AstNode n = self.node("Binary", op.text, op)
            n.add(left)
            n.add(self.parsePrimary())
            left = n
        }
        return left
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

    AstNode parsePrimary() {
        Token t = self.peek()
        if self.kind("int") {
            self.advance()
            return self.node("Int", t.text, t)
        }
        if self.kind("string") {
            self.advance()
            return self.node("String", t.text, t)
        }
        if self.kind("char") {
            self.advance()
            return self.node("Char", t.text, t)
        }
        if self.kind("kw") && (t.text == "true" || t.text == "false") {
            self.advance()
            return self.node("Bool", t.text, t)
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
                if self.eat("(") {
                    String cname = t.text
                    if n.kind == "Member" {
                        cname = self.memberPath(n)
                    }
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

    Bool knownType(String ty) {
        if ty == "Int" || ty == "String" || ty == "Bool" ||
            ty == "Unit" || ty == "Char" || ty == "Double" ||
            ty == "Long" || ty == "Int64" {
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

    String resultInner(String ty) {
        if self.isResultType(ty) {
            return ty.substring(7, ty.length() - 8)
        }
        return ""
    }

    String resultValueType(String ty) {
        List<String> parts = self.resultInner(ty).split(",")
        if parts.length() >= 1 {
            return parts.get(0)
        }
        return "Any"
    }

    String resultErrorType(String ty) {
        List<String> parts = self.resultInner(ty).split(",")
        if parts.length() >= 2 {
            return parts.get(1)
        }
        return "Any"
    }

    Bool sameType(String a, String b) {
        if a == b {
            return true
        }
        if self.isListType(a) && self.isListType(b) {
            return self.elementType(a) == self.elementType(b)
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
            }
            if n.kind == "Protocol" {
                self.protocolNames.push(n.text)
            }
            if n.kind == "Class" || n.kind == "Struct" {
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
            if n.kind == "Class" || n.kind == "Struct" {
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
        if st.kind == "Break" || st.kind == "Continue" {
            return
        }
        if st.kind == "Assign" {
            if st.kids.length() < 2 {
                self.fail("SEM-005", "malformed assignment", st)
                return
            }
            String lt = self.typeOf(st.kids.get(0))
            String rt = self.typeOf(st.kids.get(1))
            if lt != "Error" && rt != "Error" && lt != rt && !(self.isEmptyArray(st.kids.get(1)) && self.isListType(lt)) {
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
                String it = self.typeOf(st.kids.get(0))
                if it != "Error" && !self.sameType(it, ty) && !(self.isEmptyArray(st.kids.get(0)) && self.isListType(ty)) {
                    self.fail("SEM-003", "cannot initialize " + ty + " with " + it, st)
                }
            }
            return
        }
        if st.kind == "Return" {
            if st.kids.length() == 0 {
                if self.curRet != "Unit" {
                    self.fail("SEM-003", "return value required, got Unit", st)
                }
            } else {
                String t = self.typeOf(st.kids.get(0))
                if t != "Error" && t != self.curRet {
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
            i = i + 1
        }
        return false
    }

    AstNode classNode(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if (n.kind == "Class" || n.kind == "Struct") && n.text == name {
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
        if n.kind == "String" {
            return "String"
        }
        if n.kind == "Char" {
            return "Char"
        }
        if n.kind == "Bool" {
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
        if n.kind == "New" {
            if !self.knownType(n.text) {
                self.fail("SEM-005", "unknown class: " + n.text, n)
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
            if lt != "Int" || rt != "Int" {
                self.fail("SEM-003", "operator " + n.text + " needs Int, got " + lt + "/" + rt, n)
                return "Error"
            }
            return "Int"
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
            Int ei = 0
            while ei < self.enumNames.length() {
                if self.enumNames.get(ei) == bt {
                    return bt
                }
                ei = ei + 1
            }
            Int fi = self.findField(bt, n.text)
            if fi >= 0 {
                return self.fieldTypes.get(fi)
            }
            return "Any"
        }
        self.fail("SEM-001", "unsupported expression: " + n.kind, n)
        return "Error"
    }

    String checkCall(AstNode n) {
        Int argc = n.kids.length()
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
            if argc != 1 {
                self.fail("SEM-004", n.text + " expects 1 argument, got " + str(argc), n)
                return "Error"
            }
            self.typeOf(n.kids.get(0))
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
            if bt == "String" {
                if mth == "length" {
                    return "Int"
                }
                if mth == "indexOf" {
                    return "Int"
                }
                if mth == "substring" {
                    return "String"
                }
                if mth == "startsWith" {
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
                    return "Unit"
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
                if mth == "push" {
                    return "Unit"
                }
                if mth == "remove" {
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
                if mth == "getOr" {
                    return self.mapValueType(bt)
                }
                if mth == "put" {
                    return "Unit"
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
                String at = self.typeOf(n.kids.get(ai))
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
            String at = self.typeOf(n.kids.get(i))
            if at != "Error" && at != want.get(i) {
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

    CGen(AstNode program) {
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

    String ctype(String ty) {
        if ty == "Int" {
            return "int64_t"
        }
        if ty == "String" {
            return "rt_string *"
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
        if ty == "Long" || ty == "Int64" {
            return "int64_t"
        }
        if ty == "Void" {
            return "void"
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
        if self.isClass(ty) {
            return "xn_Cls_" + ty + " *"
        }
        if self.isEnumName(ty) {
            return "int64_t"
        }
        self.fail("unsupported type: " + ty)
        return "int64_t"
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
        if et == "Int" || et == "Long" || et == "Int64" || self.isEnumName(et) {
            return "xn_arr_i"
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
        return self.arrayCName(ty) + "_get(" + arr + ", " + idx + ")"
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

    Bool isClass(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if (n.kind == "Class" || n.kind == "Struct") && n.text == name {
                return true
            }
            i = i + 1
        }
        return false
    }

    AstNode classNode(String name) {
        Int i = 0
        while i < self.program.kids.length() {
            AstNode n = self.program.kids.get(i)
            if (n.kind == "Class" || n.kind == "Struct") && n.text == name {
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

    String typeOf(AstNode n) {
        if n.kind == "Int" {
            return "Int"
        }
        if n.kind == "String" {
            return "String"
        }
        if n.kind == "Bool" {
            return "Bool"
        }
        if n.kind == "Char" {
            return "Char"
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
            return "Int"
        }
        if n.kind == "Try" {
            if n.kids.length() == 0 {
                return "Any"
            }
            return self.resultValue(self.typeOf(n.kids.get(0)))
        }
        if n.kind == "Call" {
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
            Int dot = lastDot(n.text)
            if dot >= 0 {
                String base = n.text.substring(0, dot)
                String mth = n.text.substring(dot + 1, n.text.length() - dot - 1)
                String bt = self.pathType(base)
                if bt == "String" {
                    if mth == "length" || mth == "indexOf" {
                        return "Int"
                    }
                    if mth == "substring" {
                        return "String"
                    }
                    if mth == "startsWith" {
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
                        return "Unit"
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
                    if mth == "put" {
                        return "Unit"
                    }
                    if mth == "getOr" {
                        return self.mapValue(bt)
                    }
                }
                String mr = self.methodRet(bt, mth)
                if mr != "Any" {
                    return mr
                }
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
        if n.kind == "String" {
            return "rt_string_from_c(" + n.text + ")"
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
            return "(" + a + " " + n.text + " " + b + ")"
        }
        if n.kind == "Call" {
            Int ffi = ffiIndex(n.text)
            if ffi >= 0 {
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
                return "(" + self.ctype(self.curRet) + "){1, " + a + ", 0}"
            }
            if n.text == "Err" {
                String a = "rt_string_from_c(\"\")"
                if n.kids.length() > 0 {
                    a = self.expr(n.kids.get(0))
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
                if at == "Bool" {
                    return "xn_print_bool(" + av + ")"
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
                return "xn_str_int(" + av + ")"
            }
            Int dot = lastDot(n.text)
            if dot >= 0 {
                String base = n.text.substring(0, dot)
                String mth = n.text.substring(dot + 1, n.text.length() - dot - 1)
                String bv = self.pathExpr(base)
                String bt = self.pathType(base)
                if bt == "String" {
                    if mth == "length" {
                        return "((int64_t)" + bv + "->len)"
                    }
                    if mth == "indexOf" {
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
                    if mth == "startsWith" {
                        if n.kids.length() > 0 {
                            return "xn_str_startswith(" + bv + ", " + self.expr(n.kids.get(0)) + ")"
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
                        return "((" + bv + ").value)"
                    }
                    if mth == "error" {
                        return "((" + bv + ").error)"
                    }
                    if mth == "unwrapOr" {
                        String d = "0"
                        if n.kids.length() > 0 {
                            d = self.expr(n.kids.get(0))
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
                String b = "xn_Cls_" + bt + "_" + mth + "(" + bv
                Int di = 0
                while di < n.kids.length() {
                    b = b + ", " + self.expr(n.kids.get(di))
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
        if st.kind == "Break" {
            self.emit(indent + "break;")
            return
        }
        if st.kind == "Continue" {
            self.emit(indent + "continue;")
            return
        }
        if st.kind == "Assign" {
            if st.kids.length() >= 2 {
                String lhs = self.expr(st.kids.get(0))
                AstNode rv = st.kids.get(1)
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
            self.blockBody(st.kids.get(1), indent + "    ")
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
        if st.kind == "While" {
            if st.kids.length() < 2 {
                self.fail("malformed while")
                return
            }
            self.emit(indent + "while (" + self.expr(st.kids.get(0)) + ") {")
            self.blockBody(st.kids.get(1), indent + "  ")
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

    String methodSig(AstNode m, String cls) {
        String ret = self.ctype(self.retNode(m).text)
        String sig = "static " + ret + " xn_Cls_" + cls + "_" + m.text + "(xn_Cls_" + cls + " *self"
        List<AstNode> ps = self.paramsOf(m)
        Int i = 0
        while i < ps.length() {
            List<String> parts = ps.get(i).text.split(" ")
            if parts.length() >= 2 {
                sig = sig + ", " + self.ctype(parts.get(0)) + " " + parts.get(1)
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
        self.emit("typedef struct xn_Cls_" + cn + " {")
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
        self.emit("} xn_Cls_" + cn + ";")
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
        self.emit("  xn_Cls_" + cn + " *o = (xn_Cls_" + cn + " *)rt_gc_new(&RT_TYPE_XN_" + cn + ");")
        self.emit("  memset((char *)o + sizeof(rt_header), 0, sizeof(xn_Cls_" + cn + ") - sizeof(rt_header));")
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
                    self.emit("  o->" + fn + " = " + init + ";")
                }
            }
            i = i + 1
        }
        if ctor.kind == "Ctor" {
            self.curClass = cn
            self.popTo(0)
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
        self.emit("  return o;")
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
        self.emit("#include \"rt.h\"")
        self.emit("#include \"rt_gc.h\"")
        self.emit("#include \"xrt.h\"")
        self.emit("#include <stdint.h>")
        self.emit("#include <stdio.h>")
        self.emit("#include <stdlib.h>")
        self.emit("#include <unistd.h>")
        self.emit("#include <string.h>")
        self.emit("")
        self.emit("static void xn_print_int(int64_t v) { printf(\"%lld\\n\", (long long)v); }")
        self.emit("static void xn_print_bool(int v) { printf(v ? \"true\\n\" : \"false\\n\"); }")
        self.emit("static void xn_print_str(rt_string *s) { printf(\"%.*s\\n\", (int)s->len, s->bytes); }")
        self.emit("static rt_string *xn_str_int(int64_t v) { char buf[32]; snprintf(buf, sizeof(buf), \"%lld\", (long long)v); return rt_string_from_c(buf); }")
        self.emit("static rt_string *xn_str_substr(rt_string *s, int64_t start, int64_t n) { if (start < 0) { start = 0; } if (n < 0) { n = 0; } if ((size_t)start > s->len) { start = (int64_t)s->len; } if ((size_t)(start + n) > s->len) { n = (int64_t)s->len - start; } rt_string *out = rt_string_alloc((size_t)n); if (n > 0) { memcpy(out->bytes, s->bytes + start, (size_t)n); } out->bytes[n] = 0; return out; }")
        self.emit("static int64_t xn_str_indexof(rt_string *s, rt_string *sub) { if (sub->len == 0) { return 0; } if (sub->len > s->len) { return -1; } for (size_t i = 0; i + sub->len <= s->len; i++) { if (memcmp(s->bytes + i, sub->bytes, sub->len) == 0) { return (int64_t)i; } } return -1; }")
        self.emit("static rt_string *xn_concat(rt_string *a, rt_string *b) { size_t n = a->len + b->len; rt_string *r = rt_string_alloc(n); memcpy(r->bytes, a->bytes, a->len); memcpy(r->bytes + a->len, b->bytes, b->len); r->bytes[n] = 0; return r; }")
        self.emit("")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_arr_i;")
        self.emit("static const rt_type RT_TYPE_XN_ARR_I = { \"List\", sizeof(xn_arr_i), NULL, NULL };")
        self.emit("static xn_arr_i *xn_arr_i_new(size_t cap) { xn_arr_i *a = (xn_arr_i *)rt_gc_new(&RT_TYPE_XN_ARR_I); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_i) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (int64_t *)malloc(sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } return a; }")
        self.emit("static void xn_arr_i_push(xn_arr_i *a, int64_t v) { if (a->len == a->cap) { a->cap *= 2; a->data = (int64_t *)realloc(a->data, sizeof(int64_t) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }")
        self.emit("static int64_t xn_arr_i_get(const xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }")
        self.emit("static void xn_arr_i_remove(xn_arr_i *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **data; } xn_arr_s;")
        self.emit("static const rt_type RT_TYPE_XN_ARR_S = { \"List\", sizeof(xn_arr_s), NULL, NULL };")
        self.emit("static xn_arr_s *xn_arr_s_new(size_t cap) { xn_arr_s *a = (xn_arr_s *)rt_gc_new(&RT_TYPE_XN_ARR_S); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_s) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (rt_string **)malloc(sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } return a; }")
        self.emit("static void xn_arr_s_push(xn_arr_s *a, rt_string *v) { if (a->len == a->cap) { a->cap *= 2; a->data = (rt_string **)realloc(a->data, sizeof(rt_string *) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }")
        self.emit("static rt_string *xn_arr_s_get(const xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }")
        self.emit("static void xn_arr_s_remove(xn_arr_s *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; void **data; } xn_arr_o;")
        self.emit("static const rt_type RT_TYPE_XN_ARR_O = { \"List\", sizeof(xn_arr_o), NULL, NULL };")
        self.emit("static xn_arr_o *xn_arr_o_new(size_t cap) { xn_arr_o *a = (xn_arr_o *)rt_gc_new(&RT_TYPE_XN_ARR_O); memset((char *)a + sizeof(rt_header), 0, sizeof(xn_arr_o) - sizeof(rt_header)); a->cap = cap ? cap : 4; a->data = (void **)malloc(sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } return a; }")
        self.emit("static void xn_arr_o_push(xn_arr_o *a, void *v) { if (a->len == a->cap) { a->cap *= 2; a->data = (void **)realloc(a->data, sizeof(void *) * a->cap); if (a->data == NULL) { abort(); } } a->data[a->len++] = v; }")
        self.emit("static void *xn_arr_o_get(const xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } return a->data[i]; }")
        self.emit("static void xn_arr_o_remove(xn_arr_o *a, int64_t i) { if (i < 0 || (size_t)i >= a->len) { abort(); } for (size_t j = (size_t)i; j + 1 < a->len; j++) { a->data[j] = a->data[j + 1]; } a->len--; }")
        self.emit("static int xn_str_startswith(rt_string *s, rt_string *p) { if (p->len > s->len) { return 0; } return memcmp(s->bytes, p->bytes, p->len) == 0 ? 1 : 0; }")
        self.emit("static xn_arr_s *xn_str_split(rt_string *s, rt_string *sep) { xn_arr_s *out = xn_arr_s_new(4); if (sep->len == 0) { xn_arr_s_push(out, s); return out; } size_t start = 0; size_t i = 0; while (i + sep->len <= s->len) { if (memcmp(s->bytes + i, sep->bytes, sep->len) == 0) { size_t n = i - start; rt_string *p = rt_string_alloc(n); if (n > 0) { memcpy(p->bytes, s->bytes + start, n); } p->bytes[n] = 0; xn_arr_s_push(out, p); i = i + sep->len; start = i; } else { i++; } } { size_t n = s->len - start; rt_string *p = rt_string_alloc(n); if (n > 0) { memcpy(p->bytes, s->bytes + start, n); } p->bytes[n] = 0; xn_arr_s_push(out, p); } return out; }")
        self.emit("static rt_string *xn_arr_s_join(xn_arr_s *a, rt_string *sep) { size_t n = 0; for (size_t i = 0; i < a->len; i++) { n += a->data[i]->len; if (i > 0) { n += sep->len; } } rt_string *r = rt_string_alloc(n); size_t off = 0; for (size_t i = 0; i < a->len; i++) { if (i > 0) { memcpy(r->bytes + off, sep->bytes, sep->len); off += sep->len; } memcpy(r->bytes + off, a->data[i]->bytes, a->data[i]->len); off += a->data[i]->len; } r->bytes[n] = 0; return r; }")
        self.emit("")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; rt_string **keys; int64_t *vals; } xn_map_s_i;")
        self.emit("static const rt_type RT_TYPE_XN_MAP_S_I = { \"Map\", sizeof(xn_map_s_i), NULL, NULL };")
        self.emit("static xn_map_s_i *xn_map_s_i_new(size_t cap) { xn_map_s_i *m = (xn_map_s_i *)rt_gc_new(&RT_TYPE_XN_MAP_S_I); memset((char *)m + sizeof(rt_header), 0, sizeof(xn_map_s_i) - sizeof(rt_header)); m->cap = cap ? cap : 4; m->keys = (rt_string **)malloc(sizeof(rt_string *) * m->cap); m->vals = (int64_t *)malloc(sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } return m; }")
        self.emit("static long xn_map_s_i_find(const xn_map_s_i *m, rt_string *key) { for (size_t i = 0; i < m->len; i++) { if (m->keys[i]->len == key->len && memcmp(m->keys[i]->bytes, key->bytes, key->len) == 0) { return (long)i; } } return -1; }")
        self.emit("static void xn_map_s_i_put(xn_map_s_i *m, rt_string *key, int64_t val) { long i = xn_map_s_i_find(m, key); if (i >= 0) { m->vals[i] = val; return; } if (m->len == m->cap) { m->cap *= 2; m->keys = (rt_string **)realloc(m->keys, sizeof(rt_string *) * m->cap); m->vals = (int64_t *)realloc(m->vals, sizeof(int64_t) * m->cap); if (m->keys == NULL || m->vals == NULL) { abort(); } } m->keys[m->len] = key; m->vals[m->len] = val; m->len++; }")
        self.emit("static int64_t xn_map_s_i_getOr(const xn_map_s_i *m, rt_string *key, int64_t dflt) { long i = xn_map_s_i_find(m, key); return i >= 0 ? m->vals[i] : dflt; }")
        self.emit("")
        self.emit("typedef struct { rt_header hdr; size_t len; size_t cap; int64_t *data; } xn_set_i;")
        self.emit("static const rt_type RT_TYPE_XN_SET_I = { \"Set\", sizeof(xn_set_i), NULL, NULL };")
        self.emit("static xn_set_i *xn_set_i_new(void) { xn_set_i *s = (xn_set_i *)rt_gc_new(&RT_TYPE_XN_SET_I); memset((char *)s + sizeof(rt_header), 0, sizeof(xn_set_i) - sizeof(rt_header)); s->cap = 4; s->data = (int64_t *)malloc(sizeof(int64_t) * s->cap); if (s->data == NULL) { abort(); } return s; }")
        self.emit("static int xn_set_i_has(const xn_set_i *s, int64_t v) { for (size_t i = 0; i < s->len; i++) { if (s->data[i] == v) { return 1; } } return 0; }")
        self.emit("static void xn_set_i_add(xn_set_i *s, int64_t v) { if (xn_set_i_has(s, v)) { return; } if (s->len == s->cap) { s->cap *= 2; s->data = (int64_t *)realloc(s->data, sizeof(int64_t) * s->cap); if (s->data == NULL) { abort(); } } s->data[s->len++] = v; }")
        self.emit("")
        self.emit("static const char *mini_platform(void) { return \"darwin\"; }")
        self.emit("static int32_t mini_file_exists(const char *path_bytes, size_t path_len) { char *p = (char *)malloc(path_len + 1); if (p == NULL) { return 0; } memcpy(p, path_bytes, path_len); p[path_len] = 0; int ok = access(p, F_OK) == 0; free(p); return ok ? 1 : 0; }")
        self.emit("int32_t xdkc_p_resource_exists(const char *path, size_t len);")
        self.emit("const char *xdkc_p_read_resource_text(const char *path, size_t len);")
        self.emit("int64_t xdkc_p_resource_count(void);")
        self.emit("int32_t xdkc_diagnose_rc(const char *bytes, size_t len);")
        self.emit("int32_t xdkc_exit_rc(int32_t code);")
        self.emit("int64_t xdkc_now_mono_ms(void);")
        self.emit("int64_t xdkc_now_wall_ms(void);")
        self.emit("typedef struct { int ok; int64_t value; rt_string *error; } xn_Result_Int_String;")
        self.emit("")
        Int i = 0
        while i < self.program.kids.length() && !self.hasError() {
            AstNode n = self.program.kids.get(i)
            if n.kind == "Enum" {
                Int j = 0
                while j < n.kids.length() {
                    AstNode it = n.kids.get(j)
                    if it.kind == "EnumItem" {
                        self.emit("static const int64_t xn_enum_" + n.text + "_" + it.text + " = " + str(self.enumValue(n.text, it.text)) + ";")
                    }
                    j = j + 1
                }
            }
            if n.kind == "Class" || n.kind == "Struct" {
                self.genClass(n)
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
        self.emit("}")
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
            if n.kind == "Func" && !hasTypeParams(n) {
                self.func(n)
            }
            i = i + 1
        }
        self.emit("int main(void) {")
        self.emit("  xrt_runtime_init();")
        self.emit("  xn_init_globals();")
        self.emit("  int64_t xn_result = xn_main();")
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
        s == "try" || s == "catch" || s == "throw" || s == "defer" ||
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
            i = i + 1
            col = col + 1
            while i < src.length() && isDigit(at(src, i)) {
                i = i + 1
                col = col + 1
            }
            tokens.push(new Token("int", src.substring(start, i - start), startLine, startCol))
            continue
        }

        if c == "$" && next == "\"" {
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
            tokens.push(new Token("string", src.substring(start, i - start), startLine, startCol))
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
            c == "&" || c == "|" || c == "?" || c == "@" {
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
            if f.length() >= 6 {
                ffiNames.push(f.get(2))
                ffiCNames.push(f.get(3))
                ffiRets.push(f.get(5))
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
    if pkg == "xdk.text" || pkg.startsWith("xdk.text.") {
        return "text/mini/Text.x"
    }
    if pkg == "xdk.sys" || pkg.startsWith("xdk.sys.") {
        return "io/mini/Sys.x"
    }
    return ""
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
    Int i = 0
    while i < program.kids.length() {
        AstNode imp = program.kids.get(i)
        if imp.kind == "Import" {
            String rel = xdkFile(imp.text)
            if rel == "" {
                print("mini: unsupported import: " + imp.text)
                return program
            }
            String path = root + "/" + rel
            String isrc = readFile(path)
            if isrc.length() == 0 {
                print("mini: cannot read package: " + imp.text)
                return program
            }
            Parser ip = new Parser(lex(isrc))
            AstNode iprogram = ip.parse()
            if ip.hasError() {
                print(path + ":" + str(ip.errorLine) + ":" + str(ip.errorCol) + ": " + ip.error)
                return program
            }
            Int j = 0
            while j < iprogram.kids.length() {
                AstNode d = iprogram.kids.get(j)
                if d.kind != "Package" && d.kind != "Import" {
                    program.add(d)
                }
                j = j + 1
            }
        }
        i = i + 1
    }
    return program
}

static String argAfter(List<String> args, String flag) {
    Int i = 0
    while i + 1 < args.length() {
        if args.get(i) == flag {
            return args.get(i + 1)
        }
        i = i + 1
    }
    return ""
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
    if cmd == "--version" {
        print("mini 0.1.0")
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
        CGen g = new CGen(program)
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
