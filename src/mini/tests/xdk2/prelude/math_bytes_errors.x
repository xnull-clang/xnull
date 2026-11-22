// B3.4 isFinite/isNaN、Bytes.alloc/empty、errors helpers。
import xdk.math
import xdk.bytes
import xdk.errors

static Result<Int, Error> okValue() {
    return Ok(4)
}

static Result<Int, Error> badValue() {
    return Err(new BasicError(ErrorKind.NotFound, "missing"))
}

static Result<Result<Int, Error>, Error> nestedValue() {
    return Ok(okValue())
}

static Int main() {
    // math：有限/NaN/Inf 判定。
    print(isFinite(0.0))
    print(isFinite(-1.5))
    print(isFinite(Inf()))
    print(isFinite(NaN()))
    print(isNaN(NaN()))
    print(isNaN(1.0))
    print(isInf(Inf()))
    print(isInf(-1.0))

    // bytes：空缓冲、定长清零、写入/读取、十六进制。
    Bytes empty = Bytes.empty()
    print(empty.length())
    print(empty.length() == 0)
    Bytes zero = Bytes.alloc(0)
    print(zero.length())
    Bytes data = Bytes.alloc(3)
    print(data.length())
    print(data.get(0))
    print(data.get(1))
    print(data.get(2))
    data.set(0, 255)
    data.set(1, 16)
    print(data.get(0))
    print(data.get(1))
    print(toHex(data))

    // errors：Result 组合 helpers。
    Result<Int, Error> ok = okValue()
    Result<Int, Error> bad = badValue()
    print(expect(ok, "boom"))
    print(unwrapOr(bad, 8))
    List<Result<Int, Error>> results = []
    results.push(ok)
    results.push(bad)
    print(collectAll(results).isErr())
    print(flattenResult(nestedValue()).value())
    return 0
}
