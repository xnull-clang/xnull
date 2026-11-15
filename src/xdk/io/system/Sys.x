// Tier: T0；依赖：xdk.runtime、xdk.errors；稳定性：preview。
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

static Error sysError(ErrorKind kind, String message) {
    BasicError be = new BasicError(kind, message)
    return be
}

static ErrorKind resourceKind(Int code) {
    if code == 1 {
        return ErrorKind.NotFound
    }
    if code == 2 {
        return ErrorKind.InvalidArgument
    }
    if code == 3 {
        return ErrorKind.DataCorrupted
    }
    return ErrorKind.Io
}

// ---------- 字节/hex ----------

static String hexChar(Int v) {
    String table = "0123456789abcdef"
    return table.substring(v, 1)
}

static String hexEncode(Bytes b) {
    // 逐字节拼接（编译器暂无 StringBuilder/List.join 发射面）；大文件写入
    // 受此实现限制，首版以 1 MiB 为上限，超过返回 Unsupported。
    String res = ""
    Int i = 0
    while i < b.length() {
        Int v = b.get(i)
        res = $"{res}{hexChar(v / 16)}{hexChar(v % 16)}"
        i = i + 1
    }
    return res
}

static Int lastIndexOfChar(String s, String ch) {
    Int i = 0
    Int last = -1
    while i < s.length() {
        if s.substring(i, 1) == ch {
            last = i
        }
        i = i + 1
    }
    return last
}

static Int hexValueAt(String text, Int i) {
    String ch = text.substring(i, 1)
    if ch == "0" { return 0 }
    if ch == "1" { return 1 }
    if ch == "2" { return 2 }
    if ch == "3" { return 3 }
    if ch == "4" { return 4 }
    if ch == "5" { return 5 }
    if ch == "6" { return 6 }
    if ch == "7" { return 7 }
    if ch == "8" { return 8 }
    if ch == "9" { return 9 }
    if ch == "a" { return 10 }
    if ch == "b" { return 11 }
    if ch == "c" { return 12 }
    if ch == "d" { return 13 }
    if ch == "e" { return 14 }
    if ch == "f" { return 15 }
    return 0
}

static Bytes hexDecode(String hex) {
    Bytes res = Bytes.fromString("")
    Int i = 0
    while i + 1 < hex.length() {
        Int hi = hexValueAt(hex, i)
        Int lo = hexValueAt(hex, i + 1)
        res.push(hi * 16 + lo)
        i = i + 2
    }
    return res
}

// ---------- File ----------

                                               
            
                     
           
                 
               

                            
                     
                    
                         
                          
     

                   
                          
     

                       
                            
     

                    
                       
     

                                     
                                          
                       
                                                                              
         
                         
                   
     

                                     
                               
                            
                              
                  
                                                                                    
         
                    
     

                    
                                    
                         
                                                                              
         
                            
                                  
                                                                                        
         
                                                
                                     
                                              
                            
         
                                                     
                               
                      
     

                            
                                             
                         
                                                                                     
         
                         
                                                                           
         
                            
                                  
                                                                                     
         
                                                
                                     
                                              
                            
         
                                       
                         
                        
         
                              
                                            
                      
                      
     

                                
                                      
                         
                                                                               
         
                                                 
                       
     

                       
                                          
                         
                                                                            
         
                           
                                                                                  
         
                                    
                                                                                      
         
                            
                                                          
                    
                                                                               
         
                                
     

                    
                                               
                         
                                                                                
         
                           
                                                                                      
         
                            
                                           
                    
                                                                                   
         
                                
     

            
                                               
                                          
     

                                 
                                 
                           
                   
     
 

// openFileRead：只读打开；文件不存在 → NotFound。
Result<File, Error> openFileRead(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openFileRead: 路径为空"))
    }
    if fileExistsRaw(path) == 0 {
        return Err(sysError(ErrorKind.NotFound, $"openFileRead: 文件不存在 {path}"))
    }
    return Ok(new File(path, false))
}

// openFileWrite：写模式（立即截断）。
Result<File, Error> openFileWrite(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openFileWrite: 路径为空"))
    }
    Int rc = writeFileTextRaw(path, "")
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"openFileWrite: 无法创建 {path}"))
    }
    return Ok(new File(path, true))
}

