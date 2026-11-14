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

class M {
    String group = ""
    String art = ""
    String ver = ""
    String pack = ""
    List<String> depC = []
    List<String> depV = []
}
