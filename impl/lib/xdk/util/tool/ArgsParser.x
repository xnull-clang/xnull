// xdk.util —— 常用工具包：哈希校验 / UUID / 压缩 / 日志 / 断言 / 参数解析。
// 约定：
//   - 哈希后端经 ext_raw（rt_std_ext.c，参考值已对齐公开标准）；
//   - Bytes 进出统一走 hex 中转（冻结编译器 Bytes 借出 ABI 限制，已知缺口）；
//   - 断言失败走 exit(1)（S1 §10.3 语义，无 defer）。
package xdk.util
import xdk.errors
import xdk.sys
import xdk.codec

// ---------- 哈希与校验 ----------










































































































































































































































































































class ArgsParser {
    List<String> flagNames
    List<String> optionNames
    Int positionalCount

    ArgsParser() {
        self.flagNames = []
        self.optionNames = []
        self.positionalCount = 0
    }

    void flag(String name) {
        self.flagNames.push(name)
    }

    void option(String name) {
        self.optionNames.push(name)
    }

    void positional(String name) {
        self.positionalCount = self.positionalCount + 1
    }

    Result<Args, Error> parse(List<String> args) {
        Args out = new Args()
        Int i = 0
        while i < args.length() {
            String a = args.get(i)
            if a.length() > 2 && a.substring(0, 2) == "--" {
                String body = a.substring(2, a.length() - 2)
                Int eq = body.indexOf("=")
                String name = body
                String value = ""
                if eq >= 0 {
                    name = body.substring(0, eq)
                    value = body.substring(eq + 1, body.length() - eq - 1)
                }
                Bool isFlag = inList(self.flagNames, name)
                Bool isOpt = inList(self.optionNames, name)
                if !isFlag && !isOpt {
                    return Err(sysError(ErrorKind.InvalidArgument, "parse: 未知参数 " + name))
                }
                if isFlag {
                    if eq >= 0 {
                        out.put(name, value)
                    } else {
                        out.put(name, "true")
                    }
                } else {
                    if eq >= 0 {
                        out.put(name, value)
                    } else {
                        if i + 1 >= args.length() {
                            return Err(sysError(ErrorKind.InvalidArgument, "parse: " + name + " 缺少值"))
                        }
                        i = i + 1
                        out.put(name, args.get(i))
                    }
                }
            } else {
                out.positionals.push(a)
            }
            i = i + 1
        }
        if out.positionals.length() > self.positionalCount {
            return Err(sysError(ErrorKind.InvalidArgument, "parse: 位置参数过多"))
        }
        return Ok(out)
    }

    String help() {
        String out = "Usage:\n"
        Int i = 0
        while i < self.flagNames.length() {
            out = out + "  --" + self.flagNames.get(i) + "\n"
            i = i + 1
        }
        i = 0
        while i < self.optionNames.length() {
            out = out + "  --" + self.optionNames.get(i) + "=<value>\n"
            i = i + 1
        }
        Int j = 0
        while j < self.positionalCount {
            out = out + "  <arg" + str(j) + ">\n"
            j = j + 1
        }
        return out
    }
}
