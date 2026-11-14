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

Bytes sha256(Bytes b) {
    return hexDecode(sha256HexRaw(hexEncode(b)))
}

Bytes sha1(Bytes b) {
    return hexDecode(sha1HexRaw(hexEncode(b)))
}

Bytes md5(Bytes b) {
    return hexDecode(md5HexRaw(hexEncode(b)))
}

Bytes sha512(Bytes b) {
    return hexDecode(sha512HexRaw(hexEncode(b)))
}

String sha256Hex(Bytes b) {
    return sha256HexRaw(hexEncode(b))
}

Int crc32(Bytes b) {
    return crc32HexRaw(hexEncode(b))
}

Bytes hmacSha256(Bytes key, Bytes data) {
    return hexDecode(hmacSha256HexRaw(hexEncode(key), hexEncode(data)))
}

// 常量时间比较（长度相同逐字节异或累积；长度不同立即失败）。
Bool constantTimeEquals(Bytes a, Bytes b) {
    if a.length() != b.length() {
        return false
    }
    Int diff = 0
    Int i = 0
    while i < a.length() {
        diff = diff | (a.get(i) ^ b.get(i))
        i = i + 1
    }
    return diff == 0
}

// ---------- 压缩 ----------

Result<Bytes, Error> gzipCompress(Bytes b) {
    String out = gzipCompressHexRaw(hexEncode(b))
    if out.length() == 0 {
        return Err(sysError(ErrorKind.Internal, "gzipCompress: 压缩失败"))
    }
    return Ok(hexDecode(out))
}

Result<Bytes, Error> gzipDecompress(Bytes b) {
    String out = gzipDecompressHexRaw(hexEncode(b))
    if out.length() == 0 {
        return Err(sysError(ErrorKind.DataCorrupted, "gzipDecompress: 数据非法"))
    }
    return Ok(hexDecode(out))
}

// ---------- UUID ----------

            
                                    

                             
                             
     

                  
                           
                             
                    
         
                                                                                       
                                                                
     

                   
                                  
     

                  
                                    
                        
         
                 
                      
                                      
                            
             
                     
         
                   
     
 

String uuid4() {
    return uuid4Raw()
}

Result<UUID, Error> uuidParse(String s) {
    String t = s.trim().toLower()
    // 去连字符
    String hex = t.replace("-", "")
    if hex.length() != 32 {
        return Err(sysError(ErrorKind.InvalidArgument, "uuidParse: 长度非法"))
    }
    Int i = 0
    while i < 32 {
        Int b = hex.get(i)
        Bool digit = b >= 48 && b <= 57
        Bool alpha = (b >= 97 && b <= 102)
        if !digit && !alpha {
            return Err(sysError(ErrorKind.InvalidArgument, "uuidParse: 非法字符"))
        }
        i = i + 1
    }
    return Ok(new UUID(hex))
}

// ---------- 日志 ----------

Int logLevelDebug() { return 0 }
Int logLevelInfo()  { return 1 }
Int logLevelWarn()  { return 2 }
Int logLevelError() { return 3 }

              
             
               

                          
                                   
                         
     

                              
                        
                   
     

                                              
                                          
                                                              
                              
                  
     

                                        
                           
                     
                         
                            
                        
                            
                         
         
                                                        
     

                            
                            
                                      
         
     

                           
                            
                                      
         
     

                           
                            
                                      
         
     

                            
                            
                                      
         
     
 

// ---------- 断言与测试 ----------

void fail(String msg) {
    print("FAIL: " + msg)
    exit(1)
}

void assertTrue(Bool cond, String msg) {
    if !cond {
        fail(msg)
    }
}

void assertFalse(Bool cond, String msg) {
    if cond {
        fail(msg)
    }
}

void assertEqInt(Int a, Int b, String msg) {
    if a != b {
        fail(msg + "（" + str(a) + " != " + str(b) + "）")
    }
}

void assertEqStr(String a, String b, String msg) {
    if a != b {
        fail(msg + "（\"" + a + "\" != \"" + b + "\"）")
    }
}

void assertEqBytes(Bytes a, Bytes b, String msg) {
    if !constantTimeEquals(a, b) {
        fail(msg)
    }
}

Bool approxEq(Double a, Double b, Double eps) {
    Double d = a - b
    if d < 0.0 {
        d = -d
    }
    return d <= eps
}

void assertApproxEq(Double a, Double b, Double eps, String msg) {
    if !approxEq(a, b, eps) {
        fail(msg)
    }
}

// ---------- 命令行参数解析 ----------

            
                      
                       
                            

            
                       
                        
                             
     

                                         
                 
                                       
                                          
                                         
                      
             
                     
         
                             
                               
     

                            
                 
                                       
                                          
                                                   
             
                     
         
                    
     

                                
                 
                                       
                                          
                                         
             
                     
         
                 
     

                                
                                                        
                     
         
                                        
     

                           
                                        
     
 

                  
                          
                            
                       

                  
                           
                             
                                
     

                            
                                 
     

                              
                                   
     

                                  
                                                       
     

                                                  
                             
                 
                                 
                                  
                                                            
                                                            
                                          
                                  
                                 
                            
                                                
                                                                          
                 
                                                          
                                                           
                                      
                                                                                          
                 
                           
                                
                                            
                            
                                             
                     
                        
                                
                                            
                            
                                                   
                                                                                                      
                         
                                 
                                                  
                     
                 
                    
                                       
             
                     
         
                                                            
                                                                            
         
                      
     

                   
                               
                 
                                           
                                                             
                     
         
             
                                             
                                                                       
                     
         
                 
                                        
                                                 
                     
         
                  
     
 

Bool inList(List<String> xs, String v) {
    Int i = 0
    while i < xs.length() {
        if xs.get(i) == v {
            return true
        }
        i = i + 1
    }
    return false
}
