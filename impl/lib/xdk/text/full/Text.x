// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 与 impl/lib/xdk/text.x（默认构建面）同源；追加顶层工厂与 Utf16 包装。
// 默认构建不加载本单元，避免改变冻结 golden。
//
// 依赖：xdk.errors（错误值）；C 原语对应 impl/runtime/rt_std_text.c
// （parse_int/parse_float/utf8_to_utf16/utf16_to_utf8/regex_match；解释器路径由等价源码执行）。
// 稳定性：@preview。
// 合同：可失败操作返回 Result；Regex 动态编译失败是可恢复错误，不 panic。
package xdk.text
import xdk.errors

// ---------- 格式化 builder ----------

                                                            
              
                      
                    
                   

                                              
                        
                          
                      
     

                              
                                         
     

                                   
                                           
     

                                    
                                    
     

                                
              
                                             
         
                                          
     

                         
                                                 
     

                        
                                                   
     

                    
                              
                                   
                                         
                            
         
                  
     
 

// 顶层工厂（当前产品编译器尚不支持类静态方法调用；`Format.int(...)` 由 编译器修复）。
Format formatInt(Int v) {
    return new Format(str(v), 0, ' ')
}

Format formatFloat(Double v) {
    return new Format($"{v}", 0, ' ')
}

Format formatString(String v) {
    return new Format(v, 0, ' ')
}

Format formatBool(Bool v) {
    if v {
        return new Format("true", 0, ' ')
    }
    return new Format("false", 0, ' ')
}

// ---------- 解析 ----------

static Int digitOf(String ch) {
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
    return -1
}

static Double digitOfD(String ch) {
    if ch == "0" { return 0.0 }
    if ch == "1" { return 1.0 }
    if ch == "2" { return 2.0 }
    if ch == "3" { return 3.0 }
    if ch == "4" { return 4.0 }
    if ch == "5" { return 5.0 }
    if ch == "6" { return 6.0 }
    if ch == "7" { return 7.0 }
    if ch == "8" { return 8.0 }
    if ch == "9" { return 9.0 }
    return -1.0
}

static Error textErr(String msg) {
    return new CauseError(ErrorKind.InvalidArgument, msg, null)
}

// parseInt：全串消费、十进制、可选正负号；溢出/非法返回 Err。
Result<Int, Error> parseInt(String s) {
    Int n = s.length()
    if n == 0 { return Err(textErr("parseInt: 空串")) }
    Int i = 0
    Bool neg = false
    if s.substring(0, 1) == "-" { neg = true; i = 1 }
    else if s.substring(0, 1) == "+" { i = 1 }
    if i >= n { return Err(textErr("parseInt: 缺少数字")) }
    Int v = 0
    Bool any = false
    while i < n {
        Int d = digitOf(s.substring(i, 1))
        if d < 0 { return Err(textErr("parseInt: 非法字符")) }
        any = true
        Int limit = 922337203685477580
        if v > limit { return Err(textErr("parseInt: 溢出")) }
        v = v * 10 + d
        if !neg && v < 0 { return Err(textErr("parseInt: 溢出")) }
        i = i + 1
    }
    if !any { return Err(textErr("parseInt: 缺少数字")) }
    if neg { return Ok(0 - v) }
    return Ok(v)
}

