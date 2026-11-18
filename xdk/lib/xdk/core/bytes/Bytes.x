// Tier: T0；依赖：xdk.errors；稳定性：preview。
// xdk.bytes —— 字节缓冲区基础面。
//
// 当前切片先公开运行时可验证的最小接口：UTF-8 构造/还原和 hex 编解码。
// 后续 ByteBuffer、端序和位操作继续按 XDK 场景推进。
package xdk.bytes

Bytes fromUtf8(String text) {
    Bytes result = Bytes.fromString(text)
    return result
}

String toUtf8(Bytes data) {
    return data.toString()
}

Bytes fromHex(String hex) {
    Bytes result = Bytes.fromString("")
    Int i = 0
    while i + 1 < hex.length() {
        result.push(hexValue(hex.substring(i, 1)) * 16 + hexValue(hex.substring(i + 1, 1)))
        i = i + 2
    }
    return result
}

String toHex(Bytes data) {
    String digits = "0123456789abcdef"
    String result = ""
    Int i = 0
    while i < data.length() {
        Int value = data.get(i)
        result = result + digits.substring(value / 16, 1) + digits.substring(value % 16, 1)
        i = i + 1
    }
    return result
}

Int byteLength(Bytes data) {
    return data.length()
}

Bool isEmpty(Bytes data) {
    return data.length() == 0
}

static Int hexValue(String ch) {
    if ch == "0" { return 0 }
    if ch == "1" { return 1 }
    if ch == "2" { return 2 }
    if ch == "3" { return 3 }
    if ch == "4" { return 4 }
    if ch == "5" { return 5 }
    if ch == "6" { return 6 }
    if ch == "7" { return 7 }
    if ch == "8" { return 8 }
    if ch == "9" { return 9 }
    if ch == "a" { return 10 }
    if ch == "b" { return 11 }
    if ch == "c" { return 12 }
    if ch == "d" { return 13 }
    if ch == "e" { return 14 }
    if ch == "f" { return 15 }
    return 0
}
