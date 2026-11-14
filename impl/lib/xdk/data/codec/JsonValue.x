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
























































































































































































































// ---------- JSON ----------
class JsonValue {
    Int kind        // 0=null 1=bool 2=number 3=string 4=array 5=object
    Bool b
    Double num
    String str
    List<JsonValue> arr
    List<String> objKeys
    List<JsonValue> objVals

    JsonValue(Int kind0) {
        self.kind = kind0
        self.b = false
        self.num = 0.0
        self.str = ""
        self.arr = []
        self.objKeys = []
        self.objVals = []
    }

    Bool isNull() { return self.kind == 0 }
    Bool isBool() { return self.kind == 1 }
    Bool isNumber() { return self.kind == 2 }
    Bool isString() { return self.kind == 3 }
    Bool isArray() { return self.kind == 4 }
    Bool isObject() { return self.kind == 5 }

    Bool asBool() { return self.b }
    Double asDouble() { return self.num }
    Int asInt() { return self.num as Int }
    String asString() { return self.str }
    List<JsonValue> asList() { return self.arr }
    List<String> keys() { return self.objKeys }

    JsonValue get(String key) {
        Int i = 0
        while i < self.objKeys.length() {
            if self.objKeys.get(i) == key {
                return self.objVals.get(i)
            }
            i = i + 1
        }
        return new JsonValue(0)
    }

    JsonValue at(Int idx) {
        if idx < 0 || idx >= self.arr.length() {
            return new JsonValue(0)
        }
        return self.arr.get(idx)
    }

    Int size() {
        if self.kind == 4 {
            return self.arr.length()
        }
        return self.objKeys.length()
    }

    void setKey(String key, JsonValue v) {
        Int i = 0
        while i < self.objKeys.length() {
            if self.objKeys.get(i) == key {
                self.objVals.set(i, v)
                return
            }
            i = i + 1
        }
        self.objKeys.push(key)
        self.objVals.push(v)
    }

    void push(JsonValue v) {
        self.arr.push(v)
    }

    String stringify() {
        return jsonStringify(self)
    }

    String pretty(Int indent) {
        return jsonPretty(self, indent, 0)
    }
}
