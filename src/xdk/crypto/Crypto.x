package xdk.crypto
import xdk.errors
import xdk.bytes
import xdk.io
import xdk.tasks
import xdk.codec

enum HashAlgorithm {
    Unknown,
    Md5,
    Sha1,
    Sha224,
    Sha256,
    Sha384,
    Sha512,
    Sha3_256,
    Sha3_384,
    Sha3_512,
    Blake2b,
    Blake3,
    Sm3,
}

String hashAlgorithmName(HashAlgorithm algorithm) {
    if algorithm == HashAlgorithm.Md5 { return "md5" }
    if algorithm == HashAlgorithm.Sha1 { return "sha1" }
    if algorithm == HashAlgorithm.Sha224 { return "sha224" }
    if algorithm == HashAlgorithm.Sha256 { return "sha256" }
    if algorithm == HashAlgorithm.Sha384 { return "sha384" }
    if algorithm == HashAlgorithm.Sha512 { return "sha512" }
    if algorithm == HashAlgorithm.Sha3_256 { return "sha3-256" }
    if algorithm == HashAlgorithm.Sha3_384 { return "sha3-384" }
    if algorithm == HashAlgorithm.Sha3_512 { return "sha3-512" }
    if algorithm == HashAlgorithm.Blake2b { return "blake2b" }
    if algorithm == HashAlgorithm.Blake3 { return "blake3" }
    if algorithm == HashAlgorithm.Sm3 { return "sm3" }
    return "unknown"
}

HashAlgorithm? parseHashAlgorithm(String value) {
    if value == null { return null }
    String name = value.toLower().replace("_", "-")
    if name == "md5" { return HashAlgorithm.Md5 }
    if name == "sha1" || name == "sha-1" { return HashAlgorithm.Sha1 }
    if name == "sha224" || name == "sha-224" { return HashAlgorithm.Sha224 }
    if name == "sha256" || name == "sha-256" { return HashAlgorithm.Sha256 }
    if name == "sha384" || name == "sha-384" { return HashAlgorithm.Sha384 }
    if name == "sha512" || name == "sha-512" { return HashAlgorithm.Sha512 }
    if name == "sha3-256" { return HashAlgorithm.Sha3_256 }
    if name == "sha3-384" { return HashAlgorithm.Sha3_384 }
    if name == "sha3-512" { return HashAlgorithm.Sha3_512 }
    if name == "blake2b" { return HashAlgorithm.Blake2b }
    if name == "blake3" { return HashAlgorithm.Blake3 }
    if name == "sm3" { return HashAlgorithm.Sm3 }
    return null
}

enum ChecksumAlgorithm {
    Unknown,
    Crc32,
    Crc32c,
    Crc64,
    Adler32,
    Fnv1a32,
    Fnv1a64,
}

String checksumAlgorithmName(ChecksumAlgorithm algorithm) {
    if algorithm == ChecksumAlgorithm.Crc32 { return "crc32" }
    if algorithm == ChecksumAlgorithm.Crc32c { return "crc32c" }
    if algorithm == ChecksumAlgorithm.Crc64 { return "crc64" }
    if algorithm == ChecksumAlgorithm.Adler32 { return "adler32" }
    if algorithm == ChecksumAlgorithm.Fnv1a32 { return "fnv1a32" }
    if algorithm == ChecksumAlgorithm.Fnv1a64 { return "fnv1a64" }
    return "unknown"
}

static Error cryptoError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

static Void hashUnsupported(HashAlgorithm algorithm) {
    throw "Hash: Unsupported algorithm: " + hashAlgorithmName(algorithm)
}

static Bool hashImplemented(HashAlgorithm algorithm) {
    return algorithm == HashAlgorithm.Md5 || algorithm == HashAlgorithm.Sha1 ||
        algorithm == HashAlgorithm.Sha256 || algorithm == HashAlgorithm.Sha512
}

class Hash {
    private Hash() { }

