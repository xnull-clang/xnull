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

                                                  
                                 
                              
                         

                                              
                             
                              
     

                                              

                                             
 

static Error netErr(ErrorKind kind, String message) {
    return new NetError(kind, message)
}

static Bool isValidAddress(String host, Int port) {
    if host.length() == 0 {
        return false
    }
    return port > 0 && port <= 65535
}

static Bool isHttpUrl(String url) {
    if url.length() > 7 && url.substring(0, 7) == "http://" {
        return true
    }
    if url.length() > 8 && url.substring(0, 8) == "https://" {
        return true
    }
    return false
}

// ---------- Socket（客户端句柄） ----------

                                   
              
                      
                   
                        

                                   
                        
                        
     

                                                 
                                                          
                                        
                                                                                  
         
                    
                                                                            
         
                                                                           
     

                         
                                                                                
                                       
     

                                           
                    
                                                                         
         
                                 
                        
         
                                                                        
     

                                                                 
                                
     

                                            
                    
                                                                          
         
                                                                         
     

                                                                  
                                 
     

                          
                                 
                      
                   
     
 

// ---------- Listener（服务端句柄） ----------

                
                      
                   
                        

                                     
                        
                        
     

                                                         
                                        
                                                                               
         
                    
                                                                           
         
                                                                        
     

                                                                               
                                    
     

                                    
                    
                                                                             
         
                                                                          
     

                                                        
                            
     

                                 
                      
                   
     
 

// ---------- 顶层 plain/Async 入口 ----------

// connect：阻塞形态；成功返回已连接句柄，失败为可恢复错误。
Result<Socket, Error> connect(String host, Int port) {
    if !isValidAddress(host, port) {
        return Err(netErr(ErrorKind.InvalidArgument, "connect: 非法 host/port"))
    }
    return Err(netErr(ErrorKind.Unsupported, "connect: socket 运行时未链接"))
}

Result<Socket, Error> connectAsync(Context context, String host, Int port) {
    return connect(host, port)
}

// bind：阻塞形态；返回监听句柄。
Result<Listener, Error> bind(String host, Int port) {
    if !isValidAddress(host, port) {
        return Err(netErr(ErrorKind.InvalidArgument, "bind: 非法 host/port"))
    }
    return Err(netErr(ErrorKind.Unsupported, "bind: socket 运行时未链接"))
}

Result<Listener, Error> bindAsync(Context context, String host, Int port) {
    return bind(host, port)
}

// ---------- xdk.net.http 子包入口 ----------

                                
               
                        
                     
                                      
                     

                                                                                 
                            
                      
                              
                        
     
 

                                         
                
                   
                        
                                      

                                                                    
                        
                              
                              
     

                                     

                                        

                                                                 
 

Result<Response, Error> get(String url) {
    if !isHttpUrl(url) {
        return Err(netErr(ErrorKind.InvalidArgument, "get: 仅支持 http/https URL"))
    }
    return Err(netErr(ErrorKind.Unsupported, "get: HTTP 传输未链接"))
}

Result<Response, Error> post(String url, Bytes body) {
    if !isHttpUrl(url) {
        return Err(netErr(ErrorKind.InvalidArgument, "post: 仅支持 http/https URL"))
    }
    return Err(netErr(ErrorKind.Unsupported, "post: HTTP 传输未链接"))
}

Result<Response, Error> getAsync(Context context, String url) {
    return get(url)
}

Result<Response, Error> postAsync(Context context, String url, Bytes body) {
    return post(url, body)
}
