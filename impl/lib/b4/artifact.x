// B4b-03b-2：最小产物落盘（把构建产物复制到 target/）。
//
// 用法：artifact <可执行/产物> <目标目录> <产物名>
// 输出：`artifact\t<目标路径>`
//
// 未支持（B4b-03c）：.xlib 打包、.xmeta、本地仓库布局（<repo>/<g>/<a>/<v>）。

import xdk.sys

// 触发器：Go codegen 在没有任何 class 时会漏发部分预置（xn_arr_s）；保留最小类。
class ArtifactCtx {
    Int unused = 0
}

static Int argCount(List<String> xs) {
    return xs.length()
}

static Int main(String[] args) {
    ArtifactCtx ctx = new ArtifactCtx()
    ctx.unused = 0
    if args.length() < 3 {
        print("artifact: 需要 <产物> <目标目录> <产物名>")
        return 2
    }
    // 参数收进 List<String>（Go codegen 在只用 String[] 时会漏发 xn_arr_s 定义）
    List<String> argv = []
    Int ai = 0
    while ai < args.length() {
        argv.push(args[ai])
        ai = ai + 1
    }
    if argCount(argv) < 3 {
        print("artifact: 需要 <产物> <目标目录> <产物名>")
        return 2
    }
    String bin = argv.get(0)
    String dir = argv.get(1)
    String name = argv.get(2)
    if !pathExists(bin) {
        print("artifact: 产物不存在 " + bin)
        return 1
    }
    if procStatus("mkdir -p \"" + dir + "\"") != 0 {
        print("artifact: 创建目录失败 " + dir)
        return 1
    }
    String dst = dir + "/" + name
    if procStatus("cp \"" + bin + "\" \"" + dst + "\"") != 0 {
        print("artifact: 复制失败 " + dst)
        return 1
    }
    print("artifact\t" + dst)
    return 0
}