    static Bytes digest(HashAlgorithm algorithm, Bytes data) {
        if data == null { throw "Hash.digest: null data" }
        if algorithm == null { throw "Hash.digest: null algorithm" }
        String input = data.toString()
        if algorithm == HashAlgorithm.Md5 { return fromHex(md5HexRaw(input)) }
        if algorithm == HashAlgorithm.Sha1 { return fromHex(sha1HexRaw(input)) }
        if algorithm == HashAlgorithm.Sha256 { return fromHex(sha256HexRaw(input)) }
        if algorithm == HashAlgorithm.Sha512 { return fromHex(sha512HexRaw(input)) }
        hashUnsupported(algorithm)
        return Bytes.fromString("")
    }

    static String hex(HashAlgorithm algorithm, Bytes data) {
        return toHex(Hash.digest(algorithm, data))
    }

    static String base64(HashAlgorithm algorithm, Bytes data) {
        return Base64.encode(Hash.digest(algorithm, data))
    }

    static Int length(HashAlgorithm algorithm) {
        if algorithm == HashAlgorithm.Md5 { return 16 }
        if algorithm == HashAlgorithm.Sha1 { return 20 }
        if algorithm == HashAlgorithm.Sha256 { return 32 }
        if algorithm == HashAlgorithm.Sha512 { return 64 }
        return 0
    }

    static Result<Bytes, Error> hashReader(Context context, HashAlgorithm algorithm, Reader reader) {
        if context == null || reader == null { throw "Hash.hashReader: null argument" }
        Bytes buffer = Bytes.fromString("")
        Int index = 0
        while reader.remaining() > 0 {
            if context.isCancelled() {
                return Err(cryptoError(ErrorKind.Cancelled, "hash reader cancelled"))
            }
            buffer.push(reader.readU8())
            index = index + 1
        }
        return Ok(Hash.digest(algorithm, buffer))
    }
}

class Hmac {
    private Hmac() { }

    static Bytes sign(HashAlgorithm algorithm, Bytes key, Bytes data) {
        if key == null || data == null { throw "Hmac.sign: null argument" }
        if algorithm == null { throw "Hmac.sign: null algorithm" }
        if !hashImplemented(algorithm) { hashUnsupported(algorithm) }
        if algorithm == HashAlgorithm.Sha256 {
            return fromHex(hmacSha256HexRaw(key.toString(), data.toString()))
        }
        Int blockSize = 64
        if algorithm == HashAlgorithm.Sha512 { blockSize = 128 }
        Bytes padded = key
        if key.length() > blockSize { padded = Hash.digest(algorithm, key) }
        Bytes inner = Bytes.fromString("")
        Bytes outer = Bytes.fromString("")
        Int index = 0
        while index < blockSize {
            Int value = 0
            if index < padded.length() { value = padded.get(index) }
            inner.push(value ^ 54)
            outer.push(value ^ 92)
            index = index + 1
        }
        Bytes innerHash = Hash.digest(algorithm, concatBytes(inner, data))
        return Hash.digest(algorithm, concatBytes(outer, innerHash))
    }

    static Bool verify(HashAlgorithm algorithm, Bytes key, Bytes data, Bytes mac) {
        if mac == null { return false }
        Bytes expected = Hmac.sign(algorithm, key, data)
        return ConstantTime.equals(expected, mac)
    }

    static String hex(HashAlgorithm algorithm, Bytes key, Bytes data) {
        return toHex(Hmac.sign(algorithm, key, data))
    }

    static String base64(HashAlgorithm algorithm, Bytes key, Bytes data) {
        return Base64.encode(Hmac.sign(algorithm, key, data))
    }
}

class Checksum {
    private Checksum() { }

    static Long compute(ChecksumAlgorithm algorithm, Bytes data) {
        if data == null { throw "Checksum.compute: null data" }
        if algorithm == ChecksumAlgorithm.Crc32 { return Checksum.crc(data, 3988292384 as Long, 32) }
        if algorithm == ChecksumAlgorithm.Crc32c { return Checksum.crc(data, 2197175160 as Long, 32) }
        if algorithm == ChecksumAlgorithm.Crc64 { return Checksum.crc(data, -3932672073523589310 as Long, 64) }
        if algorithm == ChecksumAlgorithm.Adler32 { return Checksum.adler(data) }
        if algorithm == ChecksumAlgorithm.Fnv1a32 { return Checksum.fnv32(data) }
        if algorithm == ChecksumAlgorithm.Fnv1a64 { return Checksum.fnv64(data) }
        return 0
    }

