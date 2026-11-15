// XNull 版词法器（Go xfront.Lex 的 L1 token dump 对照实现）。
// 只输出 token/AST 层数据，不依赖 Go xfront；lex 诊断以 code/line/col 输出。
// 覆盖：注释/BOM/CRLF、自动分号、数字/字符/字符串/插值（基础）、关键字、运算符。
package xdk.compiler.lexer; import xdk.text










class Tok {
    Int kind = 0
    String text = ""
    Int line = 1
    Int col = 1
    Int str = 0
    String value = ""
    List<String> segs = []
    List<String> interps = []
    Int ch = 0
    Int base = 0
    String suffix = ""
    Bool hasSuffixF = false
}
