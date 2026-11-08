// t02 Option<handle>：File? 的 null 判定 + 守卫内收窄为 File。
// 合同（S6 §3 第 1 条）：打开失败返回 null，不 panic；成功返回可用句柄。
// 依赖 E5 包装层修复：原生返回 NULL 必须回 NULL（而不是包一个 native==NULL 的句柄）。
import xdk.sys

static Int main() {
    String p = "in.txt"
    File? f = fileOpenRead(p)
    if (f == null) {
        return 12
    }
    Bool ok = fileClose(f)
    if (!ok) {
        return 13
    }

    String missing = "no-such-file.txt"
    File? g = fileOpenRead(missing)
    if (g != null) {
        return 14
    }
    return 0
}
