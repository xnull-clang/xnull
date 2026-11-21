// Tier: T0；依赖：xdk.errors；稳定性：preview。
// xdk.bytes —— 字节缓冲区基础面。
//
// 本版按 S1 §2.2 固定数值宽度：Int 32 位、Long 64 位。
// unchecked 读取越界是合同错误（throw）；checked 版本返回 Result。
package xdk.bytes
import xdk.errors

static Error bytesError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

Bytes fromUtf8(String text) {
    Bytes result = Bytes.fromString(text)
    return result
}

String toUtf8(Bytes source) {
    return source.toString()
}

Bytes fromHex(String hexadecimal) {
    if hexadecimal.length() % 2 != 0 {
        throw "fromHex: odd length"
    }
    Bytes result = Bytes.fromString("")
    Int index = 0
    while index + 1 < hexadecimal.length() {
        Int high = hexValue(hexadecimal.substring(index, 1))
        Int low = hexValue(hexadecimal.substring(index + 1, 1))
        result.push(high * 16 + low)
        index = index + 2
    }
    return result
}

Result<Bytes, Error> tryFromHex(String hexadecimal) {
    if hexadecimal.length() % 2 != 0 {
        return Err(bytesError(ErrorKind.InvalidArgument, "fromHex: odd length"))
    }
    Int index = 0
    while index < hexadecimal.length() {
        Int code = hexValueOrNegative(hexadecimal.substring(index, 1))
        if code < 0 {
            return Err(bytesError(ErrorKind.InvalidArgument, "fromHex: invalid character"))
        }
        index = index + 1
    }
    return Ok(fromHex(hexadecimal))
}

String toHex(Bytes source) {
    String digits = "0123456789abcdef"
    String result = ""
    Int index = 0
    while index < source.length() {
        Int value = source.get(index)
        result = result + digits.substring(value / 16, 1) + digits.substring(value % 16, 1)
        index = index + 1
    }
    return result
}

Int byteLength(Bytes source) {
    return source.length()
}

Bool isEmptyBytes(Bytes source) {
    return source.length() == 0
}

// ---------- NUL 边界工具（T0-X） ----------
// 只处理字节 0，不做 C 字符串转换；返回的 Bytes 一律是新副本。

Int nulIndex(Bytes source) {
    Int index = 0
    while index < source.length() {
        if source.get(index) == 0 {
            return index
        }
        index = index + 1
    }
    return -1
}

Bool hasNul(Bytes source) {
    return nulIndex(source) >= 0
}

// 首个 NUL 之前的前缀；无 NUL 时返回全量副本。
Bytes nulPrefix(Bytes source) {
    Int end = nulIndex(source)
    if end < 0 {
        end = source.length()
    }
    return slice(source, 0, end)
}

// 返回带单个尾随 NUL 的副本；已有尾随 NUL 时不重复追加。
Bytes withNulTerminator(Bytes source) {
    Bytes result = copy(source)
    if result.length() == 0 || result.get(result.length() - 1) != 0 {
        result.push(0)
    }
    return result
}

// 去掉一个尾随 NUL；没有尾随 NUL 时返回全量副本。
Bytes withoutTrailingNul(Bytes source) {
    if source.length() > 0 && source.get(source.length() - 1) == 0 {
        return slice(source, 0, source.length() - 1)
    }
    return copy(source)
}

Bytes concatBytes(Bytes first, Bytes second) {
    Bytes result = Bytes.fromString("")
    Int index = 0
    while index < first.length() {
        result.push(first.get(index))
        index = index + 1
    }
    index = 0
    while index < second.length() {
        result.push(second.get(index))
        index = index + 1
    }
    return result
}

Bytes copy(Bytes source) {
    Bytes result = Bytes.fromString("")
    Int index = 0
    while index < source.length() {
        result.push(source.get(index))
        index = index + 1
    }
    return result
}

Bytes slice(Bytes source, Int startIndex, Int endIndex) {
    if startIndex < 0 {
        startIndex = 0
    }
    if endIndex > source.length() {
        endIndex = source.length()
    }
    Bytes result = Bytes.fromString("")
    Int index = startIndex
    while index < endIndex {
        result.push(source.get(index))
        index = index + 1
    }
    return result
}

Result<Bytes, Error> sliceChecked(Bytes source, Int startIndex, Int endIndex) {
    if startIndex < 0 || endIndex < 0 || startIndex > endIndex || endIndex > source.length() {
        return Err(bytesError(ErrorKind.InvalidArgument, "sliceChecked: invalid range"))
    }
    return Ok(slice(source, startIndex, endIndex))
}