// parseFloat：十进制整数/小数/指数，全串消费；非法或溢出返回 Err。
Result<Double, Error> parseFloat(String s) {
    Int n = s.length()
    if n == 0 { return Err(textErr("parseFloat: 空串")) }
    Int i = 0
    Bool neg = false
    if s.substring(0, 1) == "-" { neg = true; i = 1 }
    else if s.substring(0, 1) == "+" { i = 1 }
    Double v = 0.0
    Bool any = false
    while i < n {
        String ch = s.substring(i, 1)
        if ch == "." { break }
        if ch == "e" || ch == "E" { break }
        Double d = digitOfD(ch)
        if d < 0.0 { return Err(textErr("parseFloat: 非法字符")) }
        v = v * 10.0 + d
        any = true
        i = i + 1
    }
    if i < n && s.substring(i, 1) == "." {
        i = i + 1
        Double scale = 0.1
        while i < n {
            String ch = s.substring(i, 1)
            if ch == "e" || ch == "E" { break }
            Double d = digitOfD(ch)
            if d < 0.0 { return Err(textErr("parseFloat: 非法小数")) }
            v = v + d * scale
            scale = scale * 0.1
            any = true
            i = i + 1
        }
    }
    if !any { return Err(textErr("parseFloat: 缺少数字")) }
    if i < n && (s.substring(i, 1) == "e" || s.substring(i, 1) == "E") {
        i = i + 1
        Bool eneg = false
        if i < n && s.substring(i, 1) == "-" { eneg = true; i = i + 1 }
        else if i < n && s.substring(i, 1) == "+" { i = i + 1 }
        if i >= n { return Err(textErr("parseFloat: 指数缺少数字")) }
        Int e = 0
        while i < n {
            Int d = digitOf(s.substring(i, 1))
            if d < 0 { return Err(textErr("parseFloat: 非法指数")) }
            e = e * 10 + d
            i = i + 1
        }
        Int k = 0
        while k < e {
            if eneg { v = v / 10.0 } else { v = v * 10.0 }
            k = k + 1
        }
    }
    if i != n { return Err(textErr("parseFloat: 未消费完整字符串")) }
    if neg { return Ok(0.0 - v) }
    return Ok(v)
}

// ---------- UTF-8 ↔ UTF-16 ----------

                                                        
             
                      

                            
                       
     

                  
                                  
     

                       
                                
     
 

// utf8ToUtf16：把 UTF-8 字节解码为 UTF-16 码元序列；非法序列返回 Err。
Result<Utf16, Error> utf8ToUtf16(Bytes b) {
    List<UInt16> res = []
    Int i = 0
    while i < b.length() {
        Int c = b.get(i)
        if c < 0x80 {
            res.push(c)
            i = i + 1
        } else if c >= 0xC0 && c < 0xE0 {
            if i + 1 >= b.length() { return Err(textErr("utf8ToUtf16: 截断的 2 字节序列")) }
            Int c2 = b.get(i + 1)
            if (c2 & 0xC0) != 0x80 { return Err(textErr("utf8ToUtf16: 非法续字节")) }
            res.push(((c & 0x1F) << 6) | (c2 & 0x3F))
            i = i + 2
        } else if c >= 0xE0 && c < 0xF0 {
            if i + 2 >= b.length() { return Err(textErr("utf8ToUtf16: 截断的 3 字节序列")) }
            Int c2 = b.get(i + 1)
            Int c3 = b.get(i + 2)
            if (c2 & 0xC0) != 0x80 || (c3 & 0xC0) != 0x80 { return Err(textErr("utf8ToUtf16: 非法续字节")) }
            res.push(((c & 0x0F) << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F))
            i = i + 3
        } else if c >= 0xF0 && c < 0xF8 {
            if i + 3 >= b.length() { return Err(textErr("utf8ToUtf16: 截断的 4 字节序列")) }
            Int c2 = b.get(i + 1)
            Int c3 = b.get(i + 2)
            Int c4 = b.get(i + 3)
            if (c2 & 0xC0) != 0x80 || (c3 & 0xC0) != 0x80 || (c4 & 0xC0) != 0x80 {
                return Err(textErr("utf8ToUtf16: 非法续字节"))
            }
            Int cp = ((c & 0x07) << 18) | ((c2 & 0x3F) << 12) | ((c3 & 0x3F) << 6) | (c4 & 0x3F)
            cp = cp - 0x10000
            res.push((0xD800 + (cp >> 10)) as Int)
            res.push((0xDC00 + (cp & 0x3FF)) as Int)
            i = i + 4
        } else {
            return Err(textErr("utf8ToUtf16: 不支持的 UTF-8 序列"))
        }
    }
    return Ok(new Utf16(res))
}

