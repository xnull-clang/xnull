// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 与 src/xdk/text.x（默认构建面）同源；追加顶层工厂与 Utf16 包装。
// 默认构建不加载本单元，避免改变冻结 golden。
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

    static Format int(Int value) {
        return new Format(str(value), 0, ' ')
    }

    static Format float(Double value) {
        return new Format($"{(value)}", 0, ' ')
    }

    static Format string(String value) {
        return new Format(value, 0, ' ')
    }

    static Format bool(Bool value) {
        if value {
            return new Format("true", 0, ' ')
        }
        return new Format("false", 0, ' ')
    }

    Format width(Int width) {
        return new Format(self.text, width, self.pad)
    }

    Format pad(Char padding) {
        return new Format(self.text, self.width, padding)
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
