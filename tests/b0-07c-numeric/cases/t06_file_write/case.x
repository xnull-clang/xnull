// t06 写路径：File? + Bytes 实参 + Int32 返回 + @errorCode。
// 合同：fileWrite(f, buf) 返回 0 成功；输出必须逐字节等于 A\0B（NUL 是有效数据，
//       长度权威，见 S7 §3.4）——执行器用 expect-files/out.bin 逐字节比较。
import xdk.sys
import xdk.text

static Int main() {
    String p = "out.bin"
    File? f = fileOpenWrite(p)
    if (f == null) {
        return 61
    }

    Bytes b = Bytes.fromString("A")
    b.push(0)
    b.push(66)

    Int32 wc = fileWrite(f, b)
    Bool ok = fileClose(f)
    if (!ok) {
        return 62
    }
    if (wc != 0) {
        return 63
    }
    return 0
}
