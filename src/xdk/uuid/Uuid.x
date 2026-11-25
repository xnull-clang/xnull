// xdk.uuid —— UUID v4/v7 与 ULID（M18.1）
//
// 16 字节值语义；v4/v7 使用 OS 安全随机；ULID 支持同毫秒单调。
// 稳定性：preview。合同见 docs/design/utils/uuid/。
package xdk.uuid
import xdk.errors
import xdk.bytes
import xdk.time

// ---------- UuidVersion ----------
enum UuidVersion {
    V4,
    V7,
}

String uuidVersionName(UuidVersion version) {
    if version == UuidVersion.V4 { return "v4" }
    return "v7"
}

// ---------- hex / byte helpers ----------
static String uuidHexDigits() {
    return "0123456789abcdef"
}

static Int uuidHexValue(Int code) {
    if code >= 48 && code <= 57 { return code - 48 }
    if code >= 97 && code <= 102 { return code - 97 + 10 }
    if code >= 65 && code <= 70 { return code - 65 + 10 }
    return -1
}

static Bool uuidIsHex(String text) {
    Int index = 0
    while index < text.length() {
        if uuidHexValue(text.get(index)) < 0 { return false }
        index = index + 1
    }
    return true
}

static String uuidFormat(Bytes bytes) {
    String digits = uuidHexDigits()
    String result = ""
    Int index = 0
    while index < 16 {
        if index == 4 || index == 6 || index == 8 || index == 10 {
            result = result + "-"
        }
        Int value = bytes.get(index)
        result = result + digits.substring(value / 16, 1) + digits.substring(value % 16, 1)
        index = index + 1
    }
    return result
}

static Int uuidCompareBytes(Bytes left, Bytes right) {
    Int index = 0
    while index < 16 {
        Int a = left.get(index)
        Int b = right.get(index)
        if a < b { return -1 }
        if a > b { return 1 }
        index = index + 1
    }
    return 0
}

// ---------- Uuid ----------
class Uuid {
    final Bytes _bytes

    private Uuid(Bytes bytes) {
        if bytes == null || bytes.length() != 16 {
            throw "Uuid: invalid bytes"
        }
        self._bytes = copy(bytes)
    }

    static Result<Uuid, Error> v4() {
        String hex = secureRandomHexRaw(16)
        if hex.length() != 32 {
            return Err(new BasicError(ErrorKind.Unavailable, "Uuid.v4: random source unavailable"))
        }
        Bytes bytes = fromHex(hex)
        bytes.set(6, (bytes.get(6) & 0x0F) | 0x40)
        bytes.set(8, (bytes.get(8) & 0x3F) | 0x80)
        return Ok(new Uuid(bytes))
    }

    static Result<Uuid, Error> v7() {
        String hex = secureRandomHexRaw(16)
        if hex.length() != 32 {
            return Err(new BasicError(ErrorKind.Unavailable, "Uuid.v7: random source unavailable"))
        }
        Bytes bytes = fromHex(hex)
        Long millis = nowWall()
        bytes.set(0, (((millis >> 40) & (255 as Long)) as Int))
        bytes.set(1, (((millis >> 32) & (255 as Long)) as Int))
        bytes.set(2, (((millis >> 24) & (255 as Long)) as Int))
        bytes.set(3, (((millis >> 16) & (255 as Long)) as Int))
        bytes.set(4, (((millis >> 8) & (255 as Long)) as Int))
        bytes.set(5, ((millis & (255 as Long)) as Int))
        bytes.set(6, (bytes.get(6) & 0x0F) | 0x70)
        bytes.set(8, (bytes.get(8) & 0x3F) | 0x80)
        return Ok(new Uuid(bytes))
    }

    static Result<Uuid, Error> parse(String text) {
        if text == null { throw "Uuid.parse: null text" }
        String lower = text.toLower()
        String hex = ""
        if lower.length() == 36 {
            if lower.substring(8, 1) != "-" || lower.substring(13, 1) != "-" ||
               lower.substring(18, 1) != "-" || lower.substring(23, 1) != "-" {
                return Err(new BasicError(ErrorKind.InvalidArgument, "Uuid.parse: invalid hyphens"))
            }
            hex = lower.substring(0, 8) + lower.substring(9, 4) + lower.substring(14, 4) +
                lower.substring(19, 4) + lower.substring(24, 12)
        } else if lower.length() == 32 {
            hex = lower
        } else {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Uuid.parse: invalid length"))
        }
        if !uuidIsHex(hex) {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Uuid.parse: invalid hex"))
        }
        Bytes bytes = fromHex(hex)
        Int version = bytes.get(6) >> 4
        if version != 4 && version != 7 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Uuid.parse: unsupported version"))
        }
        return Ok(new Uuid(bytes))
    }

    static Uuid fromBytes(Bytes bytes) {
        return new Uuid(bytes)
    }

    Bytes bytes() {
        return copy(self._bytes)
    }

    UuidVersion version() {
        Int value = self._bytes.get(6) >> 4
        if value == 7 { return UuidVersion.V7 }
        return UuidVersion.V4
    }

    Int variant() {
        return self._bytes.get(8) >> 6
    }

    Long? timestamp() {
        if self.version() != UuidVersion.V7 { return null }
        Long value = 0 as Long
        Int index = 0
        while index < 6 {
            value = (value << 8) | (self._bytes.get(index) as Long)
            index = index + 1
        }
        return value
    }

    Bool isNil() {
        Int index = 0
        while index < 16 {
            if self._bytes.get(index) != 0 { return false }
            index = index + 1
        }
        return true
    }

    Bool equals(Uuid other) {
        if other == null { return false }
        return uuidCompareBytes(self._bytes, other._bytes) == 0
    }

    Int compare(Uuid other) {
        if other == null { throw "Uuid.compare: null" }
        return uuidCompareBytes(self._bytes, other._bytes)
    }

    String toString() {
        return uuidFormat(self._bytes)
    }
}

