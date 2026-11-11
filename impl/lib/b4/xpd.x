// B4b-03a：XPD 清单解析（project 子集）→ 规范化 TSV。
//
// 用法：
//   xpd <path/to/xnull.project>      按文件读入
//   xpd --text <源码字符串>           直接传源码（调试/测试用）
//
// 输出（制表符分隔，条目按字节序排序）：
//   # xpd tsv v1
//   field    groupId|artifactId|version|packaging   <值>
//   module   <相对目录>
//   managed  <group:artifact>   <版本>
//   dep      <group:artifact>   <版本，可空>
//
// 支持子集：project 顶层四字段、modules{module …}、dependencies{dependency c { version = v }}、
// dependencyManagement{dependencies{…}}。其余块跳过（不报错）。
import xdk.sys

class Tok {
    Int k = 0
    String t = ""
}

class Frame {
    String name = ""
    String arg = ""
    String kind = ""
    Bool hasVer = false
}

class Model {
    String groupId = ""
    String artifactId = ""
    String version = ""
    String packaging = ""
    List<String> modules = []
    List<String> managed = []
    List<String> deps = []
}

static Bool isWordByte(Int c) {
    if c >= 48 && c <= 57 { return true }
    if c >= 65 && c <= 90 { return true }
    if c >= 97 && c <= 122 { return true }
    if c == 45 || c == 46 || c == 95 || c == 58 || c == 47 { return true }
    return false
}

// 自由函数在类定义之前发射，不能 new 类；词法/语法放进类方法。
class Ctx {
    List<Tok> lex(String src) {
        List<Tok> toks = []
        Bytes b = Bytes.fromString(src)
        Int n = b.length()
        Int i = 0
        while i < n {
            Int c = b.get(i)
            if c == 10 {
                Tok nl = new Tok()
                nl.k = 6
                toks.push(nl)
                i = i + 1
                continue
            }
            if c == 32 || c == 9 || c == 13 {
                i = i + 1
                continue
            }
            if c == 35 {
                Bool skip = true
                while skip {
                    if i >= n { skip = false }
                    else if b.get(i) == 10 { skip = false }
                    else { i = i + 1 }
                }
                continue
            }
            if c == 123 {
                Tok lb = new Tok()
                lb.k = 3
                toks.push(lb)
                i = i + 1
                continue
            }
            if c == 125 {
                Tok rb = new Tok()
                rb.k = 4
                toks.push(rb)
                i = i + 1
                continue
            }
            if c == 61 {
                Tok eq = new Tok()
                eq.k = 5
                toks.push(eq)
                i = i + 1
                continue
            }
            if c == 34 {
                i = i + 1
                String v = ""
                Bool scanning = true
                while scanning {
                    if i >= n { scanning = false }
                    else if b.get(i) == 34 { scanning = false }
                    else if b.get(i) == 92 && i + 1 < n {
                        v = v + src.substring(i + 1, 1)
                        i = i + 2
                    } else {
                        v = v + src.substring(i, 1)
                        i = i + 1
                    }
                }
                if i < n { i = i + 1 }
                Tok st = new Tok()
                st.k = 2
                st.t = v
                toks.push(st)
                continue
            }
            if isWordByte(c) {
                Int st = i
                Bool inWord = true
                while inWord {
                    if i >= n { inWord = false }
                    else if isWordByte(b.get(i)) { i = i + 1 }
                    else { inWord = false }
                }
                Tok w = new Tok()
                w.k = 1
                w.t = src.substring(st, i - st)
                toks.push(w)
                continue
            }
            i = i + 1
        }
        Tok eof = new Tok()
        eof.k = 0
        toks.push(eof)
        return toks
    }

    String topName(List<Frame> st) {
        if st.length() == 0 { return "" }
        return st.get(st.length() - 1).name
    }

    String parentName(List<Frame> st) {
        if st.length() < 2 { return "" }
        return st.get(st.length() - 2).name
    }

    void putField(Model m, List<Frame> st, String name, String val) {
        if st.length() != 1 { return }
        if name == "groupId" { m.groupId = val }
        else if name == "artifactId" { m.artifactId = val }
        else if name == "version" { m.version = val }
        else if name == "packaging" { m.packaging = val }
    }

    void emitDep(Model m, Frame f, String ver) {
        String line = f.arg + "\t" + ver
        if f.kind == "managed" { m.managed.push(line) } else { m.deps.push(line) }
    }

