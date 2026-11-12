// B4b-03b-2：最小配置读取（只取 build 需要的键）。
//
// 用法：config <xnull.project>
// 输出：`build.<key>\t<value>`（仅 `build { … }` 顶层标量字段，按出现顺序）。
//
// 未支持（B4b-03c）：properties 变量替换、profile 合并、五/六层覆盖、类型校验。

import xdk.sys

// 触发器：Go codegen 在没有任何 class 时会漏发部分预置（xn_arr_s）；保留最小类。
class ConfigCtx {
    Int unused = 0
}

static Int countChar(String s, String ch) {
    Int n = 0
    Int i = 0
    while i < s.length() {
        if s.substring(i, 1) == ch { n = n + 1 }
        i = i + 1
    }
    return n
}

static String trimSp(String s) {
    Int b = 0
    Int e = s.length()
    Bool go = true
    while go {
        if b >= e { go = false }
        else if s.substring(b, 1) == " " || s.substring(b, 1) == "\t" { b = b + 1 }
        else { go = false }
    }
    go = true
    while go {
        if e <= b { go = false }
        else if s.substring(e - 1, 1) == " " || s.substring(e - 1, 1) == "\t" { e = e - 1 }
        else { go = false }
    }
    return s.substring(b, e - b)
}

static Int findChar(String s, String ch) {
    Int i = 0
    Bool go = true
    Int at = -1
    while go {
        if i >= s.length() { go = false }
        else if s.substring(i, 1) == ch { at = i; go = false }
        else { i = i + 1 }
    }
    return at
}

static Int main(String[] args) {
    ConfigCtx ctx = new ConfigCtx()
    ctx.unused = 0
    if args.length() < 1 {
        print("config: 需要 <xnull.project>")
        return 2
    }
    String src = readFileText(args[0])
    String[] ls = src.split("\n")
    List<String> outLines = []
    Int depth = 0
    Int inBuild = 0
    Int i = 0
    while i < ls.length() {
        String raw = ls[i]
        Int hash = findChar(raw, "#")
        String line = raw
        if hash >= 0 { line = raw.substring(0, hash) }
        line = trimSp(line)
        if line != "" {
            if inBuild == 0 {
                if line == "build {" || line.startsWith("build {") { inBuild = 1; depth = 1 }
            } else {
                Int opens = countChar(line, "{")
                Int closes = countChar(line, "}")
                if depth == 1 {
                    Int eq = findChar(line, "=")
                    if eq > 0 && opens == 0 && closes == 0 {
                        String k = trimSp(line.substring(0, eq))
                        String v = trimSp(line.substring(eq + 1, line.length() - eq - 1))
                        outLines.push("build." + k + "\t" + v)
                    }
                }
                depth = depth + opens - closes
                if depth <= 0 { inBuild = 0; depth = 0 }
            }
        }
        i = i + 1
    }
    Int k = 0
    while k < outLines.length() {
        print(outLines.get(k))
        k = k + 1
    }
    return 0
}
