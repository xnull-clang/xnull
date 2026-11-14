// xdk.net 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 默认构建继续使用 impl/lib/xdk/net/base/Net.x（S6 §4.7 声明面）。
//
// 依赖矩阵（S6 §2）：net → errors；不反向依赖 sys/collections。
// 运行时服务：handle（socket）、scheduler（*Async 挂起；首版随调度器切片）。
// 跨 FFI 边界：xdkc_net_raw（bindings/xdk/net_raw.xfb 的标量句柄桥）。
// 稳定性：@preview
//
// 合同（S6 §3/§4.7）：
//   - 可失败操作一律返回 Result；不使用 panic 表达可恢复失败。
//   - 资源类型 Socket/Listener 提供 close()；close 幂等。
//   - 首版为文本形态（产品编译器 Bytes 借出面待编译器修复）；二进制传输随 FFI 修复补齐。
//   - 类静态方法调用当前不可用（当前编译器），工厂以顶层函数提供：
//     connectSocket / httpGet / httpPost。
package xdk.net
import xdk.errors

// ---------- 错误映射 ----------



































































































































































































































































































































// Response：入站响应（状态码 + 文本体 + 头）。
class Response {
    Int code
    String payload
    List<String> headers

    Response(Int c, String p, List<String> h) {
        self.code = c
        self.payload = p
        self.headers = h
    }

    Int status() {
        return self.code
    }

    String body() {
        return self.payload
    }

    // 头以 `name: value` 行保存；未命中返回空串。
    String header(String name) {
        String prefix = $"{name}:"
        Int i = 0
        while i < self.headers.length() {
            String line = self.headers.get(i)
            if line.length() >= prefix.length() {
                if line.substring(0, prefix.length()) == prefix {
                    return line.substring(prefix.length(), line.length() - prefix.length())
                }
            }
            i = i + 1
        }
        return ""
    }
}
