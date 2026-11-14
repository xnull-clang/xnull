// xdk.codec —— 编解码包：Base64 / URL / JSON / CSV / 二进制。
// 约定：
//   - Hex 编解码直接复用 xdk.sys 的 hexEncode/hexDecode；
//   - JsonValue 的对象侧用平行 List 实现（Map 对类值在源码层尚未接线，已知缺口）；
//   - \\uXXXX 转义 v1 返回错误（缺 Char←Int 构造原语）；
//   - 浮点位模式经 ext_raw 的 f32/f64 bits 原语。
package xdk.codec
import xdk.errors
import xdk.sys
import xdk.math

// ---------- Base64 ----------





















































































































































































































































































































































































































































































































































































































































































































































































































































































































// ---------- 二进制（对标 struct，LE/BE） ----------
class BinaryReader {
    Bytes data
    Int pos

    BinaryReader(Bytes d) {
        self.data = d
        self.pos = 0
    }

    Int tell() {
        return self.pos
    }

    void seek(Int p) {
        if p < 0 {
            p = 0
        }
        if p > self.data.length() {
            p = self.data.length()
        }
        self.pos = p
    }

    Int remaining() {
        return self.data.length() - self.pos
    }

    Bool eof() {
        return self.pos >= self.data.length()
    }

    Bool has(Int n) {
        return self.remaining() >= n
    }

    Int readU8() {
        Int v = self.data.get(self.pos)
        self.pos = self.pos + 1
        return v
    }

    Int readU16le() {
        Int v = self.data.get(self.pos) + self.data.get(self.pos + 1) * 256
        self.pos = self.pos + 2
        return v
    }

    Int readU16be() {
        Int v = self.data.get(self.pos) * 256 + self.data.get(self.pos + 1)
        self.pos = self.pos + 2
        return v
    }

    Int readU32le() {
        Int v = self.data.get(self.pos) + self.data.get(self.pos + 1) * 256 +
            self.data.get(self.pos + 2) * 65536 + self.data.get(self.pos + 3) * 16777216
        self.pos = self.pos + 4
        return v
    }

    Int readU32be() {
        Int v = self.data.get(self.pos) * 16777216 + self.data.get(self.pos + 1) * 65536 +
            self.data.get(self.pos + 2) * 256 + self.data.get(self.pos + 3)
        self.pos = self.pos + 4
        return v
    }

    Int64 readU64le() {
        Int64 v = 0
        Int shift = 0
        Int i = 0
        while i < 8 {
            v = v + self.data.get(self.pos + i) * (1 * pow2(shift))
            shift = shift + 8
            i = i + 1
        }
        self.pos = self.pos + 8
        return v
    }

    Int64 readU64be() {
        Int64 v = 0
        Int i = 0
        while i < 8 {
            v = v * 256 + self.data.get(self.pos + i)
            i = i + 1
        }
        self.pos = self.pos + 8
        return v
    }

    Int readI32le() {
        Int v = self.readU32le()
        if v >= 2147483648 {
            v = v - 4294967296
        }
        return v
    }

    Double readF32le() {
        Int bits = self.readU32le()
        return f32FromBitsRaw(bits)
    }

    Double readF64le() {
        Int64 bits = self.readU64le()
        return f64FromBitsRaw(bits)
    }

    Bytes readBytes(Int n) {
        Bytes out = Bytes.fromString("")
        Int i = 0
        while i < n && self.pos < self.data.length() {
            out.push(self.data.get(self.pos))
            self.pos = self.pos + 1
            i = i + 1
        }
        return out
    }
}
