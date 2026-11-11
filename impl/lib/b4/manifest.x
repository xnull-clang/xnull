// B4b-03a：消费 xpd TSV，输出工程模型（模块列表、依赖边、拓扑序）。
//
// 用法：
//   xmanifest <root.tsv> [<module.tsv> …]
//
// 约定：第 1 个 TSV 是聚合根（pom），其 `module` 行按声明顺序给出模块相对目录，
// 后续 TSV 依次对应这些目录。依赖版本为空时用根的 `managed` 兜底。
//
// 输出（制表符分隔）：
//   # xmanifest v1
//   project  <g>:<a>            <version> <packaging>
//   module   <rel>  <g>:<a>     <version> <packaging>
//   edge     <fromArtifact> <coord> <version|?>
//   order    <rel,rel,…>
//   error    <文本>
import xdk.sys

class Proj {
    String groupId = ""
    String artifactId = ""
    String version = ""
    String packaging = ""
    List<String> modules = []
    List<String> managed = []
    List<String> deps = []
}

static List<String> linesOf(String path) {
    String src = readFileText(path)
    return src.split("\n")
}

static String[] partsOf(String line) {
    return line.split("\t")
}

class Loader {
    Proj load(String path) {
        Proj p = new Proj()
        List<String> ls = linesOf(path)
        Int i = 0
        while i < ls.length() {
            String line = ls.get(i)
            if line != "" && line.substring(0, 1) != "#" {
                String[] ps = partsOf(line)
                if ps.length() >= 2 {
                    String tag = ps.get(0)
                    if tag == "field" && ps.length() >= 3 {
                        if ps.get(1) == "groupId" { p.groupId = ps.get(2) }
                        else if ps.get(1) == "artifactId" { p.artifactId = ps.get(2) }
                        else if ps.get(1) == "version" { p.version = ps.get(2) }
                        else if ps.get(1) == "packaging" { p.packaging = ps.get(2) }
                    } else if tag == "module" {
                        p.modules.push(ps.get(1))
                    } else if tag == "managed" && ps.length() >= 3 {
                        p.managed.push(ps.get(1) + "\t" + ps.get(2))
                    } else if tag == "dep" && ps.length() >= 2 {
                        String ver = ""
                        if ps.length() >= 3 { ver = ps.get(2) }
                        p.deps.push(ps.get(1) + "\t" + ver)
                    }
                }
            }
            i = i + 1
        }
        return p
}
}

static String coordOf(Proj p) {
    return p.groupId + ":" + p.artifactId
}

// 版本查找：清单自身版本优先，其次根 dependencyManagement。
static String verOf(Proj root, String coord, String own) {
    if own != "" { return own }
    Int i = 0
    while i < root.managed.length() {
        String[] kv = partsOf(root.managed.get(i))
        if kv.length() >= 2 && kv.get(0) == coord { return kv.get(1) }
        i = i + 1
    }
    return "?"
}

static Int main(String[] args) {
    if args.length() == 0 {
        print("xmanifest: 需要 <root.tsv> [<module.tsv> …]")
        return 2
    }
    Loader ld = new Loader()
    Proj root = ld.load(args[0])
    List<Proj> mods = []
    Int i = 1
    while i < args.length() {
        mods.push(ld.load(args[i]))
        i = i + 1
    }
    print("# xmanifest v1")
    print("project\t" + coordOf(root) + "\t" + root.version + "\t" + root.packaging)
    List<String> edges = []
    Int bad = 0
    // 根工程自身的依赖（单工程 app/library 也要给出边）
    Int rj = 0
    while rj < root.deps.length() {
        String[] rkv = partsOf(root.deps.get(rj))
        String rcoord = rkv.get(0)
        String rown = ""
        if rkv.length() >= 2 { rown = rkv.get(1) }
        String rver = verOf(root, rcoord, rown)
        if rver == "?" { bad = bad + 1 }
        edges.push(root.artifactId + "\t" + rcoord + "\t" + rver)
        rj = rj + 1
    }
    i = 0
    while i < mods.length() {
        Proj m = mods.get(i)
        String rel = ""
        if i < root.modules.length() { rel = root.modules.get(i) }
        print("module\t" + rel + "\t" + coordOf(m) + "\t" + m.version + "\t" + m.packaging)
        Int j = 0
        while j < m.deps.length() {
            String[] kv = partsOf(m.deps.get(j))
            String coord = kv.get(0)
            String own = ""
            if kv.length() >= 2 { own = kv.get(1) }
            String ver = verOf(root, coord, own)
            if ver == "?" { bad = bad + 1 }
            edges.push(m.artifactId + "\t" + coord + "\t" + ver)
            j = j + 1
        }
        i = i + 1
    }
    i = 0
    while i < edges.length() {
        print("edge\t" + edges.get(i))
        i = i + 1
    }
    // 拓扑序：只统计指向本聚合内模块的边（Kahn，同层按声明顺序）。
    List<String> order = []
    List<Int> done = []
    i = 0
    while i < mods.length() {
        done.push(0)
        i = i + 1
    }
    Int rounds = 0
    while order.length() < mods.length() && rounds <= mods.length() {
        rounds = rounds + 1
        i = 0
        while i < mods.length() {
            if done.get(i) == 0 {
                Bool ok = true
                Int j = 0
                while j < edges.length() {
                    String[] e = partsOf(edges.get(j))
                    if e.get(0) == mods.get(i).artifactId {
                        Int k = 0
                        while k < mods.length() {
                            if mods.get(k).groupId + ":" + mods.get(k).artifactId == e.get(1) && k != i {
                                if done.get(k) == 0 { ok = false }
                            }
                            k = k + 1
                        }
                    }
                    j = j + 1
                }
                if ok {
                    done.set(i, 1)
                    order.push(mods.get(i).artifactId)
                }
            }
            i = i + 1
        }
    }
    String ord = ""
    i = 0
    while i < order.length() {
        if i > 0 { ord = ord + "," }
        ord = ord + order.get(i)
        i = i + 1
    }
    print("order\t" + ord)
    if order.length() < mods.length() {
        print("error\t依赖环或无法排序")
        return 1
    }
    if bad > 0 {
        print("error\t" + str(bad) + " 条依赖无版本（自身与 dependencyManagement 均未提供）")
        return 1
    }
    return 0
}
