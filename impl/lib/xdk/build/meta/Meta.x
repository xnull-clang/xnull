// 生成模块元数据 `.xmeta`（字段对齐 Go `projectManifest.xmeta`）。
//
// 用法：
//   xmeta <输出目录> <meta.tsv> <root.tsv> [<module.tsv> …]
//
// meta.tsv（由 xnull-build.sh 计算后传入）：
//   platform / toolchainVersion / resourcesSha256 / lockSha256 / configSha256 / pluginsSha256 / inputs
//
// 每个清单 TSV 生成 `<artifactId>-<version>.xmeta`；字段顺序与 Go 一致，
// 末尾追加两个扩展字段：`entryFile`（固定 src/main/x/main.x）与 `dependencies`（逗号分隔）。
package xdk.build.meta
import xdk.sys

         
                     
                   
                   
                    
                          
                          
 

            
                               
                                
                      
                       
                      
                       
                      
 

static String getMeta(List<String> keys, List<String> vals, String k, String dflt) {
    Int i = 0
    while i < keys.length() {
        if keys.get(i) == k { return vals.get(i) }
        i = i + 1
    }
    return dflt
}

static M loadTsv(String path) {
    M m = new M()
    String src = readFileText(path)
    String[] ls = src.split("\n")
    Int i = 0
    while i < ls.length() {
        String line = ls[i]
        if line != "" {
            String[] ps = line.split("\t")
            if ps.length() >= 3 && ps.get(0) == "field" {
                String k = ps.get(1)
                String v = ps.get(2)
                if k == "groupId" { m.group = v }
                else if k == "artifactId" { m.art = v }
                else if k == "version" { m.ver = v }
                else if k == "packaging" { m.pack = v }
            } else if ps.length() >= 2 && ps.get(0) == "dep" {
                m.depC.push(ps.get(1))
                String v = ""
                if ps.length() >= 3 { v = ps.get(2) }
                m.depV.push(v)
            }
        }
        i = i + 1
    }
    return m
}

static String depList(M m) {
    String s = "["
    Int i = 0
    while i < m.depC.length() {
        if i > 0 { s = s + ", " }
        s = s + m.depC.get(i)
        i = i + 1
    }
    return s + "]"
}

static void writeOne(String outDir, M m, Meta mt) {
    String body = "xmeta {\n"
    body = body + "  groupId          = " + m.group + "\n"
    body = body + "  artifactId       = " + m.art + "\n"
    body = body + "  version          = " + m.ver + "\n"
    body = body + "  packaging        = " + m.pack + "\n"
    body = body + "  platform         = " + mt.platform + "\n"
    body = body + "  xdkVersion       = unknown\n"
    body = body + "  languageVersion  = unknown\n"
    body = body + "  toolchainVersion = " + mt.toolchain + "\n"
    body = body + "  profiles         = []\n"
    body = body + "  plugins          = []\n"
    body = body + "  configSha256     = " + mt.cfgSha + "\n"
    body = body + "  resourcesSha256  = " + mt.resSha + "\n"
    body = body + "  pluginsSha256    = " + mt.plugSha + "\n"
    body = body + "  lockSha256       = " + mt.lockSha + "\n"
    body = body + "  inputs           = " + mt.inputs + "\n"
    // 扩展字段（Go 无）：入口与依赖
    body = body + "  entryFile        = src/main/x/main.x\n"
    body = body + "  dependencies     = " + depList(m) + "\n"
    body = body + "}\n"
    String path = outDir + "/" + m.art + "-" + m.ver + ".xmeta"
    writeFileText(path, body)
    print("xmeta\t" + path)
}

static Int main(String[] args) {
    if args.length() < 3 {
        print("xmeta: 需要 <输出目录> <meta.tsv> <root.tsv> [<module.tsv> …]")
        return 2
    }
    String outDir = args[0]
    procStatus("mkdir -p \"" + outDir + "\"")
    // meta.tsv
    List<String> keys = []
    List<String> vals = []
    String mtext = readFileText(args[1])
    String[] ml = mtext.split("\n")
    Int i = 0
    while i < ml.length() {
        if ml[i] != "" {
            String mline = ml[i]
            String[] ps = mline.split("\t")
            if ps.length() >= 2 {
                keys.push(ps.get(0))
                vals.push(ps.get(1))
            }
        }
        i = i + 1
    }
    Meta mt = new Meta()
    mt.platform = getMeta(keys, vals, "platform", "unknown")
    mt.toolchain = getMeta(keys, vals, "toolchainVersion", "unknown")
    mt.resSha = getMeta(keys, vals, "resourcesSha256", "")
    mt.lockSha = getMeta(keys, vals, "lockSha256", "")
    mt.cfgSha = getMeta(keys, vals, "configSha256", "")
    mt.plugSha = getMeta(keys, vals, "pluginsSha256", "")
    mt.inputs = getMeta(keys, vals, "inputs", "")
    // 清单 TSV：第 2 个是根，其余是模块
    i = 2
    while i < args.length() {
        M m = loadTsv(args[i])
        if m.art != "" { writeOne(outDir, m, mt) }
        i = i + 1
    }
    return 0
}
