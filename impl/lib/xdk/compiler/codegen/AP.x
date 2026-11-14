package xdk.compiler.codegen; import xdk.sys
import xdk.runtime

// xnullc Result/try/defer（XNull 版 AST -> C）。
//
// 输入：<entryPath> <xnast v1 AST dump>
// 输出：与 Go `xnull build --emit-c` 口径一致的 C 文本。
// 覆盖：Result 实例化、Ok/Err、isOk/isErr/value/error/unwrapOr、try、defer/errdefer、throw。































class AP {
    String s = ""
    Bytes b
    Int p = 0
    Int n = 0
    AP(String t) { self.s = t; self.b = Bytes.fromString(t); self.n = t.length() }
    Int ch(Int i) {
        if i < 0 { return -1 }
        if i >= self.n { return -1 }
        return self.b.get(i)
    }
    void ws() { while self.p < self.n && self.ch(self.p) == 32 { self.p = self.p + 1 } }
    String bare() {
        Int st = self.p
        while self.p < self.n {
            Int c = self.ch(self.p)
            if c == 32 || c == 40 || c == 41 { break }
            self.p = self.p + 1
        }
        return self.s.substring(st, self.p - st)
    }
    N val() {
        self.ws()
        if self.ch(self.p) == 40 {
            self.p = self.p + 1
            String name = self.bare()
            N r = new N()
            if name == "slice" {
                r.nm = "slice"
                while true {
                    self.ws()
                    if self.ch(self.p) == 41 { self.p = self.p + 1; break }
                    r.el.push(self.val())
                }
                return r
            }
            r.nm = name
            while true {
                self.ws()
                if self.ch(self.p) == 41 { self.p = self.p + 1; break }
                self.p = self.p + 1
                String f = self.bare()
                N v = self.val()
                self.ws()
                self.p = self.p + 1
                r.fn.push(f)
                r.fv.push(v)
            }
            return r
        }
        N r = new N()
        r.sc = true
        if self.ch(self.p) == 34 {
            Int st = self.p
            self.p = self.p + 1
            while true {
                Int c = self.ch(self.p)
                if c == 92 { self.p = self.p + 2; continue }
                if c == 34 { self.p = self.p + 1; break }
                self.p = self.p + 1
            }
            r.raw = self.s.substring(st, self.p - st)
            return r
        }
        Int st = self.p
        while self.p < self.n {
            Int c = self.ch(self.p)
            if c == 32 || c == 40 || c == 41 { break }
            self.p = self.p + 1
        }
        r.raw = self.s.substring(st, self.p - st)
        return r
    }
}
