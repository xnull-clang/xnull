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
















































































































































































































































class Args {
    List<String> names
    List<String> values
    List<String> positionals

    Args() {
        self.names = []
        self.values = []
        self.positionals = []
    }

    void put(String name, String value) {
        Int i = 0
        while i < self.names.length() {
            if self.names.get(i) == name {
                self.values.set(i, value)
                return
            }
            i = i + 1
        }
        self.names.push(name)
        self.values.push(value)
    }

    Bool flag(String name) {
        Int i = 0
        while i < self.names.length() {
            if self.names.get(i) == name {
                return self.values.get(i) == "true"
            }
            i = i + 1
        }
        return false
    }

    String option(String name) {
        Int i = 0
        while i < self.names.length() {
            if self.names.get(i) == name {
                return self.values.get(i)
            }
            i = i + 1
        }
        return ""
    }

    String positional(Int idx) {
        if idx < 0 || idx >= self.positionals.length() {
            return ""
        }
        return self.positionals.get(idx)
    }

    Int positionalCount() {
        return self.positionals.length()
    }
}