// utf16ToUtf8：把 UTF-16 码元编码为 UTF-8 字节；代理对按 BMP 外字符处理，孤立代理返回 Err。
Result<Bytes, Error> utf16ToUtf8(List<UInt16> xs) {
    Bytes res = Bytes.fromString("")
    Int i = 0
    while i < xs.length() {
        UInt16 u = xs.get(i)
        if u < 0x80 {
            res.push(u as Int)
            i = i + 1
        } else if u < 0x800 {
            res.push((0xC0 | (u >> 6)) as Int)
            res.push((0x80 | (u & 0x3F)) as Int)
            i = i + 1
        } else if u >= 0xD800 && u <= 0xDBFF {
            if i + 1 >= xs.length() { return Err(textErr("utf16ToUtf8: 孤立的高代理")) }
            UInt16 u2 = xs.get(i + 1)
            if u2 < 0xDC00 || u2 > 0xDFFF { return Err(textErr("utf16ToUtf8: 高代理后缺低代理")) }
            Int cp = 0x10000 + (((u as Int) - 0xD800) << 10) + ((u2 as Int) - 0xDC00)
            res.push((0xF0 | (cp >> 18)) as Int)
            res.push((0x80 | ((cp >> 12) & 0x3F)) as Int)
            res.push((0x80 | ((cp >> 6) & 0x3F)) as Int)
            res.push((0x80 | (cp & 0x3F)) as Int)
            i = i + 2
        } else if u >= 0xDC00 && u <= 0xDFFF {
            return Err(textErr("utf16ToUtf8: 孤立的低代理"))
        } else {
            res.push((0xE0 | (u >> 12)) as Int)
            res.push((0x80 | ((u >> 6) & 0x3F)) as Int)
            res.push((0x80 | (u & 0x3F)) as Int)
            i = i + 1
        }
    }
    return Ok(res)
}

// ---------- Regex（回溯引擎：字面量、.、* + ?、[] 类、分组捕获、| 、转义、^ $）----------
//
// AST 用扁平数组表示（避免自引用类）：seq/alt/group 的孩子为连续下标区间；
// 量词节点持单孩子与 min/max；类节点持区间/singles 与取反标志。
// 匹配器为递归回溯；分支失败时快照/恢复分组捕获栈。
// 约定：^/$ 为锚（字面量需转义）；{m,n} 量词与命名组暂不支持。

                 
                                                                                      
                    
                      
                      
                  
                  
                     
                
                
                     
                      
                      
                      

                 
                       
                     
                          
                          
                      
                      
                         
                    
                    
                         
                          
                          
                          
     

                                      
                             
                         
                             
                             
                         
                         
                            
                             
                             
                              
                                      
     
 

                    
                       
                    
                  
                  
                   

                       
                        
                      
                      
                       
     

                                 
                                                 
                                
                              
         
     

                     
                                           
                 
                                        
                                              
                                            
                     
         
     

                        
                                                          
                                                  
                                         
                                                    
         
                 
                                        
                                                           
                                                             
                     
         
     

                      
                                                  
                 
                                        
                                                    
                     
         
     
 

// 字节 → 单字节字符串（0..255）。
String stringOfByte(Int b) {
    Bytes buf = Bytes.fromString("")
    buf.push(b)
    return buf.toString()
}

