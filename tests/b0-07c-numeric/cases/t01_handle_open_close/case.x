// t01 句柄返回 + 显式 close（E4 已实现，作为回归护栏）。
// 合同：fileOpenRead 返回 File；fileClose 幂等、返回 Bool（true=成功）。
import xdk.sys

static Int main() {
    String p = "in.txt"
    File f = fileOpenRead(p)
    Bool ok = fileClose(f)
    if (!ok) {
        return 11
    }
    return 0
}