// openFileAppend：追加模式（不截断）。
Result<File, Error> openFileAppend(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openFileAppend: 路径为空"))
    }
    return Ok(new File(path, true))
}

// ---------- 文件系统操作 ----------

Bool fileExists(String path) {
    if path.length() == 0 {
        return false
    }
    return fileExistsRaw(path) != 0
}

Result<Unit, Error> removeFile(String path) {
    if fileExistsRaw(path) == 0 {
        return Err(sysError(ErrorKind.NotFound, $"removeFile: 文件不存在 {path}"))
    }
    Int rc = fileRemoveRaw(path)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"removeFile: 删除失败 {path}"))
    }
    return Ok()
}

Result<Unit, Error> renameFile(String from, String to) {
    if from.length() == 0 || to.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "renameFile: 路径为空"))
    }
    Int rc = fileRenameRaw(from, to)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"renameFile: {from} -> {to} 失败"))
    }
    return Ok()
}

// copyFile：整文件复制（二进制安全）；覆盖目标。
Result<Unit, Error> copyFile(String from, String to) {
    if fileExistsRaw(from) == 0 {
        return Err(sysError(ErrorKind.NotFound, $"copyFile: 源不存在 {from}"))
    }
    String hex = readFileHexRaw(from)
    Int rc = writeFileHexRaw(to, hex, false)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"copyFile: 无法写入 {to}"))
    }
    return Ok()
}

Result<Unit, Error> makeDir(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "makeDir: 路径为空"))
    }
    Int rc = dirMakeRaw(path)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"makeDir: 无法创建 {path}"))
    }
    return Ok()
}

Result<Unit, Error> removeDir(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "removeDir: 路径为空"))
    }
    Int rc = dirRemoveRaw(path)
    if rc != 0 {
        return Err(sysError(ErrorKind.Io, $"removeDir: 无法删除 {path}"))
    }
    return Ok()
}

// ---------- Path ----------

                            
            
                    

                    
                    
     

                       
                       
     

                       
                                                                       
     

                           
                   
                           
                                                                       
                                              
         
                                       
                  
                    
         
                                                     
     

                        
                     
                           
                                                                       
                                              
         
                                       
                   
                       
                          
             
                      
         
                                
     

                         
                  
                              
                                       
                   
                     
         
                                                     
     
 

// pathJoin：连接两段路径，处理重复分隔符。
String pathJoin(String a, String b) {
    if a.length() == 0 {
        return b
    }
    if b.length() == 0 {
        return a
    }
    if a.substring(a.length() - 1, 1) == "/" {
        return $"{a}{b}"
    }
    return $"{a}/{b}"
}

// ---------- Dir ----------

                                               
           
          
               

                
                   
                          
     

                   
                          
     

                              
                   
                         
                     
         
                       
                              
     

                                     
                                           
                         
                                                                             
         
                             
                                 
                                 
                          
                              
         
                      
     

                                 
                         
                       
         
                           
                       
                                 
                    
                                                                 
         
                   
     
 

Result<Dir, Error> openDir(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "openDir: 路径为空"))
    }
    Int id = dirOpenIdRaw(path)
    if id == 0 {
        return Err(sysError(ErrorKind.NotFound, $"openDir: 无法打开 {path}"))
    }
    return Ok(new Dir(id))
}

// ---------- Process ----------

                                                        
               
                
               

                      
                       
                          
     

                   
                          
     

                                            
                               
                         
                                                                              
         
                             
                                 
                   
                                                                    
         
                     
     

                                       
                         
                                                                              
         
                             
                                    
                    
                                                                      
         
                   
     

                                 
                         
                       
         
                           
                             
                                
                    
                                                                     
         
                   
     
 

Result<Process, Error> spawnProcess(String command) {
    if command.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "spawnProcess: 命令为空"))
    }
    Int64 h = procSpawnRaw(command)
    if h == 0 {
        return Err(sysError(ErrorKind.Io, "spawnProcess: 无法启动子进程"))
    }
    return Ok(new Process(h))
}

// runProcess：便捷同步形态，运行 shell 命令并返回退出码。
Int runProcess(String command) {
    Int64 code = procExitCodeRaw(command)
    return code
}

                          
                     
            
                 

                                    
                     
                       
     

                  
                        
     

                     
                          
     
 

