// Tier: T0；依赖：xdk.errors、xdk.bytes；稳定性：preview。
// xdk.text —— S6-05 源码单元（Format builder / parse / UTF-8↔UTF-16 / Regex）
//
// 依赖：xdk.errors（错误值）；C 原语对应 src/runtime/rt_std_text.c
// （parse_int/parse_float/utf8_to_utf16/utf16_to_utf8/regex_match；解释器路径由等价源码执行）。
// 稳定性：@preview。
// 合同：可失败操作返回 Result；Regex 动态编译失败是可恢复错误，不 panic。
package xdk.text
import xdk.errors

// ---------- 格式化 builder ----------

                                                            
              
                      
                    
                   

                                              
                        
                          
                      
     

                              
                                         
     

                                   
                                           
     

                                    
                                    
     

                                
              
                                             
         
                                          
     

                         
                                                 
     

                        
                                                   
     

                    
                              
                                   
                                         
                            
         
                  
     
 

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
    BasicError be = new BasicError(ErrorKind.InvalidArgument, msg)
    return be
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
Result<List<UInt16>, Error> utf8ToUtf16(Bytes b) {
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
    return Ok(res)
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

// ---------- Regex（POSIX ERE 起步子集：字面量、.、* + ?、^ $）----------

             
                         

                           
                              
     

                                                         
                 
                                    
                                               
                                                                                            
                                                                  
             
                                                                
                                                            
             
                                                       
                                                             
             
                     
         
                                     
     

                               
                  
                                                                             
                                                         
         
                     
                                      
                                                                         
                             
         
                    
     
 

static Bool regexAtomMatch(String atom, String ch) {
    if atom == "." { return true }
    return atom == ch
}

static Bool regexMatchAt(String pattern, Int pi, String text, Int ti) {
    Int plen = pattern.length()
    if pi >= plen { return true }
    String c = pattern.substring(pi, 1)
    if c == "$" && pi == plen - 1 { return ti == text.length() }
    String next = ""
    if pi + 1 < plen { next = pattern.substring(pi + 1, 1) }
    Bool quant = next == "*" || next == "+" || next == "?"
    if quant {
        Int nextp = pi + 2
        Int k = ti
        Int count = 0
        while k < text.length() && regexAtomMatch(c, text.substring(k, 1)) {
            count = count + 1
            k = k + 1
        }
        Int min = 1
        Int max = count
        if next == "*" { min = 0 }
        if next == "?" { min = 0; if max > 1 { max = 1 } }
        Int use = max
        while use >= min {
            if regexMatchAt(pattern, nextp, text, ti + use) { return true }
            use = use - 1
        }
        return false
    }
    if ti >= text.length() { return false }
    if regexAtomMatch(c, text.substring(ti, 1)) { return regexMatchAt(pattern, pi + 1, text, ti + 1) }
    return false
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
