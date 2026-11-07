// t04 Bytes 面：fromString / push / get / length（无 FFI，先隔离类型与成员调用）。
// 合同（S1 §9.7）：fromString 复制字节；push 追加一个字节；get 按索引；length 返回字节数。
import xdk.text

static Int main() {
    Bytes b = Bytes.fromString("abc")
    if (b.length() != 3) {
        return 41
    }
    b.push(0)
    b.push(255)
    if (b.length() != 5) {
        return 42
    }
    if (b.get(0) != 97) {
        return 43
    }
    if (b.get(3) != 0) {
        return 44
    }
    if (b.get(4) != 255) {
        return 45
    }
    return 0
}
