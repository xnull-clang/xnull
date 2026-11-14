// XNull 版词法器（Go xfront.Lex 的 L1 token dump 对照实现）。
// 只输出 token/AST 层数据，不依赖 Go xfront；lex 诊断以 code/line/col 输出。
// 覆盖：注释/BOM/CRLF、自动分号、数字/字符/字符串/插值（基础）、关键字、运算符。
// 新增 --file <path> 文件输入模式（import xdk.sys 提供 readFileText）。
package xdk.compiler.parser; import xdk.sys






































































































































































































































































































































































































































































































































































































































































































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
