// Tier: T0；依赖：xdk.sys、xdk.errors；稳定性：preview。
// xdk.fs —— 最小文件系统面，先覆盖文本存在性/读写。
package xdk.fs
import xdk.sys

Bool exists(String path) {
    return fileExists(path)
}

String readText(String path) {
    return readFileText(path)
}

Int writeText(String path, String text) {
    return writeFileText(path, text)
}
