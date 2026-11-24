package xdk2.crypto
import xdk.crypto
import xdk.bytes
import xdk.io
import xdk.tasks
import xdk.errors
import xdk.time

static Bytes bytesOf(String text) {
    return Bytes.fromString(text)
}

static Bytes binaryBytes() {
    Bytes result = Bytes.fromString("")
    result.push(0)
    result.push(255)
    result.push(1)
    return result
}

static Bytes repeated(Int value, Int count) {
    Bytes result = Bytes.fromString("")
    Int index = 0
    while index < count {
        result.push(value)
        index = index + 1
    }
    return result
}

static Int main() {
    Bytes abc = bytesOf("abc")
    print("md5=" + Hash.hex(HashAlgorithm.Md5, abc))
    print("sha1-length=" + str(Hash.hex(HashAlgorithm.Sha1, abc).length()))
    print("sha256=" + Hash.hex(HashAlgorithm.Sha256, abc))
    print("sha512-length=" + str(Hash.hex(HashAlgorithm.Sha512, abc).length()))
    print("sha256-b64=" + Hash.base64(HashAlgorithm.Sha256, abc))
    print("sha256-empty=" + Hash.hex(HashAlgorithm.Sha256, bytesOf("")))
    print("sha256-binary=" + Hash.hex(HashAlgorithm.Sha256, binaryBytes()))
    print("length=" + str(Hash.length(HashAlgorithm.Md5)) + "," + str(Hash.length(HashAlgorithm.Sha1)) + "," +
        str(Hash.length(HashAlgorithm.Sha256)) + "," + str(Hash.length(HashAlgorithm.Sha512)) + "," +
        str(Hash.length(HashAlgorithm.Sha3_256)))

    Reader reader = new Reader(abc)
    Context context = Context.background()
    Result<Bytes, Error> streamed = Hash.hashReader(context, HashAlgorithm.Sha256, reader)
    print("reader=" + str(streamed.isOk()) + "," + toHex(streamed.value()))
    Context cancelled = Context.background()
    cancelled.cancel()
    Reader cancelledReader = new Reader(abc)
    Result<Bytes, Error> cancelledResult = Hash.hashReader(cancelled, HashAlgorithm.Sha256, cancelledReader)
    print("reader-cancel=" + str(cancelledResult.isErr()) + "," +
        errorKindName(cancelledResult.error().kind()))

    Bytes key1 = repeated(11, 20)
    Bytes key2 = bytesOf("Jefe")
    Bytes data1 = bytesOf("Hi There")
    Bytes data2 = bytesOf("what do ya want for nothing?")
    print("hmac1=" + Hmac.hex(HashAlgorithm.Sha256, key1, data1))
    print("hmac2=" + Hmac.hex(HashAlgorithm.Sha256, key2, data2))
    print("hmac-b64=" + Hmac.base64(HashAlgorithm.Sha256, key2, data2))
    Bytes mac = Hmac.sign(HashAlgorithm.Sha256, key2, data2)
    print("hmac-verify=" + str(Hmac.verify(HashAlgorithm.Sha256, key2, data2, mac)) + "," +
        str(Hmac.verify(HashAlgorithm.Sha256, key2, bytesOf("changed"), mac)) + "," +
        str(Hmac.verify(HashAlgorithm.Sha256, key2, data2, bytesOf("short"))))
    print("hmac-sha1=" + Hmac.hex(HashAlgorithm.Sha1, key2, data2))
    print("hmac-binary=" + Hmac.hex(HashAlgorithm.Sha256, bytesOf("key"), binaryBytes()))

    Bytes vector = bytesOf("123456789")
    print("crc32=" + Checksum.hex(ChecksumAlgorithm.Crc32, vector))
    print("crc32c=" + Checksum.hex(ChecksumAlgorithm.Crc32c, vector))
    print("crc64=" + Checksum.hex(ChecksumAlgorithm.Crc64, vector))
    print("adler=" + Checksum.hex(ChecksumAlgorithm.Adler32, vector))
    print("fnv32=" + Checksum.hex(ChecksumAlgorithm.Fnv1a32, vector))
    print("fnv64=" + Checksum.hex(ChecksumAlgorithm.Fnv1a64, vector))
    print("checksum-empty=" + Checksum.hex(ChecksumAlgorithm.Crc32, bytesOf("")) + "," +
        Checksum.hex(ChecksumAlgorithm.Adler32, bytesOf("")))
    print("names=" + hashAlgorithmName(HashAlgorithm.Sha256) + "," +
        hashAlgorithmName(HashAlgorithm.Sha3_256) + "," +
        checksumAlgorithmName(ChecksumAlgorithm.Crc32c) + "," +
        str(parseHashAlgorithm("SHA-256") == HashAlgorithm.Sha256) + "," +
        str(parseHashAlgorithm("sm3") == HashAlgorithm.Sm3) + "," +
        str(parseHashAlgorithm("nope") == null))

    Bytes zero = Bytes.fromString("")
    zero.push(0)
    zero.push(0)
    Bytes one = Bytes.fromString("")
    one.push(0)
    one.push(1)
    print("ct=" + str(ConstantTime.equals(zero, zero)) + "," + str(ConstantTime.equals(zero, one)) + "," +
        str(ConstantTime.equals(zero, bytesOf("")) ) + "," + str(ConstantTime.isZero(zero)) + "," +
        str(ConstantTime.isZero(one)) + "," + str(ConstantTime.compare(zero, one) < 0) + "," +
        str(ConstantTime.compare(one, zero) > 0) + "," + str(ConstantTime.compare(zero, zero) == 0))
    return 0
}
