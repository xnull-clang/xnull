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

































































































































class Logger {
    Int level
    String name

    Logger(String name0) {
        self.level = logLevelInfo()
        self.name = name0
    }

    Logger setLevel(Int lvl) {
        self.level = lvl
        return self
    }

    // withField v1：以 key=value 追加到前缀（无结构化输出）。
    Logger withField(String k, String v) {
        Logger out = new Logger(self.name + " " + k + "=" + v)
        out.level = self.level
        return out
    }

    String render(Int lvl, String msg) {
        String tag = "INFO"
        if lvl == 0 {
            tag = "DEBUG"
        } else if lvl == 2 {
            tag = "WARN"
        } else if lvl == 3 {
            tag = "ERROR"
        }
        return "[" + tag + "] " + self.name + ": " + msg
    }

    void debug(String msg) {
        if self.level <= 0 {
            print(self.render(0, msg))
        }
    }

    void info(String msg) {
        if self.level <= 1 {
            print(self.render(1, msg))
        }
    }

    void warn(String msg) {
        if self.level <= 2 {
            print(self.render(2, msg))
        }
    }

    void error(String msg) {
        if self.level <= 3 {
            print(self.render(3, msg))
        }
    }
}