Result<Int, Error> tryGetByte(Bytes source, Int index) {
    if index < 0 || index >= source.length() {
        return Err(bytesError(ErrorKind.InvalidArgument, "tryGetByte: index out of range"))
    }
    return Ok(source.get(index))
}

Result<Unit, Error> trySetByte(Bytes target, Int index, Int value) {
    if index < 0 || index >= target.length() {
        return Err(bytesError(ErrorKind.InvalidArgument, "trySetByte: index out of range"))
    }
    target.set(index, value)
    return Ok()
}

Bool equals(Bytes left, Bytes right) {
    if left.length() != right.length() {
        return false
    }
    Int index = 0
    while index < left.length() {
        if left.get(index) != right.get(index) {
            return false
        }
        index = index + 1
    }
    return true
}

Int compare(Bytes left, Bytes right) {
    Int length = left.length()
    if right.length() < length {
        length = right.length()
    }
    Int index = 0
    while index < length {
        Int leftByte = left.get(index)
        Int rightByte = right.get(index)
        if leftByte < rightByte {
            return -1
        }
        if leftByte > rightByte {
            return 1
        }
        index = index + 1
    }
    if left.length() < right.length() {
        return -1
    }
    if left.length() > right.length() {
        return 1
    }
    return 0
}

Bytes u16BE(Int value) {
    if value < 0 || value > 65535 {
        throw "u16BE: value out of range"
    }
    Bytes result = Bytes.fromString("")
    result.push((value / 256) % 256)
    result.push(value % 256)
    return result
}

Bytes u16LE(Int value) {
    if value < 0 || value > 65535 {
        throw "u16LE: value out of range"
    }
    Bytes result = Bytes.fromString("")
    result.push(value % 256)
    result.push((value / 256) % 256)
    return result
}

Bytes u32BE(Long value) {
    if value < 0 || value > 4294967295 {
        throw "u32BE: value out of range"
    }
    Bytes lowFirst = u32LE(value)
    Bytes result = Bytes.fromString("")
    Int index = lowFirst.length() - 1
    while index >= 0 {
        result.push(lowFirst.get(index))
        index = index - 1
    }
    return result
}

Bytes u32LE(Long value) {
    if value < 0 || value > 4294967295 {
        throw "u32LE: value out of range"
    }
    Bytes result = Bytes.fromString("")
    Long current = value
    Int index = 0
    while index < 4 {
        Long next = current / 256
        Int byteValue = current - next * 256
        result.push(byteValue)
        current = next
        index = index + 1
    }
    return result
}

Bytes u64BE(Long value) {
    Bytes lowFirst = u64LE(value)
    Bytes result = Bytes.fromString("")
    Int index = lowFirst.length() - 1
    while index >= 0 {
        result.push(lowFirst.get(index))
        index = index - 1
    }
    return result
}

Bytes u64LE(Long value) {
    Bytes result = Bytes.fromString("")
    Long current = value
    Int index = 0
    while index < 8 {
        Long next = current / 256
        if current < 0 && current % 256 != 0 {
            next = next - 1
        }
        Int byteValue = current - next * 256
        result.push(byteValue)
        current = next
        index = index + 1
    }
    return result
}

Int readShortBE(Bytes source, Int offset) {
    if offset < 0 || offset + 2 > source.length() {
        throw "readShortBE: out of range"
    }
    return source.get(offset) * 256 + source.get(offset + 1)
}

Int readShortLE(Bytes source, Int offset) {
    if offset < 0 || offset + 2 > source.length() {
        throw "readShortLE: out of range"
    }
    return source.get(offset + 1) * 256 + source.get(offset)
}

Long readIntBE(Bytes source, Int offset) {
    if offset < 0 || offset + 4 > source.length() {
        throw "readIntBE: out of range"
    }
    Long value = 0
    Int index = 0
    while index < 4 {
        value = value * 256 + source.get(offset + index)
        index = index + 1
    }
    return value
}

Long readIntLE(Bytes source, Int offset) {
    if offset < 0 || offset + 4 > source.length() {
        throw "readIntLE: out of range"
    }
    Long value = 0
    Int index = 3
    while index >= 0 {
        value = value * 256 + source.get(offset + index)
        index = index - 1
    }
    return value
}