// ---------- Ulid ----------
class Ulid {
    final Bytes _bytes

    private Ulid(Bytes bytes) {
        if bytes == null || bytes.length() != 16 {
            throw "Ulid: invalid bytes"
        }
        self._bytes = copy(bytes)
    }

    static String ulidAlphabet() {
        return "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    }

    static Int ulidValue(String text, Int index) {
        String alphabet = Ulid.ulidAlphabet()
        String upper = text.toUpper()
        Int probe = 0
        while probe < alphabet.length() {
            if alphabet.substring(probe, 1) == upper.substring(index, 1) {
                return probe
            }
            probe = probe + 1
        }
        return -1
    }

    static Result<Ulid, Error> generate(Bool monotonic) {
        String hex = secureRandomHexRaw(16)
        if hex.length() != 32 {
            return Err(new BasicError(ErrorKind.Unavailable, "Ulid.generate: random source unavailable"))
        }
        Bytes bytes = fromHex(hex)
        Long millis = nowWall()
        bytes.set(0, (((millis >> 40) & (255 as Long)) as Int))
        bytes.set(1, (((millis >> 32) & (255 as Long)) as Int))
        bytes.set(2, (((millis >> 24) & (255 as Long)) as Int))
        bytes.set(3, (((millis >> 16) & (255 as Long)) as Int))
        bytes.set(4, (((millis >> 8) & (255 as Long)) as Int))
        bytes.set(5, (millis & 255 as Long) as Int)
        if monotonic {
            Long sequence = ulidMonotonicRaw(millis)
            bytes.set(6, (((sequence >> 24) & (255 as Long)) as Int))
            bytes.set(7, (((sequence >> 16) & (255 as Long)) as Int))
            bytes.set(8, (((sequence >> 8) & (255 as Long)) as Int))
            bytes.set(9, ((sequence & (255 as Long)) as Int))
        }
        return Ok(new Ulid(bytes))
    }

    static Result<Ulid, Error> parse(String text) {
        if text == null { throw "Ulid.parse: null text" }
        if text.length() != 26 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Ulid.parse: invalid length"))
        }
        String upper = text.toUpper()
        Int first = Ulid.ulidValue(upper, 0)
        if first < 0 || first > 7 {
            return Err(new BasicError(ErrorKind.InvalidArgument, "Ulid.parse: invalid leading character"))
        }
        List<Int> values = []
        Int index = 0
        while index < 26 {
            Int value = Ulid.ulidValue(upper, index)
            if value < 0 {
                return Err(new BasicError(ErrorKind.InvalidArgument, "Ulid.parse: invalid character"))
            }
            values.push(value)
            index = index + 1
        }
        Bytes bytes = Bytes.alloc(16)
        Int bitIndex = 127
        Int pos = 25
        while pos >= 0 {
            Int value = values.get(pos)
            Int bit = 0
            while bit < 5 {
                if bitIndex >= 0 {
                    Int byteIndex = bitIndex / 8
                    Int bitInByte = 7 - (bitIndex % 8)
                    if ((value >> bit) & 1) == 1 {
                        bytes.set(byteIndex, bytes.get(byteIndex) | (1 << bitInByte))
                    }
                    bitIndex = bitIndex - 1
                }
                bit = bit + 1
            }
            pos = pos - 1
        }
        return Ok(new Ulid(bytes))
    }

    static Ulid fromBytes(Bytes bytes) {
        return new Ulid(bytes)
    }

    Long timestamp() {
        Long value = 0 as Long
        Int index = 0
        while index < 6 {
            value = (value << 8) | (self._bytes.get(index) as Long)
            index = index + 1
        }
        return value
    }

    Bytes randomness() {
        return self._bytes.slice(6, 16)
    }

    Bytes bytes() {
        return copy(self._bytes)
    }

    Bool equals(Ulid other) {
        if other == null { return false }
        return uuidCompareBytes(self._bytes, other._bytes) == 0
    }

    Int compare(Ulid other) {
        if other == null { throw "Ulid.compare: null" }
        return uuidCompareBytes(self._bytes, other._bytes)
    }

    String toString() {
        String alphabet = Ulid.ulidAlphabet()
        List<Int> values = []
        Int index = 0
        while index < 26 {
            values.push(0)
            index = index + 1
        }
        Int bitIndex = 127
        Int pos = 25
        while pos >= 0 {
            Int value = 0
            Int bit = 0
            while bit < 5 {
                if bitIndex >= 0 {
                    Int byteIndex = bitIndex / 8
                    Int bitInByte = 7 - (bitIndex % 8)
                    Int current = (self._bytes.get(byteIndex) >> bitInByte) & 1
                    if current == 1 { value = value | (1 << bit) }
                    bitIndex = bitIndex - 1
                }
                bit = bit + 1
            }
            values.set(pos, value)
            pos = pos - 1
        }
        String result = ""
        index = 0
        while index < 26 {
            result = result + alphabet.substring(values.get(index), 1)
            index = index + 1
        }
        return result
    }
}