    static String hex(ChecksumAlgorithm algorithm, Bytes data) {
        Int width = 8
        if algorithm == ChecksumAlgorithm.Crc64 || algorithm == ChecksumAlgorithm.Fnv1a64 {
            width = 16
        }
        return Checksum.hexLong(Checksum.compute(algorithm, data), width)
    }

    private static Long crc(Bytes data, Long polynomial, Int bits) {
        if bits == 32 {
            Long crc = 4294967295 as Long
            Int index = 0
            while index < data.length() {
                crc = (crc ^ (data.get(index) as Long)) & 4294967295 as Long
                Int bit = 0
                while bit < 8 {
                    if (crc & (1 as Long)) != 0 {
                        crc = (crc >> 1) ^ polynomial
                    } else {
                        crc = crc >> 1
                    }
                    crc = crc & 4294967295 as Long
                    bit = bit + 1
                }
                index = index + 1
            }
            return crc ^ 4294967295 as Long
        }
        Long crc = -1
        Int index = 0
        while index < data.length() {
            crc = crc ^ (data.get(index) as Long)
            Int bit = 0
            while bit < 8 {
                if (crc & (1 as Long)) != 0 {
                    crc = ((crc >> 1) & (9223372036854775807 as Long)) ^ polynomial
                } else {
                    crc = (crc >> 1) & (9223372036854775807 as Long)
                }
                bit = bit + 1
            }
            index = index + 1
        }
        return crc ^ (-1 as Long)
    }

    private static Long adler(Bytes data) {
        Long a = 1
        Long b = 0
        Int index = 0
        while index < data.length() {
            a = (a + (data.get(index) as Long)) % 65521
            b = (b + a) % 65521
            index = index + 1
        }
        return (b << 16) | a
    }

    private static Long fnv32(Bytes data) {
        Long hash = 2166136261 as Long
        Int index = 0
        while index < data.length() {
            hash = hash ^ (data.get(index) as Long)
            hash = (hash * (16777619 as Long)) & 4294967295 as Long
            index = index + 1
        }
        return hash
    }

    private static Long fnv64(Bytes data) {
        Long hash = -3750763034362895579 as Long
        Int index = 0
        while index < data.length() {
            hash = hash ^ (data.get(index) as Long)
            hash = hash * (1099511628211 as Long)
            index = index + 1
        }
        return hash
    }

    private static String hexLong(Long value, Int width) {
        String digits = "0123456789abcdef"
        String result = ""
        Long current = value
        Int index = 0
        while index < width {
            Int nibble = (current & (15 as Long)) as Int
            result = digits.substring(nibble, 1) + result
            current = current >> 4
            index = index + 1
        }
        return result
    }
}

class ConstantTime {
    private ConstantTime() { }

    static Bool equals(Bytes left, Bytes right) {
        if left == null || right == null { throw "ConstantTime.equals: null argument" }
        Int limit = left.length()
        if right.length() > limit { limit = right.length() }
        Int difference = left.length() ^ right.length()
        Int index = 0
        while index < limit {
            Int a = 0
            Int b = 0
            if index < left.length() { a = left.get(index) }
            if index < right.length() { b = right.get(index) }
            difference = difference | (a ^ b)
            index = index + 1
        }
        return difference == 0
    }

    static Int compare(Bytes left, Bytes right) {
        if left == null || right == null { throw "ConstantTime.compare: null argument" }
        Int limit = left.length()
        if right.length() < limit { limit = right.length() }
        Int first = 0
        Int index = 0
        while index < limit {
            Int difference = left.get(index) - right.get(index)
            if first == 0 && difference != 0 { first = difference }
            index = index + 1
        }
        if first != 0 { return first }
        if left.length() < right.length() { return -1 }
        if left.length() > right.length() { return 1 }
        return 0
    }

    static Bool isZero(Bytes data) {
        if data == null { throw "ConstantTime.isZero: null data" }
        Int result = 0
        Int index = 0
        while index < data.length() {
            result = result | data.get(index)
            index = index + 1
        }
        return result == 0
    }
}
