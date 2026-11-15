// 聚合工程最小构建（reactor）。
//
// 用法：
//   reactor build-project <dir> --xpd <xpd> --xmanifest <xmanifest>
//           --xnullc <xnullc> --xnast <xnast> --runtime <src/runtime> --out <目标目录>
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











class Args {
    String dir = ""
    String xpd = "/tmp/xpd"
    String xmanifest = "/tmp/xmanifest"
    String xnullc = "/tmp/xn-s4"
    String xnast = "/tmp/xnast"
    String runtime = ""
    String outdir = ""
    String repo = ""
    String resman = ""
    String artifact = ""
    String config = ""
}