// runProcessResult：运行命令并捕获 stdout（stderr 不捕获）。
Result<ProcessResult, Error> runProcessResult(String command) {
    if command.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "runProcessResult: 命令为空"))
    }
    String text = procOutputRaw(command)
    Int code = procLastStatusRaw()
    if code < 0 {
        return Err(sysError(ErrorKind.Io, "runProcessResult: 无法执行命令"))
    }
    return Ok(new ProcessResult(code, text))
}

// ---------- 旧兼容入口（K-07：编译器读源文件） ----------

// readFileTextImpl：读取失败（缺失/IO/超过 64 MiB）→ throw 明确诊断，不返回空串。
// 与 readFileText 分开命名：产品编译器对 readFileText 有 K-07 专用发射（调用点丢参）。
String readFileTextImpl(String path) {
    String raw = readFileTextRaw(path)
    if readFileTextError() != 0 {
        throw $"readFileText: 无法读取文件 {path}"
    }
    return raw
}

// readFileText：K-07 兼容入口（编译器 --ast-file/--bundle-file 使用）。
String readFileText(String path) {
    return readFileTextImpl(path)
}

// 兼容聚合构建工具使用的 sys 面。
Bool pathExists(String path) {
    return fileExists(path)
}

Int32 writeFileText(String path, String text) {
    return writeFileTextRaw(path, text)
}

Int32 procStatus(String command) {
    return runProcess(command)
}

// ---------- 系统信息与环境（ext_raw 桥）----------

String env(String name) {
    return envRaw(name)
}

Bool envHas(String name) {
    return envHasRaw(name) != 0
}

String hostname() {
    return hostnameRaw()
}

String platform() {
    return platformRaw()
}

String arch() {
    return archRaw()
}

Int pid() {
    return pidRaw()
}

String cwd() {
    return cwdRaw()
}

Bool chdir(String path) {
    return chdirRaw(path) != 0
}

Int fileMtime(String path) {
    return fileMtimeRaw(path)
}

// 读取一行 stdin（EOF 返回空串）；v1 阻塞。
String stdinReadLine() {
    return stdinLineRaw()
}

// ---------- 目录遍历 ----------

Bool dirExists(String path) {
    // 无 stat 原语：openDir 成功即目录（文件句柄打开失败）。
    Result<Dir, Error> d = openDir(path)
    if d.isErr() {
        return false
    }
    Result<Unit, Error> c = d.value().close()
    return c.isOk()
}

Bool isDir(String path) {
    return dirExists(path)
}

// 递归收集 root 下的全部文件路径（深度优先；"." 与 ".." 跳过）。
Result<List<String>, Error> walk(String root) {
    List<String> res = []
    Result<Dir, Error> d = openDir(root)
    if d.isErr() {
        Error derr = d.error()
        return Err(derr)
    }
    Dir dir = d.value()
    String name = dir.next()
    while name.length() > 0 {
        if name != "." && name != ".." {
            String child = root + "/" + name
            if dirExists(child) {
                Result<List<String>, Error> sub = walk(child)
                if sub.isErr() {
                    Error serr = sub.error()
                    Result<Unit, Error> cl = dir.close()
                    return Err(serr)
                }
                Int i = 0
                while i < sub.value().length() {
                    res.push(sub.value().get(i))
                    i = i + 1
                }
            } else {
                res.push(child)
            }
        }
        name = dir.next()
    }
    Result<Unit, Error> closed = dir.close()
    if closed.isErr() {
        Error cerr = closed.error()
        return Err(cerr)
    }
    return Ok(res)
}

// 多级建目录（逐级 mkdir，已存在视为成功）。
Result<Unit, Error> mkdirAll(String path) {
    if path.length() == 0 {
        return Err(sysError(ErrorKind.InvalidArgument, "mkdirAll: 空路径"))
    }
    Int i = 0
    while i < path.length() {
        if path.substring(i, 1) == "/" && i > 0 {
            String prefix = path.substring(0, i)
            Result<Unit, Error> made = makeDir(prefix)
            if made.isErr() && !dirExists(prefix) {
                Error merr = made.error()
                return Err(merr)
            }
        }
        i = i + 1
    }
    Result<Unit, Error> made2 = makeDir(path)
    if made2.isErr() && !dirExists(path) {
        Error merr2 = made2.error()
        return Err(merr2)
    }
    return Ok()
}
