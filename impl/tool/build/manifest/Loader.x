// 消费 xpd TSV，输出工程模型（模块列表、依赖边、拓扑序）。
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
package xdk.build.manifest
import xdk.sys




















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
