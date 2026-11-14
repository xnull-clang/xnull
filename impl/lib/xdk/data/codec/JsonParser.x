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
























































































































































































































































































































































































































































// JSON 解析器（递归下降；索引游标）。
class JsonParser {
    String s
    Int i

    JsonParser(String s0) {
        self.s = s0
        self.i = 0
    }

    void skipWs() {
        while self.i < self.s.length() {
            Int byte = self.s.get(self.i)
            if byte == 32 || byte == 9 || byte == 10 || byte == 13 {
                self.i = self.i + 1
            } else {
                return
            }
        }
    }

    Int peek() {
        if self.i >= self.s.length() {
            return -1
        }
        return self.s.get(self.i)
    }

    Result<JsonValue, Error> parseValue() {
        self.skipWs()
        Int c = self.peek()
        if c == 110 {
            return self.expectWord("null", 0)
        }
        if c == 116 {
            return self.expectWord("true", 1)
        }
        if c == 102 {
            return self.expectWord("false", 1)
        }
        if c == 34 {
            return self.parseString()
        }
        if c == 91 {
            return self.parseArray()
        }
        if c == 123 {
            return self.parseObject()
        }
        if c == 45 || (c >= 48 && c <= 57) {
            return self.parseNumber()
        }
        return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 非法值起始字符"))
    }

    Result<JsonValue, Error> expectWord(String word, Int kind) {
        Int n = word.length()
        Int j = 0
        while j < n {
            if self.i >= self.s.length() || self.s.get(self.i) != word.get(j) {
                return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 关键字非法"))
            }
            self.i = self.i + 1
            j = j + 1
        }
        JsonValue v = new JsonValue(kind)
        if kind == 1 {
            v.b = word.substring(0, 1) == "t"
        }
        return Ok(v)
    }

    Result<JsonValue, Error> parseNumber() {
        Int start = self.i
        if self.peek() == 45 {
            self.i = self.i + 1
        }
        Bool hasDigits = false
        while self.i < self.s.length() {
            Int c = self.s.get(self.i)
            if (c >= 48 && c <= 57) || c == 46 || c == 43 || c == 45 || c == 101 || c == 69 {
                if c >= 48 && c <= 57 {
                    hasDigits = true
                }
                self.i = self.i + 1
            } else {
                break
            }
        }
        if !hasDigits {
            return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 数字非法"))
        }
        String text = self.s.substring(start, self.i - start)
        Double d = parseDouble(text)
        if isNaN(d) {
            return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 数字非法"))
        }
        return Ok(jsonNumber(d))
    }

    Result<JsonValue, Error> parseString() {
        self.i = self.i + 1
        Bytes buf = Bytes.fromString("")
        while self.i < self.s.length() {
            Int c = self.s.get(self.i)
            if c == 34 {
                self.i = self.i + 1
                return Ok(jsonStringValue(buf.toString()))
            }
            if c == 92 {
                self.i = self.i + 1
                if self.i >= self.s.length() {
                    return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 转义截断"))
                }
                Int e = self.s.get(self.i)
                if e == 34 { buf.push(34) }
                else if e == 92 { buf.push(92) }
                else if e == 47 { buf.push(47) }
                else if e == 98 { buf.push(8) }
                else if e == 102 { buf.push(12) }
                else if e == 110 { buf.push(10) }
                else if e == 114 { buf.push(13) }
                else if e == 116 { buf.push(9) }
                else if e == 117 {
                    return Err(sysError(ErrorKind.Unsupported, "jsonParse: \\u 转义 v1 暂不支持"))
                }
                else {
                    return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 非法转义"))
                }
                self.i = self.i + 1
                continue
            }
            buf.push(c)
            self.i = self.i + 1
        }
        return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 字符串未闭合"))
    }

    Result<JsonValue, Error> parseArray() {
        self.i = self.i + 1
        JsonValue arr = new JsonValue(4)
        self.skipWs()
        if self.peek() == 93 {
            self.i = self.i + 1
            return Ok(arr)
        }
        while true {
            Result<JsonValue, Error> item = self.parseValue()
            if item.isErr() {
                return item
            }
            arr.push(item.value())
            self.skipWs()
            Int c = self.peek()
            if c == 44 {
                self.i = self.i + 1
                continue
            }
            if c == 93 {
                self.i = self.i + 1
                return Ok(arr)
            }
            return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 数组分隔符缺失"))
        }
    }

    Result<JsonValue, Error> parseObject() {
        self.i = self.i + 1
        JsonValue obj = new JsonValue(5)
        self.skipWs()
        if self.peek() == 125 {
            self.i = self.i + 1
            return Ok(obj)
        }
        while true {
            self.skipWs()
            if self.peek() != 34 {
                return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 对象键必须是字符串"))
            }
            Result<JsonValue, Error> keyJ = self.parseString()
            if keyJ.isErr() {
                return keyJ
            }
            self.skipWs()
            if self.peek() != 58 {
                return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 缺少冒号"))
            }
            self.i = self.i + 1
            Result<JsonValue, Error> val = self.parseValue()
            if val.isErr() {
                return val
            }
            obj.setKey(keyJ.value().asString(), val.value())
            self.skipWs()
            Int c = self.peek()
            if c == 44 {
                self.i = self.i + 1
                continue
            }
            if c == 125 {
                self.i = self.i + 1
                return Ok(obj)
            }
            return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 对象分隔符缺失"))
        }
    }
}