Long readLongBE(Bytes source, Int offset) {
    if offset < 0 || offset + 8 > source.length() {
        throw "readLongBE: out of range"
    }
    Long value = 0
    Int index = 0
    while index < 8 {
        value = value * 256 + source.get(offset + index)
        index = index + 1
    }
    return value
}

Long readLongLE(Bytes source, Int offset) {
    if offset < 0 || offset + 8 > source.length() {
        throw "readLongLE: out of range"
    }
    Long value = 0
    Int index = 7
    while index >= 0 {
        value = value * 256 + source.get(offset + index)
        index = index - 1
    }
    return value
}

Result<Int, Error> tryReadShortBE(Bytes source, Int offset) {
    if offset < 0 || offset + 2 > source.length() {
        return Err(bytesError(ErrorKind.InvalidArgument, "tryReadShortBE: out of range"))
    }
    return Ok(readShortBE(source, offset))
}

Result<Int, Error> tryReadShortLE(Bytes source, Int offset) {
    if offset < 0 || offset + 2 > source.length() {
        return Err(bytesError(ErrorKind.InvalidArgument, "tryReadShortLE: out of range"))
    }
    return Ok(readShortLE(source, offset))
}

Result<Long, Error> tryReadIntBE(Bytes source, Int offset) {
    if offset < 0 || offset + 4 > source.length() {
        return Err(bytesError(ErrorKind.InvalidArgument, "tryReadIntBE: out of range"))
    }
    return Ok(readIntBE(source, offset))
}

Result<Long, Error> tryReadIntLE(Bytes source, Int offset) {
    if offset < 0 || offset + 4 > source.length() {
        return Err(bytesError(ErrorKind.InvalidArgument, "tryReadIntLE: out of range"))
    }
    return Ok(readIntLE(source, offset))
}

Result<Long, Error> tryReadLongBE(Bytes source, Int offset) {
    if offset < 0 || offset + 8 > source.length() {
        return Err(bytesError(ErrorKind.InvalidArgument, "tryReadLongBE: out of range"))
    }
    return Ok(readLongBE(source, offset))
}

Result<Long, Error> tryReadLongLE(Bytes source, Int offset) {
    if offset < 0 || offset + 8 > source.length() {
        return Err(bytesError(ErrorKind.InvalidArgument, "tryReadLongLE: out of range"))
    }
    return Ok(readLongLE(source, offset))
}

Int bitAnd(Int left, Int right) {
    return left & right
}

Int bitOr(Int left, Int right) {
    return left | right
}

Int bitXor(Int left, Int right) {
    return left ^ right
}

Int bitNot(Int value) {
    return -value - 1
}

Int shiftLeft(Int value, Int bitCount) {
    if bitCount < 0 || bitCount >= 32 {
        throw "shiftLeft: bit count out of range"
    }
    return value << bitCount
}

Int shiftRight(Int value, Int bitCount) {
    if bitCount < 0 || bitCount >= 32 {
        throw "shiftRight: bit count out of range"
    }
    return value >> bitCount
}

Int popCount(Int value) {
    Int count = 0
    Int index = 0
    while index < 32 {
        count = count + (value & 1)
        value = value >> 1
        index = index + 1
    }
    return count
}

Int leadingZeros(Int value) {
    Int index = 31
    while index >= 0 {
        if bitAnd(shiftRight(value, index), 1) == 1 {
            return 31 - index
        }
        index = index - 1
    }
    return 32
}

Int trailingZeros(Int value) {
    Int index = 0
    while index < 32 {
        if bitAnd(shiftRight(value, index), 1) == 1 {
            return index
        }
        index = index + 1
    }
    return 32
}

Long shiftLeftLong(Long value, Int bitCount) {
    if bitCount < 0 || bitCount >= 64 {
        throw "shiftLeftLong: bit count out of range"
    }
    Long current = value
    Int index = 0
    while index < bitCount {
        current = current * 2
        index = index + 1
    }
    return current
}

Long shiftRightLong(Long value, Int bitCount) {
    if bitCount < 0 || bitCount >= 64 {
        throw "shiftRightLong: bit count out of range"
    }
    Long current = value
    Int index = 0
    while index < bitCount {
        current = current / 2
        index = index + 1
    }
    return current
}

Int popCountLong(Long value) {
    Long current = value
    Int count = 0
    Int index = 0
    while index < 64 {
        Long quotient = current / 2
        if current < 0 && current % 2 != 0 {
            quotient = quotient - 1
        }
        Long remainder = current - quotient * 2
        if remainder != 0 {
            count = count + 1
        }
        current = quotient
        index = index + 1
    }
    return count
}

