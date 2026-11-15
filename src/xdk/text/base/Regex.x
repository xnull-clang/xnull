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
























































































































































































































































class Regex {
    final String pattern;

    Regex(String pattern) {
        self.pattern = pattern
    }

    static Result<Regex, Error> compile(String pattern) {
        Int i = 0
        while i < pattern.length() {
            String ch = pattern.substring(i, 1)
            if ch == "(" || ch == ")" || ch == "[" || ch == "]" || ch == "|" || ch == "\\" {
                return Err(textErr("Regex.compile: 暂不支持该 ERE 构造"))
            }
            if (ch == "*" || ch == "+" || ch == "?") && i == 0 {
                return Err(textErr("Regex.compile: 量词缺少原子"))
            }
            if ch == "$" && i != pattern.length() - 1 {
                return Err(textErr("Regex.compile: $ 只能在末尾"))
            }
            i = i + 1
        }
        return Ok(new Regex(pattern))
    }

    Bool isMatch(String text) {
        Int pi = 0
        if self.pattern.length() > 0 && self.pattern.substring(0, 1) == "^" {
            return regexMatchAt(self.pattern, 1, text, 0)
        }
        Int start = 0
        while start <= text.length() {
            if regexMatchAt(self.pattern, 0, text, start) { return true }
            start = start + 1
        }
        return false
    }
}
