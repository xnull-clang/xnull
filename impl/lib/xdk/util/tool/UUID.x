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































































class UUID {
    String hex    // 归一化：小写无连字符 32 位

    UUID(String normalized) {
        self.hex = normalized
    }

    String str() {
        String h = self.hex
        if h.length() != 32 {
            return h
        }
        return h.substring(0, 8) + "-" + h.substring(8, 4) + "-" + h.substring(12, 4) +
            "-" + h.substring(16, 4) + "-" + h.substring(20, 12)
    }

    Bytes bytes() {
        return hexDecode(self.hex)
    }

    Bool isNil() {
        if self.hex.length() != 32 {
            return false
        }
        Int i = 0
        while i < 32 {
            if self.hex.get(i) != 48 {
                return false
            }
            i = i + 1
        }
        return true
    }
}
