// xdk.sys —— S6-08 包骨架
//
// 说明：文件、目录、进程与内嵌资源（原语由运行时提供，句柄 close 必达）。
// 依赖矩阵：本骨架不导入其他 xdk 单元（依赖方向由 S6 §2 冻结后再追加）。
// 稳定性：@preview（API 冻结前不承诺）。

// K-07：文件输入通道（xnullc --ast-file/--bundle-file 使用）。
// 读取失败（缺失/IO/超过 64 MiB）→ throw 明确诊断，不返回空串。
String readFileText(String path) {
    String raw = readFileTextRaw(path)
    if (readFileTextError() != 0) {
        throw $"readFileText: 无法读取文件 {path}"
    }
    return raw
}