Int leadingZerosLong(Long value) {
    Long current = value
    Int index = 0
    while index < 64 {
        Long quotient = current / 2
        if current < 0 && current % 2 != 0 {
            quotient = quotient - 1
        }
        if quotient == 0 {
            return 64 - index - 1
        }
        current = quotient
        index = index + 1
    }
    return 0
}

Int trailingZerosLong(Long value) {
    Long current = value
    Int index = 0
    while index < 64 {
        Long quotient = current / 2
        if current < 0 && current % 2 != 0 {
            quotient = quotient - 1
        }
        Long remainder = current - quotient * 2
        if remainder != 0 {
            return index
        }
        current = quotient
        index = index + 1
    }
    return 64
}

class ByteReader {
    Bytes _source
    Int _position

    ByteReader(Bytes source) {
        self._source = source
        self._position = 0
    }

    Int position() {
        return self._position
    }

    Int remaining() {
        return self._source.length() - self._position
    }

    Bool hasRemaining() {
        return self._position < self._source.length()
    }

    Result<Unit, Error> seek(Int offset) {
        if offset < 0 || offset > self._source.length() {
            return Err(bytesError(ErrorKind.InvalidArgument, "seek: out of range"))
        }
        self._position = offset
        return Ok()
    }

    Int readU8() {
        if !self.hasRemaining() {
            throw "readU8: end of input"
        }
        Int value = self._source.get(self._position)
        self._position = self._position + 1
        return value
    }

    Result<Int, Error> tryReadU8() {
        if !self.hasRemaining() {
            return Err(bytesError(ErrorKind.DataCorrupted, "tryReadU8: end of input"))
        }
        return Ok(self.readU8())
    }

    Int shortBE() {
        if self.remaining() < 2 {
            throw "shortBE: end of input"
        }
        Int value = readShortBE(self._source, self._position)
        self._position = self._position + 2
        return value
    }

    Int shortLE() {
        if self.remaining() < 2 {
            throw "shortLE: end of input"
        }
        Int value = readShortLE(self._source, self._position)
        self._position = self._position + 2
        return value
    }

    Result<Int, Error> tryShortBE() {
        if self.remaining() < 2 {
            return Err(bytesError(ErrorKind.DataCorrupted, "tryShortBE: end of input"))
        }
        return Ok(self.shortBE())
    }

    Result<Int, Error> tryShortLE() {
        if self.remaining() < 2 {
            return Err(bytesError(ErrorKind.DataCorrupted, "tryShortLE: end of input"))
        }
        return Ok(self.shortLE())
    }

    Long intBE() {
        if self.remaining() < 4 {
            throw "intBE: end of input"
        }
        Long value = readIntBE(self._source, self._position)
        self._position = self._position + 4
        return value
    }

    Long intLE() {
        if self.remaining() < 4 {
            throw "intLE: end of input"
        }
        Long value = readIntLE(self._source, self._position)
        self._position = self._position + 4
        return value
    }

    Result<Long, Error> tryIntBE() {
        if self.remaining() < 4 {
            return Err(bytesError(ErrorKind.DataCorrupted, "tryIntBE: end of input"))
        }
        return Ok(self.intBE())
    }

    Result<Long, Error> tryIntLE() {
        if self.remaining() < 4 {
            return Err(bytesError(ErrorKind.DataCorrupted, "tryIntLE: end of input"))
        }
        return Ok(self.intLE())
    }

    Long longBE() {
        if self.remaining() < 8 {
            throw "longBE: end of input"
        }
        Long value = readLongBE(self._source, self._position)
        self._position = self._position + 8
        return value
    }

    Long longLE() {
        if self.remaining() < 8 {
            throw "longLE: end of input"
        }
        Long value = readLongLE(self._source, self._position)
        self._position = self._position + 8
        return value
    }

    Result<Long, Error> tryLongBE() {
        if self.remaining() < 8 {
            return Err(bytesError(ErrorKind.DataCorrupted, "tryLongBE: end of input"))
        }
        return Ok(self.longBE())
    }

    Result<Long, Error> tryLongLE() {
        if self.remaining() < 8 {
            return Err(bytesError(ErrorKind.DataCorrupted, "tryLongLE: end of input"))
        }
        return Ok(self.longLE())
    }

