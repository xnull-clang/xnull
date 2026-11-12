// B4b-04a：`tree` / `why`（输出与 Go `xnull tree|why` 对齐）。
//
// 用法（TSV 由 xnull-build.sh 用 xpd 预处理）：
//   deps tree <root.tsv> [<module.tsv> …]
//   deps why <coord> <root.tsv> [<module.tsv> …]
//
// 图模型：把「根工程的直接依赖」与「各模块自身的依赖」展平成边表，
// 从根做 BFS（最近优先、同深度先到先得，等价 Go ResolveGraph 的 nearest-wins），
// 记录版本/父节点/深度；tree 子节点与 why 路径按坐标字节序输出。

import xdk.sys

class Ctx {
    // 边表（from 为空表示根工程）
    List<String> froms = []
    List<String> tos = []
    List<String> vers = []
    // 根工程的 dependencyManagement（版本兜底）
    List<String> managedCoords = []
    List<String> managedVers = []
    // BFS 结果
    List<String> coords = []
    List<String> selected = []
    List<String> parents = []
    List<Int> depths = []

    Int find(String coord) {
        Int i = 0
        while i < coords.length() {
            if coords.get(i) == coord { return i }
            i = i + 1
        }
        return -1
    }

    String verFor(String coord, String ver) {
        if ver != "" { return ver }
        Int i = 0
        while i < managedCoords.length() {
            if managedCoords.get(i) == coord { return managedVers.get(i) }
            i = i + 1
        }
        return "?"
    }

    void addNode(String coord, String ver, String parent, Int depth) {
        if coord == "" { return }
        if find(coord) >= 0 { return }
        coords.push(coord)
        selected.push(ver)
        parents.push(parent)
        depths.push(depth)
    }

    void resolve() {
        // 根的直接依赖
        Int i = 0
        while i < froms.length() {
            if froms.get(i) == "" {
                addNode(tos.get(i), verFor(tos.get(i), vers.get(i)), "", 1)
            }
            i = i + 1
        }
        // BFS：按已选节点顺序展开其出边
        i = 0
        while i < coords.length() {
            String c = coords.get(i)
            Int d = depths.get(i)
            Int k = 0
            while k < froms.length() {
                if froms.get(k) == c {
                    addNode(tos.get(k), verFor(tos.get(k), vers.get(k)), c, d + 1)
                }
                k = k + 1
            }
            i = i + 1
        }
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

static String safeJoin(String prefix, String suffix) {
    return prefix + suffix
}

// 解析一个清单 TSV 到图：返回该文件的坐标（"g:a"），边写入 ctx。
static String loadTsv(Ctx g, String path) {
    String group = ""
    String artifact = ""
    String ver = ""
    List<String> depC = []
    List<String> depV = []
    String src = readFileText(path)
    String[] ls = src.split("\n")
    Int i = 0
    while i < ls.length() {
        String line = ls[i]
        if line != "" {
            String[] ps = line.split("\t")
            if ps.length() >= 2 {
                String tag = ps.get(0)
                if tag == "field" && ps.length() >= 3 {
                    String k = ps.get(1)
                    String v = ps.get(2)
                    if k == "groupId" { group = v }
                    else if k == "artifactId" { artifact = v }
                    else if k == "version" { ver = v }
                } else if tag == "managed" && ps.length() >= 3 {
                    g.managedCoords.push(ps.get(1))
                    g.managedVers.push(ps.get(2))
                } else if tag == "dep" {
                    String c = ps.get(1)
                    String v = ""
                    if ps.length() >= 3 { v = ps.get(2) }
                    depC.push(c)
                    depV.push(v)
                }
            }
        }
        i = i + 1
    }
    String coord = group + ":" + artifact
    // 该文件的依赖边：from = 本工程坐标（根工程用 ""）
    String from = coord
    i = 0
    while i < depC.length() {
        g.froms.push(from)
        g.tos.push(depC.get(i))
        g.vers.push(depV.get(i))
        i = i + 1
    }
    return coord + "\t" + ver + "\t" + from
}

static String rootCoord(Ctx g) {
    // from == "" 的边来自根；根坐标不参与 BFS，单独保存
    return ""
}

static String indentOf(Int depth) {
    String s = ""
    Int i = 0
    while i < depth {
        s = s + "  "
        i = i + 1
    }
    return s
}

static void collectChildren(Ctx g, String parent, List<Int> kids) {
    Int i = 0
    while i < g.coords.length() {
        if g.parents.get(i) == parent { kids.push(i) }
        i = i + 1
    }
    Int j = 1
    while j < kids.length() {
        Int cur = kids.get(j)
        Int k = j - 1
        Bool moving = true
        while moving {
            if k < 0 { moving = false }
            else if cmpStr(g.coords.get(kids.get(k)), g.coords.get(cur)) <= 0 { moving = false }
            else {
                kids.set(k + 1, kids.get(k))
                k = k - 1
            }
        }
        kids.set(k + 1, cur)
        j = j + 1
    }
}

static void walk(Ctx g, String parent, Int depth) {
    List<Int> kids = []
    collectChildren(g, parent, kids)
    Int i = 0
    while i < kids.length() {
        Int idx = kids.get(i)
        String line = indentOf(depth + 1) + g.coords.get(idx) + "@" + g.selected.get(idx)
        print(line)
        walk(g, g.coords.get(idx), depth + 1)
        i = i + 1
    }
}

static Int main(String[] args) {
    if args.length() < 2 {
        print("deps: 用法 tree|why …")
        return 2
    }
    String cmd = args[0]
    Int rootAt = 1
    String coord = ""
    if cmd == "why" {
        coord = args[1]
        rootAt = 2
    }
    Ctx g = new Ctx()
    // 根清单：from 记为 ""（根工程的依赖）
    String rootInfo = loadTsv(g, args[rootAt])
    String[] ri = rootInfo.split("\t")
    String rootC = ri.get(0)
    String rootV = ri.get(1)
    // 把根自身的边 from 改成 ""
    Int i = 0
    while i < g.froms.length() {
        if g.froms.get(i) == rootC { g.froms.set(i, "") }
        i = i + 1
    }
    // 其余模块
    i = rootAt + 1
    while i < args.length() {
        loadTsv(g, args[i])
        i = i + 1
    }
    g.resolve()
    if cmd == "tree" {
        print(rootC + "@" + rootV)
        walk(g, "", 0)
        return 0
    }
    Int idx = g.find(coord)
    if idx < 0 {
        print("xnull: 依赖 " + coord + " 未被解析（不在依赖图中）")
        return 2
    }
    String ver = g.selected.get(idx)
    List<String> path = []
    Int cur = idx
    Bool go = true
    while go {
        path.push(g.coords.get(cur) + "@" + g.selected.get(cur))
        if g.parents.get(cur) == "" { go = false }
        else { cur = g.find(g.parents.get(cur)) }
    }
    String p = ""
    Int k = path.length() - 1
    while k >= 0 {
        if p != "" { p = p + " -> " }
        p = p + path.get(k)
        k = k - 1
    }
    print("坐标：" + coord)
    print("版本：" + ver)
    print("路径：" + p)
    String src = "最近优先（路径最短）"
    if g.depths.get(idx) <= 1 { src = "直接依赖" }
    else {
        Int mi = 0
        while mi < g.managedCoords.length() {
            if g.managedCoords.get(mi) == coord {
                if g.managedVers.get(mi) == ver { src = "dependencyManagement 固定" }
            }
            mi = mi + 1
        }
    }
    print("来源：" + src)
    print("深度：" + str(g.depths.get(idx)))
    return 0
}