// 类节点匹配单字节（ASCII 语义）。
Bool regexClassMatch(RegexTree t, Int ni, Int byte) {
    Int cs = t.clsStart.get(ni)
    Int cc = t.clsCount.get(ni)
    Bool hit = false
    Int i = 0
    while i < cc {
        Int j = cs + i
        Int single = t.singles.get(j)
        if single >= 0 {
            if single == byte {
                hit = true
            }
        } else {
            if byte >= t.lo.get(j) && byte <= t.hi.get(j) {
                hit = true
            }
        }
        i = i + 1
    }
    if t.negated.get(ni) == 1 {
        return !hit
    }
    return hit
}

                   
                  
           
               
                  
                 

                           
                        
                    
                                
                           
                             
     

                    
                                              
                     
         
                                         
     

                         
                                 
                                   
                       
         
                    
     

                           
                                 
                                
                                 
                                 
                                 
                               
                                                                            
                                                                    
                                                                  
                    
         
                 
     

                          
                                  
                                              
                                    
                              
                              
                                   
                          
                                           
             
                  
         
                                    
                              
                              
                                   
                              
                               
                                   
                              
                              
                                   
                                   
                          
                                           
             
                  
         
                                    
                                   
                                  
                                   
                                   
                                   
                                   
                          
                                           
             
                  
         
                                
     

                                    
                      
                                      
                                                        
                             
                                     
         
                         
                    
                                   
                      
                         
             
                                  
                                       
                     
             
                         
                       
                        
                                       
                                       
                          
                             
                 
                                       
                                                                                      
                                          
                            
                 
                                       
                    
                      
                                       
             
                       
                         
             
                                                                               
                                                      
                                       
                                        
                           
                             
                                           
                                            
                                           
                                            
                        
                           
                                           
                 
                            
                             
                 
                                  
                                  
                                       
                    
                                       
             
         
                                                                                  
                 
     

                                    
                               
                    
                                   
                                    
                                                 
                                                      
                              
                            
             
                                  
                                                          
             
                                          
                                                  
                                      
                                       
                         
         
                    
                                   
                                      
                       
                                                          
             
                         
         
                    
                                   
                                             
         
                    
                                   
                                   
                      
                                                         
             
                                   
                                                                                  
                                              
                                                                
                                      
                                                                                          
                             
             
                                      
                      
                                                         
             
                                                         
         
                                
                                                          
         
                                          
                                                       
         
                               
                    
                                             
         
                    
                                             
         
                                                     
     

                                          
                                                  
                         
                       
         
                             
                               
                    
                                   
                                         
                                      
                                     
                                 
                                          
                        
         
                    
                                   
                                         
                                      
                                     
                                 
                                          
                        
         
                    
                                   
                                         
                                      
                                     
                                 
                                 
                        
         
                     
     

                                      
                            
                                        
                                                          
                      
                                                           
                                             
                                             
                                                            
                     
                          
                              
                                                
                                                
                                                          
                         
             
                                       
                  
         
                                                             
                                             
                                             
                                                          
                     
                          
                                     
                         
             
                                       
                                                     
                                                     
                                                             
         
     

                                   
                           
                    
                                   
                                             
                     
             
                                                         
                          
                        
             
                                
         
                               
                                            
         
                               
                                  
         
                                      
                                                      
                 
                                 
                                      
                     
         
                                              
                     
     

                                   
                                                  
                          
                        
         
                                   
                        
         
                               
                                    
                                 
                                                  
                          
                        
             
                                    
         
                                   
                                      
         
                                      
                                                      
                 
                                     
                                          
                     
         
                                                  
                     
     
 

                    
               
               
                      

                                                              
                   
                         
                                       
                                  
     

                                       
                                          
                                          
                     
         
                                                
                                        
                    
                                                          
         
                                                    
                        
                         
             
                                                
         
                                                    
                                         
                         
             
                                                
         
                    
                                               
                              
                                      
                                                   
                          
                                     
                         
             
                                                       
                         
                                     
                         
             
                                       
                               
                       
         
                    
                                               
                                               
                     
                          
                                  
                                                        
                               
                                                               
                                  
                                           
                                   
                     
                 
                                     
                         
             
                     
         
                    
                                                   
                          
                         
             
                                                   
         
                    
                                                
         
                                     
                                     
                     
         
                                    
                       
                    
                     
                           
                                                     
                
                                                     
         
                
                     
         
                                                
     

                                         
                                                             
                                            
                                      
                                      
                          
                                                
                             
                       
                          
                              
                                                              
                         
                                   
                          
             
                                 
                         
         
                 
     

                                         
                                             
                    
                 
                       
                                               
                                      
                        
             
                     
                     
         
                  
     

                                        
                                                                 
                     
                                                   
         
                                          
                    
                     
         
                      
                                  
                                                   
         
                                                            
     

                           
                                  
                                    
                   
                     
         
                                                
                                    
         
                                                
                                                     
         
                   
                                            
                              
                                      
                                                
                          
                                     
                         
             
                                       
                               
                        
         
                   
                                            
                                            
                     
                          
                                  
                                                        
                               
                                       
                                
                 
                                     
                         
             
                     
         
                   
                                           
         
                   
                                               
                                         
                                         
                              
                                                    
                                 
                           
                              
                                                           
                             
                              
                 
                             
             
                     
         
                                     
                     
         
                                    
                   
                         
         
                   
                                                  
                             
             
                     
         
                                              
                         
         
                 
     

                         
                                                  
                     
                     
         
                                          
                    
                     
         
                      
                     
         
                                                     
     
 

             
             
           
                       

                                          
                      
                    
                        
     

               
                                    
     

                                      
                         
                                          
                     
         
                      
                     
         
                                     
     
 

             
                         
               
                  
                 
            

                           
                              
                                
                           
                             
                     
     

                               
                                      
     

                       
                              
                     
                                      
                                                                            
                                                  
                             
                                                                   
             
                              
                           
             
                             
         
                   
     

                                                
                             
                 
                                   
                                      
                                    
                                 
                                                    
                    
                            
             
                     
         
                  
     

                             
                                      
                            
                     
                                     
                                                                            
                                                  
                            
                                                                      
                           
                        
             
                              
                     
             
                             
         
                  
     

                       
                                                 
                       
                   
                                   
                                                                            
                                              
                        
                                
                       
                        
             
                                              
                         
         
                  
     

               
                                     
                             
                   
                    
                                   
                                                                            
                                              
                        
                                                          
                       
                        
                        
             
                         
         
                                                            
                  
     
 

