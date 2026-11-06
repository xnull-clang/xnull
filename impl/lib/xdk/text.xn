// xdk.text 的纯 XNull 辅助（M4.6a 种子单元）
//
// 说明：本单元只使用当前已可编译的语言面（Int/Bool/String、拼接、if、
// 顶层函数与递归），不含 extern/类/枚举/String 方法与可变 String——
// 那些形态随 M4.5b 的调用钩子、M4.4 的类与容器一起接入。
// 稳定性：@preview（语言面扩齐后转 @stable）。

// repeatText：把 unit 重复 times 次；times <= 0 返回空串。
String repeatText(String unit, Int times) {
    if (times <= 0) {
        return ""
    }
    return unit + repeatText(unit, times - 1)
}

// repeatJoined：把 unit 以 sep 连接重复 times 次（times <= 0 返回空串）。
String repeatJoined(String unit, String sep, Int times) {
    if (times <= 0) {
        return ""
    }
    if (times == 1) {
        return unit
    }
    return unit + sep + repeatJoined(unit, sep, times - 1)
}

// isPositive：n > 0（Bool 面示例，供 XDK 合同用例复用）。
Bool isPositive(Int n) {
    return n > 0
}
