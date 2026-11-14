// 聚合工程最小构建（reactor）。
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
// 未支持（后续）：build.entryFile、sourceRoot、跨模块 import、资源表（resman）、配置。
// 模块入口固定为 <dir>/<rel>/src/main/x/main.x。
package xdk.build.reactor
import xdk.sys

















































































































class Reactor {
    // 安装到本地仓库：<repo>/<group 斜杠>/<artifact>/<version>/
    //   library → <a>-<v>.o + xnull.project
    //   app     → <a>-<v>（可执行）+ xnull.project
    //   聚合根  → xnull.project + reactor-summary.txt
    void installAll(Args a, List<Mod> mods, List<String> seq, String bin) {
        if a.repo == "" { return }
        Int i = 0
        String tmpSum = a.outdir + "/.sha";
        String summary = a.outdir + "/reactor-summary.txt"
        String body = "# reactor 聚合摘要（脚本生成，手改即作废）\n"
        while i < seq.length() {
            Mod m = new Mod()
            Int kk = 0
            while kk < mods.length() {
                if mods.get(kk).rel == seq.get(i) { m = mods.get(kk) }
                kk = kk + 1
            }
            String g = groupOf(m.coord)
            String art = artifactOf(m.coord)
            String dir = a.repo + "/" + slashDots(g) + "/" + art + "/" + m.ver
            procStatus("mkdir -p \"" + dir + "\"")
            String srcf = m.obj
            String name = art + "-" + m.ver + ".o"
            if m.packaging == "app" {
                srcf = bin
                name = art + "-" + m.ver
            }
            if srcf != "" {
                procStatus("cp -f \"" + srcf + "\" \"" + dir + "/" + name + "\"")
                print("install\t" + dir + "/" + name)
            }
            procStatus("cp -f \"" + a.dir + "/" + m.rel + "/xnull.project\" \"" + dir + "/xnull.project\"")
            String sh = shaOf(dir + "/" + name, tmpSum)
            body = body + "module " + m.rel + " " + dir + "/" + name + " " + sh + "\n"
            i = i + 1
        }
        // 聚合根：坐标从根 TSV 的 field 行读取
        String rootTsv = a.outdir + "/root.tsv"
        String group = ""
        String art = ""
        String ver = ""
        String rt = readFileText(rootTsv)
        String[] rl = rt.split("\n")
        Int k = 0
        while k < rl.length() {
            if rl[k] != "" {
                String rline = rl[k]
                String[] ps = rline.split("\t")
                if ps.length() >= 3 && ps.get(0) == "field" {
                    if ps.get(1) == "groupId" { group = ps.get(2) }
                    else if ps.get(1) == "artifactId" { art = ps.get(2) }
                    else if ps.get(1) == "version" { ver = ps.get(2) }
                }
            }
            k = k + 1
        }
        if group != "" && art != "" {
            writeFileText(summary, body)
            String dir = a.repo + "/" + slashDots(group) + "/" + art + "/" + ver
            procStatus("mkdir -p \"" + dir + "\"")
            procStatus("cp -f \"" + a.dir + "/xnull.project\" \"" + dir + "/xnull.project\"")
            procStatus("cp -f \"" + summary + "\" \"" + dir + "/reactor-summary.txt\"")
            print("install\t" + dir + "/reactor-summary.txt")
        }
    }

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
            installAll(a, mods, seq, "")
            return 0
        }
        String bin = a.outdir + "/app"
        String cmd2 = "cc -std=c11 -O2 -pthread -I \"" + a.runtime + "\" -o \"" + bin + "\" \"" + appCf + "\"" + link + runtimeSrcs(a.runtime) + " \"" + a.outdir + "/res.c\""
        print("link\t" + cmd2)
        st = procStatus(cmd2)
        if st != 0 { print("reactor: 链接失败"); return 1 }
        print("bin\t" + bin)
        installAll(a, mods, seq, bin)
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
