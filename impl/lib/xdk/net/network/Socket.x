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
















































































// Socket：客户端连接句柄。send/recv 为文本形态；close 幂等。
class Socket {
    Int64 handle
    Bool opened

    Socket(Int64 h) {
        self.handle = h
        self.opened = true
    }

    Bool isOpen() {
        return self.opened
    }

    // 发送文本；返回发送字节数。
    Result<Int, Error> send(String data) {
        if !self.opened {
            return Err(netError(ErrorKind.Unavailable, "Socket.send: socket 已关闭"))
        }
        Int64 n = socketSendRaw(self.handle, data)
        if n < 0 {
            return Err(netError(netKind(socketErrorRaw()), "Socket.send: 发送失败"))
        }
        return Ok(n)
    }

    // 发送二进制（首版上限 1 MiB）。
    Result<Int, Error> sendBytes(Bytes data) {
        if !self.opened {
            return Err(netError(ErrorKind.Unavailable, "Socket.sendBytes: socket 已关闭"))
        }
        if data.length() > 1048576 {
            return Err(netError(ErrorKind.Unsupported, "Socket.sendBytes: 首版上限 1 MiB"))
        }
        Int64 n = socketSendHexRaw(self.handle, netHexEncode(data))
        if n < 0 {
            return Err(netError(netKind(socketErrorRaw()), "Socket.sendBytes: 发送失败"))
        }
        return Ok(n)
    }

    // 接收至多 maxBytes 字节并返回二进制；对端关闭 → 空缓冲。
    Result<Bytes, Error> recvBytes(Int maxBytes) {
        if !self.opened {
            return Err(netError(ErrorKind.Unavailable, "Socket.recvBytes: socket 已关闭"))
        }
        String hex = socketRecvHexRaw(self.handle, maxBytes)
        Int code = socketErrorRaw()
        if code != 0 {
            return Err(netError(netKind(code), "Socket.recvBytes: 接收失败"))
        }
        Bytes res = netHexDecode(hex)
        return Ok(res)
    }

    // 接收至多 maxBytes 字节并返回文本；对端关闭 → 空串。
    Result<String, Error> recv(Int maxBytes) {
        if !self.opened {
            return Err(netError(ErrorKind.Unavailable, "Socket.recv: socket 已关闭"))
        }
        String data = socketRecvRaw(self.handle, maxBytes)
        Int code = socketErrorRaw()
        if code != 0 {
            return Err(netError(netKind(code), "Socket.recv: 接收失败"))
        }
        return Ok(data)
    }

    // close 幂等；句柄立即失效。
    Result<void, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Int rc = socketCloseRaw(self.handle)
        if rc != 0 {
            return Err(netError(ErrorKind.Io, "Socket.close: 关闭失败"))
        }
        return Ok()
    }
}
