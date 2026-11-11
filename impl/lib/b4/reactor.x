// B4b-03b-1：聚合工程最小构建（reactor）。
//
// 用法：
//   reactor build-project <dir> --xpd <xpd> --xmanifest <xmanifest>
//           --xnullc <xnullc> --xnast <xnast> --runtime <impl/runtime> --out <目标目录>
//
// 流程：
//   1. xpd 解析根与各模块清单 → TSV；
//   2. xmanifest 合成模块/依赖边/拓扑序；
//   3. 按拓扑序逐模块：xnast --ast → 原生 xnullc 生成 C；
//      library → cc -c（-Dmain=xn_unused_<模块> 避免与 app 的 main 冲突）；
//      app     → 记录 C，最后与全部 library 对象 + runtime + 空资源表链接。
//
// 未支持（B4b-03b-2/03c）：build.entryFile、sourceRoot、跨模块 import、资源表（resman）、配置。
// 模块入口固定为 <dir>/<rel>/src/main/x/main.x。
import xdk.sys

class Mod {
    String rel = ""
    String coord = ""
    String ver = ""
    String packaging = ""
    String obj = ""
    String cf = ""
    String entry = ""
}

class Args {
    String dir = ""
    String xpd = "/tmp/xpd"
    String xmanifest = "/tmp/xmanifest"
    String xnullc = "/tmp/xn-s4"
    String xnast = "/tmp/xnast"
    String runtime = ""
    String outdir = ""
    String resman = ""
    String artifact = ""
    String config = ""
}

// 文件名/符号名安全化：非字母数字一律换成下划线（`lib-core` → `lib_core`）。
static String safe(String rel) {
    String r = ""
    Int i = 0
    while i < rel.length() {
        String c = rel.substring(i, 1)
        Bytes b = Bytes.fromString(c)
        Int v = b.get(0)
        if v >= 48 && v <= 57 { r = r + c }
        else if v >= 65 && v <= 90 { r = r + c }
        else if v >= 97 && v <= 122 { r = r + c }
        else { r = r + "_" }
        i = i + 1
    }
    return r
}

static String resTable() {
    return "/* 由 xnull-build 生成：零资源工程空表（S8 §5.6） */\n"
        + "#include <stddef.h>\n"
        + "#include <string.h>\n"
        + "size_t xrt_resource_count(void) { return 0; }\n"
        + "int xrt_resource_get(const char *name, size_t nlen,\n"
        + "                     const unsigned char **out, size_t *out_len) {\n"
        + "    (void)name; (void)nlen;\n"
        + "    *out = 0; *out_len = 0;\n"
        + "    return 1;\n"
        + "}\n"
        + "int xrt_resource_at(size_t i, const char **name, size_t *nlen,\n"
        + "                    const unsigned char **out, size_t *out_len) {\n"
        + "    (void)i;\n"
        + "    *name = 0; *nlen = 0; *out = 0; *out_len = 0;\n"
        + "    return 1;\n"
        + "}\n"
}

static String runtimeSrcs(String rt) {
    List<String> names = ["rt.c", "rt_gc.c", "rt_policy.c", "rt_weak.c", "xrt_abi.c",
        "rt_std_runtime.c", "rt_std_text.c", "rt_std_sys.c", "rt_std_bytes.c",
        "rt_std_net.c", "rt_task.c", "rt_sync.c", "rt_std_res.c", "rt_std_res_empty.c"]
    String s = ""
    Int i = 0
    while i < names.length() {
        s = s + " \"" + rt + "/" + names.get(i) + "\""
        i = i + 1
    }
    return s
}

