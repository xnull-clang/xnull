// xdk.sys 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 与 impl/lib/xdk/io/base/Sys.x（编译器/默认构建使用的精简面）保持同包语义；默认构建
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



















































































































































































































































































































































































































// Dir：目录迭代。next() 返回空串表示结束；entries() 消费剩余全部条目。
class Dir {
    Int id
    Bool opened

    Dir(Int i) {
        self.id = i
        self.opened = true
    }

    Bool isOpen() {
        return self.opened
    }

    // 下一个条目；结束返回空串（文件名不可能为空）。
    String next() {
        if !self.opened {
            return ""
        }
        Int d = self.id
        return dirNextIdRaw(d)
    }

    // 读取剩余全部条目（含 "." 与 ".."，与运行时一致）。
    Result<List<String>, Error> entries() {
        if !self.opened {
            return Err(sysError(ErrorKind.Unavailable, "Dir.entries: 目录未打开"))
        }
        List<String> res = []
        String name = self.next()
        while name.length() > 0 {
            res.push(name)
            name = self.next()
        }
        return Ok(res)
    }

    Result<void, Error> close() {
        if !self.opened {
            return Ok()
        }
        self.opened = false
        Int d = self.id
        Int rc = dirCloseIdRaw(d)
        if rc != 0 {
            return Err(sysError(ErrorKind.Io, "Dir.close: 关闭失败"))
        }
        return Ok()
    }
}
