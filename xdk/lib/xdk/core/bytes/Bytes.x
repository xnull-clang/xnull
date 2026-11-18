// Tier: T0；依赖：xdk.errors；稳定性：preview。
// xdk.bytes —— 字节缓冲区基础面。
//
// 已落地的逆向切片：UTF-8 构造/还原、hex、拼接、比较、端序读写和最小
// ByteBuffer。ByteBuffer 仍是最小实现，后续按 XDK 场景继续扩展。
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

Bytes concatBytes(Bytes first, Bytes second) {
    Bytes result = Bytes.fromString("")
    Int i = 0
    while i < first.length() {
        result.push(first.get(i))
        i = i + 1
    }
    i = 0
    while i < second.length() {
        result.push(second.get(i))
        i = i + 1
    }
    return result
}

Bytes slice(Bytes data, Int start, Int end) {
    if start < 0 { start = 0 }
    if end > data.length() { end = data.length() }
    Bytes result = Bytes.fromString("")
    Int i = start
    while i < end {
        result.push(data.get(i))
        i = i + 1
    }
    return result
}

Int compare(Bytes first, Bytes second) {
    Int n = first.length()
    if second.length() < n { n = second.length() }
    Int i = 0
    while i < n {
        Int a = first.get(i)
        Int b = second.get(i)
        if a < b { return -1 }
        if a > b { return 1 }
        i = i + 1
    }
    if first.length() < second.length() { return -1 }
    if first.length() > second.length() { return 1 }
    return 0
}

Bytes u16BE(Int value) {
    Bytes result = Bytes.fromString("")
    result.push((value / 256) % 256)
    result.push(value % 256)
    return result
}

Bytes u16LE(Int value) {
    Bytes result = Bytes.fromString("")
    result.push(value % 256)
    result.push((value / 256) % 256)
    return result
}

Bytes u32BE(Int value) {
    Bytes result = Bytes.fromString("")
    result.push((value / 16777216) % 256)
    result.push((value / 65536) % 256)
    result.push((value / 256) % 256)
    result.push(value % 256)
    return result
}

Bytes u32LE(Int value) {
    Bytes result = Bytes.fromString("")
    result.push(value % 256)
    result.push((value / 256) % 256)
    result.push((value / 65536) % 256)
    result.push((value / 16777216) % 256)
    return result
}

Int readShortBE(Bytes data, Int offset) {
    return data.get(offset) * 256 + data.get(offset + 1)
}

Int readShortLE(Bytes data, Int offset) {
    return data.get(offset + 1) * 256 + data.get(offset)
}

Int readIntBE(Bytes data, Int offset) {
    return data.get(offset) * 16777216 + data.get(offset + 1) * 65536 + data.get(offset + 2) * 256 + data.get(offset + 3)
}

Int readIntLE(Bytes data, Int offset) {
    return data.get(offset + 3) * 16777216 + data.get(offset + 2) * 65536 + data.get(offset + 1) * 256 + data.get(offset)
}

Int bitAnd(Int a, Int b) {
    return a & b
}

Int bitOr(Int a, Int b) {
    return a | b
}

Int bitXor(Int a, Int b) {
    return a ^ b
}

Int shiftLeft(Int value, Int bits) {
    return value << bits
}

Int shiftRight(Int value, Int bits) {
    return value >> bits
}

class ByteReader {
    Bytes data
    Int position

    ByteReader(Bytes source) {
        self.data = source
        self.position = 0
    }

    Int remaining() {
        return self.data.length() - self.position
    }

    Bool hasRemaining() {
        return self.position < self.data.length()
    }

    Int readU8() {
        if self.position >= self.data.length() { return 0 }
        Int value = self.data.get(self.position)
        self.position = self.position + 1
        return value
    }

    Int shortBE() {
        Int value = readShortBE(self.data, self.position)
        self.position = self.position + 2
        return value
    }

    Int shortLE() {
        Int value = readShortLE(self.data, self.position)
        self.position = self.position + 2
        return value
    }

    Int intBE() {
        Int value = readIntBE(self.data, self.position)
        self.position = self.position + 4
        return value
    }

    Int intLE() {
        Int value = readIntLE(self.data, self.position)
        self.position = self.position + 4
        return value
    }

    Bytes readBytes(Int count) {
        Int end = self.position + count
        if end > self.data.length() { end = self.data.length() }
        Bytes value = slice(self.data, self.position, end)
        self.position = end
        return value
    }
}

class ByteWriter {
    Bytes data

    ByteWriter() {
        self.data = Bytes.fromString("")
    }

    Int length() {
        return self.data.length()
    }

    Bytes toBytes() {
        return self.data
    }

    Void writeU8(Int value) {
        self.data.push(value % 256)
    }

    Void writeBytes(Bytes value) {
        Int i = 0
        while i < value.length() {
            self.data.push(value.get(i))
            i = i + 1
        }
    }

    Void writeU16BE(Int value) {
        self.writeBytes(u16BE(value))
    }

    Void writeU16LE(Int value) {
        self.writeBytes(u16LE(value))
    }

    Void writeU32BE(Int value) {
        self.writeBytes(u32BE(value))
    }

    Void writeU32LE(Int value) {
        self.writeBytes(u32LE(value))
    }
}

class ByteBuffer {
    Bytes data

    ByteBuffer() {
        self.data = Bytes.fromString("")
    }

    ByteBuffer(Bytes initial) {
        self.data = initial
    }

    Int length() {
        return self.data.length()
    }

    Bytes toBytes() {
        return self.data
    }

    Void push(Int value) {
        self.data.push(value % 256)
    }

    Void append(Bytes more) {
        Int i = 0
        while i < more.length() {
            self.data.push(more.get(i))
            i = i + 1
        }
    }
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
