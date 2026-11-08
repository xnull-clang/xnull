// K-07：xdk.sys.readFileText 双路径回归入口。
// 用法：k07_readfile.x <path>
// 输出：len=<字节数> head=<前 64 字节的十六进制>（文件不足 64 字节时取全部）。
import xdk.sys
import xdk.runtime

static String hex2(Int v) {
    String digits = "0123456789abcdef"
    Int hi = (v >> 4) & 15
    Int lo = v & 15
    return digits.substring(hi, 1) + digits.substring(lo, 1)
}

static Int main(String[] args) {
    if (args.length() != 1) {
        diagnose("k07_readfile: 需要 1 个文件路径参数")
        return 2
    }
    String path = args[0]
    String text = readFileText(path)
    Bytes b = Bytes.fromString(text)
    Int n = b.length()
    Int take = 64
    if (n < take) {
        take = n
    }
    String head = ""
    Int i = 0
    while (i < take) {
        head = head + hex2(b.get(i))
        i = i + 1
    }
    print("len=" + str(n) + " head=" + head)
    return 0
}
