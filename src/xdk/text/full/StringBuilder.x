// xdk.text —— T0 StringBuilder（append-only 文本构造器）
// Tier: T0；依赖：无（随 xdk.text 编入）；稳定性：preview。
//
// 合同：引用类型、可变；append* 返回 self 以便链式调用；toString() 返回当前
// 内容的不可变快照；length() 返回 UTF-8 字节数。空 builder 的 toString() 为 ""。
package xdk.text

class StringBuilder {
    String _text = ""

    StringBuilder() {
    }

    Int length() {
        return self._text.length()
    }

    Bool isEmpty() {
        return self._text.length() == 0
    }

    StringBuilder append(String text) {
        self._text = self._text + text
        return self
    }

    StringBuilder appendInt(Int value) {
        self._text = self._text + str(value)
        return self
    }

    StringBuilder appendLong(Long value) {
        self._text = self._text + str(value)
        return self
    }

    StringBuilder appendChar(Char value) {
        self._text = self._text + $"{value}"
        return self
    }

    StringBuilder clear() {
        self._text = ""
        return self
    }

    String toString() {
        return self._text
    }
}
