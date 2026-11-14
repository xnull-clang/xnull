package xdk.compiler.codegen; import xdk.sys
import xdk.runtime

// xnullc Result/try/defer（XNull 版 AST -> C）。
//
// 输入：<entryPath> <xnast v1 AST dump>
// 输出：与 Go `xnull build --emit-c` 口径一致的 C 文本。
// 覆盖：Result 实例化、Ok/Err、isOk/isErr/value/error/unwrapOr、try、defer/errdefer、throw。






















class N {
    Bool sc = false
    String raw = ""
    String nm = ""
    List<String> fn = []
    List<N> fv = []
    List<N> el = []
}
