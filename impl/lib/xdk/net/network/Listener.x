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
















































































































































































class Listener {
    final String host
    final Int port
    Int64 handle
    Bool opened

    Listener(String h, Int p, Int64 handle) {
        self.host = h
        self.port = p
        self.handle = handle
        self.opened = true
    }

    Bool isOpen() {
        return self.opened
    }

    Result<void, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Int rc = socketCloseRaw(self.handle)
        self.handle = 0
        if rc != 0 {
            return Err(netError(ErrorKind.Io, "Listener.close: 关闭失败"))
        }
        return Ok()
    }

    Result<Socket, Error> accept() {
        if !self.opened {
            return Err(netError(ErrorKind.Unavailable, "Listener.accept: listener 已关闭"))
        }
        Int64 handle = listenerAcceptRaw(self.handle)
        if handle == 0 {
            return Err(netError(netKind(socketErrorRaw()), "Listener.accept: 接受连接失败"))
        }
        return Ok(new Socket(handle))
    }
}