class Reactor {
    Int run(Args a) {
        if a.dir == "" || a.outdir == "" || a.runtime == "" {
            print("reactor: 需要 <dir>、--runtime、--out")
            return 2
        }
        procStatus("mkdir -p \"" + a.outdir + "\"")
        String rootTsv = a.outdir + "/root.tsv"
        Int32 st = procStatus("\"" + a.xpd + "\" \"" + a.dir + "/xnull.project\" > \"" + rootTsv + "\"")
        if st != 0 { print("reactor: 根清单解析失败"); return 1 }
        List<String> rels = []
        String rootText = readFileText(rootTsv)
        String[] rl = rootText.split("\n")
        Int i = 0
        while i < rl.length() {
            if rl[i] != "" {
                String rline = rl[i]
                String[] ps = rline.split("\t")
                if ps.length() >= 2 && ps.get(0) == "module" { rels.push(ps.get(1)) }
            }
            i = i + 1
        }
        List<String> tsvs = [rootTsv]
        i = 0
        while i < rels.length() {
            String f = a.outdir + "/m-" + safe(rels.get(i)) + ".tsv"
            st = procStatus("\"" + a.xpd + "\" \"" + a.dir + "/" + rels.get(i) + "/xnull.project\" > \"" + f + "\"")
            if st != 0 { print("reactor: 模块清单解析失败：" + rels.get(i)); return 1 }
            tsvs.push(f)
            i = i + 1
        }
        String model = a.outdir + "/model.tsv"
        String cmd = "\"" + a.xmanifest + "\""
        i = 0
        while i < tsvs.length() {
            cmd = cmd + " \"" + tsvs.get(i) + "\""
            i = i + 1
        }
        st = procStatus(cmd + " > \"" + model + "\"")
        if st != 0 { print("reactor: 工程模型合成失败（依赖无版本或成环）"); return 1 }
        List<Mod> mods = []
        String order = ""
        String modelText = readFileText(model)
        String[] ml = modelText.split("\n")
        i = 0
        while i < ml.length() {
            if ml[i] != "" {
                String mline = ml[i]
                String[] ps = mline.split("\t")
                if ps.length() >= 5 && ps.get(0) == "module" {
                    Mod m = new Mod()
                    m.rel = ps.get(1)
                    m.coord = ps.get(2)
                    m.ver = ps.get(3)
                    m.packaging = ps.get(4)
                    mods.push(m)
                } else if ps.length() >= 2 && ps.get(0) == "order" {
                    order = ps.get(1)
                }
            }
            i = i + 1
        }
        List<String> seq = []
        if order != "" {
            String[] os = order.split(",")
            i = 0
            while i < os.length() {
                seq.push(os.get(i))
                i = i + 1
            }
        }
        String resC = a.outdir + "/res.c"
        writeFileText(resC, resTable())
        if a.resman != "" {
            // 约定：app 模块的资源目录（单层）；由 shell 展开文件列表
            Int k = 0
            String resDir = ""
            while k < mods.length() {
                if mods.get(k).packaging == "app" { resDir = a.dir + "/" + mods.get(k).rel + "/src/main/resources" }
                k = k + 1
            }
            if resDir != "" && pathExists(resDir) {
                String rcmd = "\"" + a.resman + "\" \"" + resC + "\" \"" + resDir + "\" \"" + resDir + "\"/* > \"" + a.outdir + "/resources.log\" 2>/dev/null"
                Int32 rrc = procStatus(rcmd)
                if rrc != 0 {
                    writeFileText(resC, resTable())
                    print("resource\t（空表：resman 未找到文件）")
                } else {
                    print("resource\t\"" + resC + "\"")
                }
            }
        }
        // 逐模块：emit-c → library 出对象 / app 留 C
        i = 0
        while i < seq.length() {
            Int k = 0
            Mod m = new Mod()
            while k < mods.length() {
                if mods.get(k).rel == seq.get(i) { m = mods.get(k) }
                k = k + 1
            }
            String id = safe(m.rel)
            String relEntry = "src/main/x/main.x"
            if a.config != "" {
                String cfgOut = a.outdir + "/cfg-" + id + ".tsv"
                Int32 crc = procStatus("\"" + a.config + "\" \"" + a.dir + "/" + m.rel + "/xnull.project\" > \"" + cfgOut + "\"")
                if crc == 0 {
                    String cfgText = readFileText(cfgOut)
                    String[] cl = cfgText.split("\n")
                    Int ci = 0
                    while ci < cl.length() {
                        String cline = cl[ci]
                        String[] cp = cline.split("\t")
                        if cp.length() >= 2 && cp.get(0) == "build.entryFile" { relEntry = cp.get(1) }
                        ci = ci + 1
                    }
                }
            }
            String entryPath = a.dir + "/" + m.rel + "/" + relEntry
            m.entry = entryPath
            if !pathExists(m.entry) {
                print("reactor: 模块缺少入口 " + m.entry)
                return 1
            }
            String cfPath = a.outdir + "/" + id + ".c"
            m.cf = cfPath
            st = procStatus("\"" + a.xnast + "\" --ast \"" + m.entry + "\" > \"" + a.outdir + "/" + id + ".ast\"")
            if st != 0 { print("reactor: AST 失败：" + m.rel); return 1 }
            st = procStatus("\"" + a.xnullc + "\" \"" + m.entry + "\" --ast-file \"" + a.outdir + "/" + id + ".ast\" --project \"\" > \"" + m.cf + "\"")
            if st != 0 { print("reactor: 生成 C 失败：" + m.rel); return 1 }
            if m.packaging == "app" {
                print("module\t" + m.rel + "\t" + m.packaging + "\t" + m.coord + "\t" + m.cf)
            } else {
                String objPath = a.outdir + "/" + id + ".o"
                m.obj = objPath
                st = procStatus("cc -std=c11 -O2 -pthread -I \"" + a.runtime + "\" -c -Dmain=xn_unused_" + id + " \"" + m.cf + "\" -o \"" + m.obj + "\"")
                if st != 0 { print("reactor: 编译库对象失败：" + m.rel); return 1 }
                print("module\t" + m.rel + "\t" + m.packaging + "\t" + m.coord + "\t" + m.obj)
            }
            i = i + 1
        }
        // 链接：全部 library 对象 + app C + runtime + 空资源表
        String link = ""
        String appCf = ""
        i = 0
        while i < seq.length() {
            Int k = 0
            while k < mods.length() {
                if mods.get(k).rel == seq.get(i) {
                    if mods.get(k).packaging == "app" {
                        appCf = mods.get(k).cf
                    } else if mods.get(k).obj != "" {
                        link = link + " \"" + mods.get(k).obj + "\""
                    }
                }
                k = k + 1
            }
            i = i + 1
        }
        if appCf == "" {
            print("reactor: 没有 app 模块，跳过链接")
            return 0
        }
        String bin = a.outdir + "/app"
        String cmd2 = "cc -std=c11 -O2 -pthread -I \"" + a.runtime + "\" -o \"" + bin + "\" \"" + appCf + "\"" + link + runtimeSrcs(a.runtime) + " \"" + a.outdir + "/res.c\""
        print("link\t" + cmd2)
        st = procStatus(cmd2)
        if st != 0 { print("reactor: 链接失败"); return 1 }
        print("bin\t" + bin)
        if a.artifact != "" {
            Int k = 0
            String aname = ""
            while k < mods.length() {
                if mods.get(k).packaging == "app" {
                    aname = mods.get(k).coord
                    Int c = 0
                    String base = aname
                    while c < aname.length() {
                        if aname.substring(c, 1) == ":" { base = aname.substring(c + 1, aname.length() - c - 1) }
                        c = c + 1
                    }
                    aname = base + "-" + mods.get(k).ver
                }
                k = k + 1
            }
            if aname != "" {
                procStatus("\"" + a.artifact + "\" \"" + bin + "\" \"" + a.dir + "/target\" \"" + aname + "\"")
            }
        }
        return 0
    }
}

static Int main(String[] args) {
    if args.length() < 2 || args[0] != "build-project" {
        print("reactor: 用法 build-project <dir> --runtime <rt> --out <dir> [--xpd P --xmanifest P --xnullc P --xnast P]")
        return 2
    }
    Args a = new Args()
    a.dir = args[1]
    Int i = 2
    while i < args.length() {
        String k = args[i]
        String v = ""
        if i + 1 < args.length() { v = args[i + 1] }
        if k == "--xpd" { a.xpd = v }
        else if k == "--xmanifest" { a.xmanifest = v }
        else if k == "--xnullc" { a.xnullc = v }
        else if k == "--xnast" { a.xnast = v }
        else if k == "--runtime" { a.runtime = v }
        else if k == "--out" { a.outdir = v }
        else if k == "--resman" { a.resman = v }
        else if k == "--artifact" { a.artifact = v }
        else if k == "--config" { a.config = v }
        i = i + 2
    }
    Reactor r = new Reactor()
    return r.run(a)
}
