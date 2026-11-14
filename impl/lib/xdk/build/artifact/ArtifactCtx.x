// 最小产物落盘（把构建产物复制到 target/）。
//
// 用法：artifact <可执行/产物> <目标目录> <产物名>
// 输出：`artifact\t<目标路径>`
//
// 未支持（后续）：.xlib 打包、.xmeta、本地仓库布局（<repo>/<g>/<a>/<v>）。
package xdk.build.artifact
import xdk.sys

// 触发器：Go codegen 在没有任何 class 时会漏发部分预置（xn_arr_s）；保留最小类。
class ArtifactCtx {
    Int unused = 0
}
