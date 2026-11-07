// t05 读路径：File? + Bytes 缓冲 + @errorCode 出参 + Int64 返回。
// 合同：fileRead(f, buf, code) 把错误码写入 code（0=成功），返回读入字节数；
//       Bytes 实参按 data/len 借出，canary 校验越界（S7 §9）。
import xdk.sys
import xdk.text

static Int main() {
    String p = "in.txt"
    File? f = fileOpenRead(p)
    if (f == null) {
        return 51
    }

    Bytes buf = Bytes.fromString("")
    Int i = 0
    while (i < 8) {
        buf.push(0)
        i = i + 1
    }

    Int32 code = 7          // 预置非 0：调用必须把它写回 0，证明出参真被接线
    Int64 got = fileRead(f, buf, code)
    Bool ok = fileClose(f)
    if (!ok) {
        return 52
    }
    if (code != 0) {
        return 53
    }
    if (got != 2) {
        return 54
    }
    if (buf.get(0) != 65) {  // 'A'
        return 55
    }
    if (buf.get(1) != 66) {  // 'B'
        return 56
    }
    return 0
}