// 顶层工厂（静态方法调用待 当前编译器修复）。
Result<Regex, Error> regexCompile(String pattern) {
    RegexParser p = new RegexParser(pattern)
    if p.pattern.length() > 0 && p.pattern.get(0) == 94 {
        p.anchored = true
        p.pos = 1
    }
    Result<Int, Error> root = p.parseAlt()
    if root.isErr() {
        Error rerr = root.error()
        return Err(rerr)
    }
    if p.pos != p.pattern.length() {
        return Err(textErr("regexCompile: 存在未消费字符"))
    }
    Regex rx = new Regex(pattern)
    rx.t = p.t
    rx.groupCount = p.groupCount
    rx.anchored = p.anchored
    rx.root = root.value()
    return Ok(rx)
}

// ---------- 旧种子辅助（保留兼容）----------

String repeatText(String unit, Int times) {
    if (times <= 0) { return "" }
    return unit + repeatText(unit, times - 1)
}

String repeatJoined(String unit, String sep, Int times) {
    if (times <= 0) { return "" }
    if (times == 1) { return unit }
    return unit + sep + repeatJoined(unit, sep, times - 1)
}

Bool isPositive(Int n) {
    return n > 0
}

// ---------- Strings 工具（S6 §4.1 扩展面）----------

Bool contains(String s, String sub) {
    return s.indexOf(sub) >= 0
}

Int count(String s, String sub) {
    if sub.length() == 0 {
        return 0
    }
    Int n = 0
    Int i = 0
    while i + sub.length() <= s.length() {
        if s.substring(i, sub.length()) == sub {
            n = n + 1
            i = i + sub.length()
            continue
        }
        i = i + 1
    }
    return n
}

String repeat(String s, Int n) {
    String out = ""
    Int i = 0
    while i < n {
        out = out + s
        i = i + 1
    }
    return out
}

String padLeft(String s, Int width, String ch) {
    String out = s
    while out.length() < width {
        out = ch + out
    }
    return out
}

String padRight(String s, Int width, String ch) {
    String out = s
    while out.length() < width {
        out = out + ch
    }
    return out
}

String reverse(String s) {
    Bytes buf = Bytes.fromString("")
    Int i = s.length() - 1
    while i >= 0 {
        buf.push(s.get(i))
        i = i - 1
    }
    return buf.toString()
}

Bool isEmpty(String s) {
    return s.length() == 0
}

Bool isBlank(String s) {
    String t = s.trim()
    return t.length() == 0
}

Bool equalsIgnoreCase(String a, String b) {
    return a.toUpper() == b.toUpper()
}

String capitalize(String s) {
    if s.length() == 0 {
        return s
    }
    return s.substring(0, 1).toUpper() + s.substring(1, s.length() - 1)
}

String truncate(String s, Int max) {
    if s.length() <= max {
        return s
    }
    return s.substring(0, max) + "..."
}

Int levenshtein(String a, String b) {
    Int n = a.length()
    Int m = b.length()
    List<Int> prev = []
    Int j = 0
    while j <= m {
        prev.push(j)
        j = j + 1
    }
    Int i = 1
    while i <= n {
        List<Int> cur = []
        cur.push(i)
        j = 1
        while j <= m {
            Int cost = a.get(i - 1) == b.get(j - 1) ? 0 : 1
            Int del = prev.get(j) + 1
            Int ins = cur.get(j - 1) + 1
            Int sub = prev.get(j - 1) + cost
            Int best = del
            if ins < best {
                best = ins
            }
            if sub < best {
                best = sub
            }
            cur.push(best)
            j = j + 1
        }
        prev = cur
        i = i + 1
    }
    return prev.get(m)
}

// ---------- Char 分类（单字符 String 语义）----------

Bool isDigit(String ch) {
    if ch.length() != 1 {
        return false
    }
    Int b = ch.get(0)
    return b >= 48 && b <= 57
}

