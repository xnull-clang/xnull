// 最小配置读取（只取 build 需要的键）。
//
// 用法：config <xnull.project>
// 输出：`build.<key>\t<value>`（仅 `build { … }` 顶层标量字段，按出现顺序）。
//
// 未支持（后续）：properties 变量替换、profile 合并、五/六层覆盖、类型校验。
package xdk.build.config
import xdk.sys

// 触发器：Go codegen 在没有任何 class 时会漏发部分预置（xn_arr_s）；保留最小类。
class ConfigCtx {
    Int unused = 0
}
