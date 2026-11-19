// Tier: T1；依赖：xdk.text、xdk.sys；稳定性：preview。
// xdk.cli —— 命令行解析与用法（W5）
//
// 面：参数列表、flag/值查询（`--k v` 与 `--k=v`）、位置参数、usage 文本、
// 退出码映射。子命令与帮助渲染为后续切片。
package xdk.cli

static Bool isOption(String arg) {
    return arg.length() > 0 && arg.substring(0, 1) == "-"
}

static Bool matchesFlag(String arg, String flag) {
    return arg == flag || arg.startsWith(flag + "=")
}

class Args {
    List<String> raw

    Args(List<String> raw) {
        self.raw = raw
    }

    Int length() {
        return self.raw.length()
    }

    String get(Int i) {
        return self.raw.get(i)
    }

    Bool has(String flag) {
        Int i = 0
        while i < self.raw.length() {
            if matchesFlag(self.raw.get(i), flag) {
                return true
            }
            i = i + 1
        }
        return false
    }

    String value(String flag) {
        String prefix = flag + "="
        String result = ""
        Bool found = false
        Int i = 0
        while i < self.raw.length() {
            String arg = self.raw.get(i)
            if !found && arg == flag {
                if i + 1 < self.raw.length() {
                    result = self.raw.get(i + 1)
                }
                found = true
            }
            if !found && arg.startsWith(prefix) {
                result = arg.substring(prefix.length(), arg.length() - prefix.length())
                found = true
            }
            i = i + 1
        }
        return result
    }

    String valueOr(String flag, String fallback) {
        String v = self.value(flag)
        if v == "" {
            return fallback
        }
        return v
    }

    List<String> positionals() {
        List<String> res = []
        Bool skipNext = false
        Int i = 0
        while i < self.raw.length() {
            String arg = self.raw.get(i)
            if skipNext {
                skipNext = false
            } else if isOption(arg) {
                if arg.indexOf("=") < 0 {
                    skipNext = true
                }
            } else {
                res.push(arg)
            }
            i = i + 1
        }
        return res
    }
}

String usage(String program, String summary) {
    return "usage: " + program + " " + summary
}

Int exitCodeFor(String outcome) {
    if outcome == "ok" {
        return 0
    }
    if outcome == "usage" {
        return 2
    }
    return 1
}
