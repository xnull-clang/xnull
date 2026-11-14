// xdk.net —— S6-09 源码单元（socket plain/Async + xdk.net.http 入口）
//
// 依赖矩阵（S6 §2）：net → errors, tasks, sync；不反向依赖 sys/collections。
// 运行时服务：handle（socket/Listener 句柄）、scheduler（*Async 挂起）。
// 跨 FFI 边界：-（rt_std_net.c / net.xfb 由 E4/E5 接入；本单元先冻结语言面）。
// 稳定性：@preview
//
// 合同（S6 §3/§4.7、XDK-09）：
//   - 可失败操作一律返回 Result；不使用 panic 表达可恢复失败。
//   - 资源类型 Socket/Listener 必须提供 close()；close 幂等，不以 deinit 作为唯一关闭路径。
//   - 默认异步形态 `*Async` 首参 Context；plain 形态无后缀并声明为阻塞。
//   - net.http 是 `xdk.net` 的子包入口（S1 §3.2 多级包），符号由本单元导出。
//
// 边界：OS socket 原语尚未链接。地址/URL 校验是真实行为；需要内核的
// connect/bind/accept/read/write 与 HTTP 传输在运行时接入前返回
// ErrorKind.Unsupported，避免静默给出假成功。
package xdk.net
import xdk.errors
import xdk.tasks

// ---------- 内部错误构造 ----------

// NetError：本单元自带的 Error 实现，避免依赖错误包的非公开构造器。





































// Socket：plain/Async 双形态；close 幂等。
class Socket {
    final String host;
    final Int port;
    Bool _closed = false

    Socket(String host, Int port) {
        self.host = host
        self.port = port
    }

    // plain 形态：显式阻塞，无 Context（S6 §4.7 定案 3-g-2）。
    Result<Socket, Error> connect(String host, Int port) {
        if !isValidAddress(host, port) {
            return Err(netErr(ErrorKind.InvalidArgument, "connect: 非法 host/port"))
        }
        if _closed {
            return Err(netErr(ErrorKind.Unavailable, "connect: socket 已关闭"))
        }
        return Err(netErr(ErrorKind.Unsupported, "connect: socket 运行时未链接"))
    }

    // 默认异步形态：首参 Context。
    Result<Socket, Error> connectAsync(Context context, String host, Int port) {
        return self.connect(host, port)
    }

    Result<Int, Error> read(Bytes buffer) {
        if _closed {
            return Err(netErr(ErrorKind.Unavailable, "read: socket 已关闭"))
        }
        if buffer.length() == 0 {
            return Ok(0)
        }
        return Err(netErr(ErrorKind.Unsupported, "read: socket 运行时未链接"))
    }

    Result<Int, Error> readAsync(Context context, Bytes buffer) {
        return self.read(buffer)
    }

    Result<Int, Error> write(Bytes buffer) {
        if _closed {
            return Err(netErr(ErrorKind.Unavailable, "write: socket 已关闭"))
        }
        return Err(netErr(ErrorKind.Unsupported, "write: socket 运行时未链接"))
    }

    Result<Int, Error> writeAsync(Context context, Bytes buffer) {
        return self.write(buffer)
    }

    // close 幂等：重复关闭仍返回成功。
    Result<void, Error> close() {
        _closed = true
        return Ok()
    }
}
