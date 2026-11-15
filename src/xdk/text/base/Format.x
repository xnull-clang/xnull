// xdk.text —— S6-05 源码单元（Format builder / parse / UTF-8↔UTF-16 / Regex）
//
// 依赖：xdk.errors（错误值）；C 原语对应 src/runtime/rt_std_text.c
// （parse_int/parse_float/utf8_to_utf16/utf16_to_utf8/regex_match；解释器路径由等价源码执行）。
// 稳定性：@preview。
// 合同：可失败操作返回 Result；Regex 动态编译失败是可恢复错误，不 panic。
package xdk.text
import xdk.errors

// ---------- 格式化 builder ----------

// Format：链式格式化构造器（Format.int(7).width(4).pad('0').build()）。
class Format {
    final String text;
    final Int width;
    final Char pad;

    Format(String text, Int width, Char pad) {
        self.text = text
        self.width = width
        self.pad = pad
    }

    static Format int(Int v) {
        return new Format(str(v), 0, ' ')
    }

    static Format float(Double v) {
        return new Format($"{(v)}", 0, ' ')
    }

    static Format string(String v) {
        return new Format(v, 0, ' ')
    }

    static Format bool(Bool v) {
        if v {
            return new Format("true", 0, ' ')
        }
        return new Format("false", 0, ' ')
    }

    Format width(Int w) {
        return new Format(self.text, w, self.pad)
    }

    Format pad(Char c) {
        return new Format(self.text, self.width, c)
    }

    String build() {
        String res = self.text
        String unit = $"{self.pad}"
        while res.length() < self.width {
            res = unit + res
        }
        return res
    }
}