    Bytes readBytes(Int count) {
        if count < 0 {
            throw "readBytes: negative count"
        }
        Int end = self._position + count
        if end > self._source.length() {
            end = self._source.length()
        }
        Bytes value = slice(self._source, self._position, end)
        self._position = end
        return value
    }

    Result<Bytes, Error> readExact(Int count) {
        if count < 0 {
            throw "readExact: negative count"
        }
        if self.remaining() < count {
            return Err(bytesError(ErrorKind.DataCorrupted, "readExact: end of input"))
        }
        Bytes value = slice(self._source, self._position, self._position + count)
        self._position = self._position + count
        return Ok(value)
    }
}

class ByteWriter {
    Bytes _buffer

    ByteWriter() {
        self._buffer = Bytes.fromString("")
    }

    Int length() {
        return self._buffer.length()
    }

    Bytes toBytes() {
        return copy(self._buffer)
    }

    Bytes takeBytes() {
        Bytes result = self._buffer
        self._buffer = Bytes.fromString("")
        return result
    }

    Void writeU8(Int value) {
        self._buffer.push(value % 256)
    }

    Void writeBytes(Bytes source) {
        Int index = 0
        while index < source.length() {
            self._buffer.push(source.get(index))
            index = index + 1
        }
    }

    Void writeU16BE(Int value) {
        self.writeBytes(u16BE(value))
    }

    Void writeU16LE(Int value) {
        self.writeBytes(u16LE(value))
    }

    Void writeU32BE(Long value) {
        self.writeBytes(u32BE(value))
    }

    Void writeU32LE(Long value) {
        self.writeBytes(u32LE(value))
    }

    Void writeU64BE(Long value) {
        self.writeBytes(u64BE(value))
    }

    Void writeU64LE(Long value) {
        self.writeBytes(u64LE(value))
    }

    Void clear() {
        self._buffer = Bytes.fromString("")
    }
}

ByteBuffer byteBufferFrom(Bytes initialContent) {
    ByteBuffer buffer = new ByteBuffer()
    buffer.append(initialContent)
    return buffer
}

class ByteBuffer {
    Bytes _data
    Int _capacity

    ByteBuffer() {
        self._data = Bytes.fromString("")
        self._capacity = 0
    }

    Int length() {
        return self._data.length()
    }

    Int capacity() {
        return self._capacity
    }

    Bytes toBytes() {
        return copy(self._data)
    }

    Void push(Int value) {
        self._data.push(value % 256)
        if self._data.length() > self._capacity {
            self._capacity = self._data.length()
        }
    }

    Void append(Bytes source) {
        Int index = 0
        while index < source.length() {
            self.push(source.get(index))
            index = index + 1
        }
    }

    Result<Unit, Error> put(Int index, Int value) {
        if index < 0 || index >= self._data.length() {
            return Err(bytesError(ErrorKind.InvalidArgument, "ByteBuffer.put: out of range"))
        }
        self._data.set(index, value)
        return Ok()
    }

    Result<Int, Error> get(Int index) {
        if index < 0 || index >= self._data.length() {
            return Err(bytesError(ErrorKind.InvalidArgument, "ByteBuffer.get: out of range"))
        }
        return Ok(self._data.get(index))
    }

    Void clear() {
        self._data = Bytes.fromString("")
    }

    Void reserve(Int minimumCapacity) {
        if minimumCapacity < 0 {
            throw "ByteBuffer.reserve: negative capacity"
        }
        if minimumCapacity > self._capacity {
            self._capacity = minimumCapacity
        }
    }
}

static Int hexValue(String character) {
    Int value = hexValueOrNegative(character)
    if value < 0 {
        throw "fromHex: invalid character"
    }
    return value
}

static Int hexValueOrNegative(String character) {
    if character == "0" { return 0 }
    if character == "1" { return 1 }
    if character == "2" { return 2 }
    if character == "3" { return 3 }
    if character == "4" { return 4 }
    if character == "5" { return 5 }
    if character == "6" { return 6 }
    if character == "7" { return 7 }
    if character == "8" { return 8 }
    if character == "9" { return 9 }
    if character == "a" { return 10 }
    if character == "b" { return 11 }
    if character == "c" { return 12 }
    if character == "d" { return 13 }
    if character == "e" { return 14 }
    if character == "f" { return 15 }
    if character == "A" { return 10 }
    if character == "B" { return 11 }
    if character == "C" { return 12 }
    if character == "D" { return 13 }
    if character == "E" { return 14 }
    if character == "F" { return 15 }
    return -1
}