    Model parse(String src) {
        List<Tok> ts = lex(src)
        Model m = new Model()
        List<Frame> st = []
        Int i = 0
        while ts.get(i).k != 0 {
            Tok t = ts.get(i)
            if t.k == 6 {
                i = i + 1
                continue
            }
            if t.k == 4 {
                if st.length() > 0 {
                    Frame f = st.get(st.length() - 1)
                    if f.kind != "" && !f.hasVer {
                        emitDep(m, f, "")
                    }
                    st.remove(st.length() - 1)
                }
                i = i + 1
                continue
            }
            if t.k != 1 {
                i = i + 1
                continue
            }
            Tok nx = ts.get(i + 1)
            if nx.k == 5 {
                Tok v = ts.get(i + 2)
                if v.k == 1 || v.k == 2 {
                    putField(m, st, t.t, v.t)
                    if topName(st) == "dependency" && t.t == "version" {
                        Frame f = st.get(st.length() - 1)
                        if f.kind != "" {
                            f.hasVer = true
                            emitDep(m, f, v.t)
                        }
                    }
                }
                i = i + 3
                continue
            }
            String arg = ""
            Int j = i + 1
            if nx.k == 1 || nx.k == 2 {
                arg = nx.t
                j = j + 1
            }
            // `module <rel>` 是无花括号的块：直接记模块。
            if t.t == "module" && topName(st) == "modules" {
                m.modules.push(arg)
                i = j
                continue
            }
            if ts.get(j).k == 3 {
                Frame f = new Frame()
                f.name = t.t
                f.arg = arg
                st.push(f)
                if t.t == "module" && parentName(st) == "modules" {
                    m.modules.push(arg)
                }
                if t.t == "dependency" && parentName(st) == "dependencies" {
                    f.kind = "dep"
                    if st.length() >= 3 && st.get(st.length() - 3).name == "dependencyManagement" {
                        f.kind = "managed"
                    }
                }
                i = j + 1
                continue
            }
            i = j
        }
        return m
    }
}

static Int cmpStr(String a, String b) {
    Bytes x = Bytes.fromString(a)
    Bytes y = Bytes.fromString(b)
    Int n = x.length()
    if y.length() < n { n = y.length() }
    Int i = 0
    while i < n {
        Int cx = x.get(i)
        Int cy = y.get(i)
        if cx != cy {
            if cx < cy { return -1 }
            return 1
        }
        i = i + 1
    }
    if x.length() == y.length() { return 0 }
    if x.length() < y.length() { return -1 }
    return 1
}

static void sortLines(List<String> xs) {
    Int i = 1
    while i < xs.length() {
        String v = xs.get(i)
        Int j = i - 1
        Bool moving = true
        while moving {
            if j < 0 {
                moving = false
            } else if cmpStr(xs.get(j), v) <= 0 {
                moving = false
            } else {
                xs.set(j + 1, xs.get(j))
                j = j - 1
            }
        }
        xs.set(j + 1, v)
        i = i + 1
    }
}

static Int main(String[] args) {
    if args.length() == 0 {
        print("xpd: 需要 <path> 或 --text <源码>")
        return 2
    }
    String src = ""
    if args[0] == "--text" {
        if args.length() < 2 { return 2 }
        src = args[1]
    } else {
        src = readFileText(args[0])
    }
    Ctx c = new Ctx()
    Model m = c.parse(src)
    List<String> lines = []
    // 字段固定顺序；module 保持声明顺序；managed/dep 排序。
    if m.groupId != "" { lines.push("field\tgroupId\t" + m.groupId) }
    if m.artifactId != "" { lines.push("field\tartifactId\t" + m.artifactId) }
    if m.version != "" { lines.push("field\tversion\t" + m.version) }
    if m.packaging != "" { lines.push("field\tpackaging\t" + m.packaging) }
    Int i = 0
    while i < m.modules.length() {
        lines.push("module\t" + m.modules.get(i))
        i = i + 1
    }
    sortLines(m.managed)
    i = 0
    while i < m.managed.length() {
        lines.push("managed\t" + m.managed.get(i))
        i = i + 1
    }
    sortLines(m.deps)
    i = 0
    while i < m.deps.length() {
        lines.push("dep\t" + m.deps.get(i))
        i = i + 1
    }
    print("# xpd tsv v1")
    i = 0
    while i < lines.length() {
        print(lines.get(i))
        i = i + 1
    }
    return 0
}
