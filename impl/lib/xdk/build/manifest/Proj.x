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

class Proj {
    String groupId = ""
    String artifactId = ""
    String version = ""
    String packaging = ""
    List<String> modules = []
    List<String> managed = []
    List<String> deps = []
}
