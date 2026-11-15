// xdk.sys 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 与 src/xdk/io/base/Sys.x（编译器/默认构建使用的精简面）保持同包语义；默认构建
// 不加载本单元，避免改变冻结 golden。资源 API 见 io/resource/Resource.x。
//
// 依赖矩阵（S6 §2）：sys → errors；运行时服务：handle、ffi-contract。
// 稳定性：@preview。
//
// 实现口径（当前编译器 之前的编译面约束）：
//   - File 为**直接落盘**模型：write 立即写，不缓冲；二进制经 hex 桥传输，
//     文本经 append 原语传输；read 每次按 offset 重新读取。
//   - Dir 用运行时句柄表索引迭代；顺序依文件系统，不排序。
//   - 资源读取按 S6 §4.8：合法路径/只读/不回退 FS/缺失 NotFound。
//   - Context 首参为 S6 §3 惯例；单线程运行时无挂起点，取消面随调度器切片补齐。
//   - 当前产品编译器不支持类静态方法调用，工厂以顶层函数提供：
//     openFileRead/openFileWrite/openFileAppend/openDir/spawnProcess。
package xdk.sys
import xdk.errors

// ---------- 错误映射 ----------











































































































































































































































































































































// Path：路径字符串的轻量视图（不访问文件系统）。
class Path {
    final String raw

    Path(String p) {
        self.raw = p
    }

    String toString() {
        return self.raw
    }

    Bool isAbsolute() {
        return self.raw.length() > 0 && self.raw.substring(0, 1) == "/"
    }

    // 最后一段；以 / 结尾时去掉尾部分隔符。
    String name() {
        String s = self.raw
        while s.length() > 1 && s.substring(s.length() - 1, 1) == "/" {
            s = s.substring(0, s.length() - 1)
        }
        Int i = lastIndexOfChar(s, "/")
        if i < 0 {
            return s
        }
        return s.substring(i + 1, s.length() - i - 1)
    }

    // 父目录（无分隔符时返回 "."）。
    String parent() {
        String s = self.raw
        while s.length() > 1 && s.substring(s.length() - 1, 1) == "/" {
            s = s.substring(0, s.length() - 1)
        }
        Int i = lastIndexOfChar(s, "/")
        if i <= 0 {
            if i == 0 {
                return "/"
            }
            return "."
        }
        return s.substring(0, i)
    }

    // 扩展名（不含点）；无扩展名返回空串。
    String ext() {
        String n = self.name()
        Int i = lastIndexOfChar(n, ".")
        if i <= 0 {
            return ""
        }
        return n.substring(i + 1, n.length() - i - 1)
    }
}