Bool isAlpha(String ch) {
    if ch.length() != 1 {
        return false
    }
    Int b = ch.get(0)
    return (b >= 65 && b <= 90) || (b >= 97 && b <= 122)
}

Bool isAlnum(String ch) {
    return isAlpha(ch) || isDigit(ch)
}

Bool isSpace(String ch) {
    if ch.length() != 1 {
        return false
    }
    Int b = ch.get(0)
    return b == 32 || b == 9 || b == 10 || b == 13 || b == 11 || b == 12
}

Bool isUpper(String ch) {
    if ch.length() != 1 {
        return false
    }
    Int b = ch.get(0)
    return b >= 65 && b <= 90
}

Bool isLower(String ch) {
    if ch.length() != 1 {
        return false
    }
    Int b = ch.get(0)
    return b >= 97 && b <= 122
}

Bool isHexDigit(String ch) {
    if ch.length() != 1 {
        return false
    }
    Int b = ch.get(0)
    return (b >= 48 && b <= 57) || (b >= 97 && b <= 102) || (b >= 65 && b <= 70)
}

// ---------- CodePoint（UTF-8）----------

// 第 i 字节起解码一个 codepoint；返回值：高 32 位为 codepoint，低 1 位不可用（用 -1 表示失败）。
Int decodeCodePoint(String s, Int i) {
    Int n = s.length()
    if i >= n {
        return -1
    }
    Int b0 = s.get(i)
    if b0 < 128 {
        return b0
    }
    if (b0 & 224) == 192 && i + 1 < n {
        Int b1 = s.get(i + 1)
        if (b1 & 192) == 128 {
            return ((b0 & 31) * 64) + (b1 & 63)
        }
        return -1
    }
    if (b0 & 240) == 224 && i + 2 < n {
        Int b1 = s.get(i + 1)
        Int b2 = s.get(i + 2)
        if (b1 & 192) == 128 && (b2 & 192) == 128 {
            return ((b0 & 15) * 4096) + ((b1 & 63) * 64) + (b2 & 63)
        }
        return -1
    }
    if (b0 & 248) == 240 && i + 3 < n {
        Int b1 = s.get(i + 1)
        Int b2 = s.get(i + 2)
        Int b3 = s.get(i + 3)
        if (b1 & 192) == 128 && (b2 & 192) == 128 && (b3 & 192) == 128 {
            return ((b0 & 7) * 262144) + ((b1 & 63) * 4096) + ((b2 & 63) * 64) + (b3 & 63)
        }
        return -1
    }
    return -1
}

// UTF-8 序列长度；非法返回 -1。
Int codePointLen(String s, Int i) {
    Int b0 = s.get(i)
    if b0 < 128 {
        return 1
    }
    if (b0 & 224) == 192 {
        return 2
    }
    if (b0 & 240) == 224 {
        return 3
    }
    if (b0 & 248) == 240 {
        return 4
    }
    return -1
}

List<Int> codePoints(String s) {
    List<Int> out = []
    Int i = 0
    while i < s.length() {
        Int cp = decodeCodePoint(s, i)
        if cp < 0 {
            out.push(65533)
            i = i + 1
            continue
        }
        out.push(cp)
        Int l = codePointLen(s, i)
        i = i + (l > 0 ? l : 1)
    }
    return out
}

// codepoint → UTF-8 String（0..0x10FFFF；越界返回替换符）。
String fromCodePoint(Int cp) {
    Bytes buf = Bytes.fromString("")
    if cp < 128 {
        buf.push(cp)
        return buf.toString()
    }
    if cp < 2048 {
        buf.push(192 + (cp / 64))
        buf.push(128 + (cp % 64))
        return buf.toString()
    }
    if cp < 65536 {
        buf.push(224 + (cp / 4096))
        buf.push(128 + ((cp / 64) % 64))
        buf.push(128 + (cp % 64))
        return buf.toString()
    }
    if cp <= 1114111 {
        buf.push(240 + (cp / 262144))
        buf.push(128 + ((cp / 4096) % 64))
        buf.push(128 + ((cp / 64) % 64))
        buf.push(128 + (cp % 64))
        return buf.toString()
    }
    buf.push(239)
    buf.push(191)
    buf.push(189)
    return buf.toString()
}

// 第 i 字节处的 codepoint；非法返回 -1。
Int codePointAt(String s, Int i) {
    return decodeCodePoint(s, i)
}
