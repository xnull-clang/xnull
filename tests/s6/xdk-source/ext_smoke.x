import xdk.math
import xdk.time
import xdk.codec
import xdk.util
import xdk.text

static Int main() {
    // ---- math ----
    print(mathSmoke())

    // ---- time ----
    DateTime dt = dateTimeOf(2026, 11, 14, 8, 30, 5)
    print(dt.format("yyyy-MM-dd HH:mm:ss"))
    print(str(dt.weekday()))
    DateTime dt2 = dateTimeFromTimestamp(dt.timestamp() + 1500)
    print(str(dt2.diff(dt).seconds()))
    Result<DateTime, Error> parsed = parseDateTime("2026-11-14T08:30:05")
    print(str(parsed.isOk() && parsed.value().timestamp() == dt.timestamp()))

    // ---- codec ----
    print(base64Encode(Bytes.fromString("hello")))
    print(base64Decode("aGVsbG8=").value().toString())
    print(urlEncode("a b&c"))
    print(urlDecode("a%20b%26c"))
    Result<JsonValue, Error> j = jsonParse("{\"n\":42,\"s\":\"hi\",\"a\":[1,2,3]}")
    print(str(j.isOk() && j.value().get("s").asString() == "hi" && j.value().get("n").asInt() == 42))
    print(j.value().stringify())
    Result<CsvTable, Error> csv = csvParse("a,b\nc,\"d\"\"x\"")
    print(csv.value().row(1).get(1))
    BinaryWriter w = BinaryWriter()
    w.writeU32le(305419896)
    w.writeF64le(1.5)
    BinaryReader r = BinaryReader(w.toBytes())
    print(str(r.readU32le() == 305419896))
    print(str(approxEq(r.readF64le(), 1.5, 1e-9)))

    // ---- util ----
    print(sha256Hex(Bytes.fromString("abc")))
    print(str(crc32(Bytes.fromString("123456789"))))
    UUID u = uuidParse(uuid4()).value()
    print(str(u.str().length() == 36))
    Result<Bytes, Error> gz = gzipDecompress(gzipCompress(Bytes.fromString("gzip gzip gzip")).value())
    print(gz.value().toString())
    ArgsParser ap = ArgsParser()
    ap.flag("verbose")
    ap.option("out")
    List<String> argv = []
    argv.push("--verbose")
    argv.push("--out=x.txt")
    argv.push("pos")
    Result<Args, Error> pa = ap.parse(argv)
    print(str(pa.value().flag("verbose")) + "," + pa.value().option("out") + "," + pa.value().positional(0))

    // ---- text 扩展 ----
    print(str(contains("hello world", "wor")) + "," + str(count("aaa", "aa")))
    print(reverse("abc"))
    print(str(levenshtein("kitten", "sitting")))
    print(fromCodePoint(20013) + str(codePointAt("中", 0)))
    Result<Regex, Error> rx = regexCompile("(\\w+)@(\\w+)")
    Match? m = rx.value().find("mail: tom@example")
    print(m != null ? m.value().group(1) + "@" + m.value().group(2) : "null")
    print(rx.value().replaceAll("a1b2c3", "#"))
    List<String> parts = rx.value().split("x1y2")
    print(str(parts.length()) + "," + parts.get(1))
    return 0
}

// math 冒烟：sqrt/gcd/isPrime/统计/随机。
String mathSmoke() {
    Double s = sqrt(9.0)
    Bool ok1 = approxEq(s, 3.0, 1e-9)
    Bool ok2 = gcd(12, 18) == 6
    Bool ok3 = isPrime(97) && !isPrime(96)
    List<Double> xs = []
    xs.push(1.0)
    xs.push(2.0)
    xs.push(3.0)
    xs.push(4.0)
    Bool ok4 = approxEq(mean(xs), 2.5, 1e-9)
    Bool ok5 = approxEq(median(xs), 2.5, 1e-9)
    Bool ok6 = approxEq(quantile(xs, 0.5), 2.5, 1e-9)
    seedRandom(42)
    Int r1 = randomNext(1000)
    seedRandom(42)
    Bool ok7 = randomNext(1000) == r1
    Bool ok8 = approxEq(sin(deg2rad(30.0)), 0.5, 1e-6)
    Bool ok = ok1 && ok2 && ok3 && ok4 && ok5 && ok6 && ok7 && ok8
    return ok ? "math-ok" : "math-fail"
}
