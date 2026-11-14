// 资源表生成（最小 resman）。
//
// 用法：
//   resman <资源目录> <输出.c> [<文件> …]
//
// 约定：只处理**单层目录**下的常规文件；文件名（相对资源目录）即资源名，
// 由调用方（xnull-build.sh）用 shell glob 展开并传入，按名字节序排序。
// 输出与 Go `impl/internal/devtool` 的 renderResources 逐字节一致（空表/单文件/多文件）。
//
// 未支持（后续）：子目录递归、符号链接校验、glob includes/excludes、二进制资源。
package xdk.build.resource
import xdk.sys

class Acc {
    List<String> names = []
    List<String> datas = []
}
