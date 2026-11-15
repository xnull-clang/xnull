// xdk.text —— mini 引擎最小文本面
package xdk.text

String padLeft(String s, Int width, String ch) {
    String out = s
    while out.length() < width {
        out = ch + out
    }
    return out
}

String repeatText(String unit, Int times) {
    String out = ""
    Int i = 0
    while i < times {
        out = out + unit
        i = i + 1
    }
    return out
}

Bool contains(String s, String sub) {
    return s.indexOf(sub) >= 0
}
