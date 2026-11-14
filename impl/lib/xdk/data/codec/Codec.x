// xdk.codec —— 编解码包：Base64 / URL / JSON / CSV / 二进制。
// 约定：
//   - Hex 编解码直接复用 xdk.sys 的 hexEncode/hexDecode；
//   - JsonValue 的对象侧用平行 List 实现（Map 对类值在源码层尚未接线，已知缺口）；
//   - \\uXXXX 转义 v1 返回错误（缺 Char←Int 构造原语）；
//   - 浮点位模式经 ext_raw 的 f32/f64 bits 原语。
package xdk.codec
import xdk.errors
import xdk.sys
import xdk.math

// ---------- Base64 ----------

String b64StdAlphabet() {
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
}

String b64UrlAlphabet() {
    return "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
}

String base64Encode(Bytes b) {
    return base64EncodeAlphabet(b, b64StdAlphabet(), true)
}

String base64UrlEncode(Bytes b) {
    return base64EncodeAlphabet(b, b64UrlAlphabet(), false)
}

String base64EncodeAlphabet(Bytes b, String alpha, Bool pad) {
    String out = ""
    Int n = b.length()
    Int i = 0
    while i + 2 < n {
        Int v = (b.get(i) * 65536) + (b.get(i + 1) * 256) + b.get(i + 2)
        out = out + alpha.substring((v / 262144) % 64, 1)
            + alpha.substring((v / 4096) % 64, 1)
            + alpha.substring((v / 64) % 64, 1)
            + alpha.substring(v % 64, 1)
        i = i + 3
    }
    Int rem = n - i
    if rem == 1 {
        Int v = b.get(i) * 65536
        out = out + alpha.substring((v / 262144) % 64, 1) + alpha.substring((v / 4096) % 64, 1)
        if pad {
            out = out + "=="
        }
    } else if rem == 2 {
        Int v = (b.get(i) * 65536) + (b.get(i + 1) * 256)
        out = out + alpha.substring((v / 262144) % 64, 1)
            + alpha.substring((v / 4096) % 64, 1)
            + alpha.substring((v / 64) % 64, 1)
        if pad {
            out = out + "="
        }
    }
    return out
}

// 按 alphabet 反查（64 字节内线性扫描）。
Int b64IndexOf(String alpha, Int byte) {
    Int i = 0
    while i < 64 {
        if alpha.get(i) == byte {
            return i
        }
        i = i + 1
    }
    return -1
}

Result<Bytes, Error> base64Decode(String s) {
    return base64DecodeAlphabet(s, b64StdAlphabet(), true)
}

Result<Bytes, Error> base64UrlDecode(String s) {
    return base64DecodeAlphabet(s, b64UrlAlphabet(), false)
}

Result<Bytes, Error> base64DecodeAlphabet(String s, String alpha, Bool pad) {
    String t = s.trim()
    if pad {
        while t.length() > 0 && t.substring(t.length() - 1, 1) == "=" {
            t = t.substring(0, t.length() - 1)
        }
    }
    Int n = t.length()
    if n % 4 == 1 {
        return Err(sysError(ErrorKind.DataCorrupted, "base64Decode: 长度非法"))
    }
    Bytes out = Bytes.fromString("")
    Int i = 0
    while i + 3 < n {
        Int a = b64IndexOf(alpha, t.get(i))
        Int b = b64IndexOf(alpha, t.get(i + 1))
        Int c = b64IndexOf(alpha, t.get(i + 2))
        Int d = b64IndexOf(alpha, t.get(i + 3))
        if a < 0 || b < 0 || c < 0 || d < 0 {
            return Err(sysError(ErrorKind.DataCorrupted, "base64Decode: 非法字符"))
        }
        Int v = a * 262144 + b * 4096 + c * 64 + d
        out.push((v / 65536) % 256)
        out.push((v / 256) % 256)
        out.push(v % 256)
        i = i + 4
    }
    Int rem = n - i
    if rem == 2 {
        Int a = b64IndexOf(alpha, t.get(i))
        Int b = b64IndexOf(alpha, t.get(i + 1))
        if a < 0 || b < 0 {
            return Err(sysError(ErrorKind.DataCorrupted, "base64Decode: 非法字符"))
        }
        Int v = a * 262144 + b * 4096
        out.push((v / 65536) % 256)
    } else if rem == 3 {
        Int a = b64IndexOf(alpha, t.get(i))
        Int b = b64IndexOf(alpha, t.get(i + 1))
        Int c = b64IndexOf(alpha, t.get(i + 2))
        if a < 0 || b < 0 || c < 0 {
            return Err(sysError(ErrorKind.DataCorrupted, "base64Decode: 非法字符"))
        }
        Int v = a * 262144 + b * 4096 + c * 64
        out.push((v / 65536) % 256)
        out.push((v / 256) % 256)
    }
    return Ok(out)
}

// ---------- URL ----------

Bool isUrlUnreserved(Int byte) {
    if byte >= 48 && byte <= 57 { return true }
    if byte >= 65 && byte <= 90 { return true }
    if byte >= 97 && byte <= 122 { return true }
    if byte == 45 || byte == 95 || byte == 46 || byte == 126 { return true }
    return false
}

String hexByteUpper(Int byte) {
    String hex = "0123456789ABCDEF"
    return hex.substring((byte / 16) % 16, 1) + hex.substring(byte % 16, 1)
}

String urlEncode(String s) {
    String out = ""
    Int i = 0
    while i < s.length() {
        Int byte = s.get(i)
        if isUrlUnreserved(byte) {
            out = out + s.substring(i, 1)
        } else {
            out = out + "%" + hexByteUpper(byte)
        }
        i = i + 1
    }
    return out
}

String queryEscape(String s) {
    String out = ""
    Int i = 0
    while i < s.length() {
        Int byte = s.get(i)
        if byte == 32 {
            out = out + "%20"
        } else if isUrlUnreserved(byte) {
            out = out + s.substring(i, 1)
        } else {
            out = out + "%" + hexByteUpper(byte)
        }
        i = i + 1
    }
    return out
}

Int hexDigitVal(Int byte) {
    if byte >= 48 && byte <= 57 { return byte - 48 }
    if byte >= 97 && byte <= 102 { return byte - 97 + 10 }
    if byte >= 65 && byte <= 70 { return byte - 65 + 10 }
    return -1
}

String urlDecode(String s) {
    Bytes out = Bytes.fromString("")
    Int i = 0
    Int n = s.length()
    while i < n {
        Int byte = s.get(i)
        if byte == 37 && i + 2 < n {
            Int hi = hexDigitVal(s.get(i + 1))
            Int lo = hexDigitVal(s.get(i + 2))
            if hi >= 0 && lo >= 0 {
                out.push(hi * 16 + lo)
                i = i + 3
                continue
            }
        }
        if byte == 43 {
            out.push(32)
            i = i + 1
            continue
        }
        out.push(byte)
        i = i + 1
    }
    return out.toString()
}

String queryUnescape(String s) {
    return urlDecode(s)
}

String buildQuery(Map<String, String> params) {
    String out = ""
    List<String> ks = params.keys()
    Int i = 0
    while i < ks.length() {
        if i > 0 {
            out = out + "&"
        }
        out = out + queryEscape(ks.get(i)) + "=" + queryEscape(params.get(ks.get(i)))
        i = i + 1
    }
    return out
}

                             
                 
                                                                       
          
              
              
                       
                        
                           

                          
                         
                      
                      
                     
                     
                         
                         
     

                                           
                                           
                                             
                                             
                                            
                                             

                                   
                                         
                                          
                                         
                                                
                                               

                               
                 
                                         
                                           
                                          
             
                     
         
                               
     

                           
                                                
                                   
         
                                
     

                
                           
                                    
         
                                    
     

                                          
                 
                                         
                                           
                                      
                      
             
                     
         
                              
                            
     

                            
                        
     

                        
                                  
     

                               
                                          
     
 
 

JsonValue jsonNull() {
    return new JsonValue(0)
}

JsonValue jsonBool(Bool v) {
    JsonValue j = new JsonValue(1)
    j.b = v
    return j
}

JsonValue jsonNumber(Double v) {
    JsonValue j = new JsonValue(2)
    j.num = v
    return j
}

JsonValue jsonInt(Int v) {
    JsonValue j = new JsonValue(2)
    j.num = v * 1.0
    return j
}

JsonValue jsonStringValue(String v) {
    JsonValue j = new JsonValue(3)
    j.str = v
    return j
}

// JSON 字符串转义。
String jsonEscape(String s) {
    String out = "\""
    Int i = 0
    while i < s.length() {
        Int byte = s.get(i)
        if byte == 34 {
            out = out + "\\\""
        } else if byte == 92 {
            out = out + "\\\\"
        } else if byte == 10 {
            out = out + "\\n"
        } else if byte == 13 {
            out = out + "\\r"
        } else if byte == 9 {
            out = out + "\\t"
        } else {
            out = out + s.substring(i, 1)
        }
        i = i + 1
    }
    return out + "\""
}

String jsonStringify(JsonValue v) {
    if v.kind == 0 {
        return "null"
    }
    if v.kind == 1 {
        if v.b {
            return "true"
        }
        return "false"
    }
    if v.kind == 2 {
        return str(v.num)
    }
    if v.kind == 3 {
        return jsonEscape(v.str)
    }
    if v.kind == 4 {
        String out = "["
        Int i = 0
        while i < v.arr.length() {
            if i > 0 {
                out = out + ","
            }
            out = out + jsonStringify(v.arr.get(i))
            i = i + 1
        }
        return out + "]"
    }
    String out = "{"
    Int i = 0
    while i < v.objKeys.length() {
        if i > 0 {
            out = out + ","
        }
        out = out + jsonEscape(v.objKeys.get(i)) + ":" + jsonStringify(v.objVals.get(i))
        i = i + 1
    }
    return out + "}"
}

String jsonIndent(Int indent, Int depth) {
    String out = ""
    Int total = indent * depth
    Int i = 0
    while i < total {
        out = out + " "
        i = i + 1
    }
    return out
}

String jsonPretty(JsonValue v, Int indent, Int depth) {
    String nl = "\n"
    if v.kind == 4 {
        if v.arr.length() == 0 {
            return "[]"
        }
        String out = "[" + nl
        Int i = 0
        while i < v.arr.length() {
            if i > 0 {
                out = out + "," + nl
            }
            out = out + jsonIndent(indent, depth + 1) + jsonPretty(v.arr.get(i), indent, depth + 1)
            i = i + 1
        }
        return out + nl + jsonIndent(indent, depth) + "]"
    }
    if v.kind == 5 {
        if v.objKeys.length() == 0 {
            return "{}"
        }
        String out = "{" + nl
        Int i = 0
        while i < v.objKeys.length() {
            if i > 0 {
                out = out + "," + nl
            }
            out = out + jsonIndent(indent, depth + 1) + jsonEscape(v.objKeys.get(i)) + ": "
                + jsonPretty(v.objVals.get(i), indent, depth + 1)
            i = i + 1
        }
        return out + nl + jsonIndent(indent, depth) + "}"
    }
    return jsonStringify(v)
}
                       
                  
            
         

                           
                   
                  
     

                   
                                        
                                         
                                                                    
                                   
                    
                      
             
         
     

                
                                      
                     
         
                                 
     

                                           
                     
                           
                     
                                             
         
                     
                                             
         
                     
                                              
         
                    
                                     
         
                    
                                    
         
                     
                                     
         
                                            
                                     
         
                                                                           
     

                                                                
                             
                 
                     
                                                                               
                                                                                 
             
                               
                     
         
                                         
                      
                                             
         
                    
     

                                            
                          
                              
                               
         
                              
                                        
                                      
                                                                                             
                                       
                                    
                 
                                   
                    
                     
             
         
                       
                                                                            
         
                                                             
                                    
                     
                                                                            
         
                                
     

                                            
                           
                                        
                                        
                                      
                        
                                   
                                                          
             
                        
                                   
                                              
                                                                                    
                 
                                          
                                           
                                                
                                                
                                               
                                                 
                                                 
                                                 
                                                
                                  
                                                                                            
                 
                      
                                                                                    
                 
                                   
                        
             
                       
                               
         
                                                                          
     

                                           
                           
                                        
                     
                              
                               
                          
         
                    
                                                             
                             
                           
             
                                  
                         
                               
                        
                                   
                        
             
                        
                                   
                              
             
                                                                               
         
     

                                            
                           
                                        
                     
                               
                               
                          
         
                    
                         
                                  
                                                                                     
             
                                                              
                             
                           
             
                         
                                  
                                                                                
             
                               
                                                            
                            
                          
             
                                                            
                         
                               
                        
                                   
                        
             
                         
                                   
                              
             
                                                                               
         
     
 
 

// ---------- 数值解析（纯源码 strtod 子集） ----------

// 十进制浮点：[+-]digits[.digits][(e|E)[+-]digits]；非法/空返回 NaN。
Double parseDouble(String s) {
    Int i = 0
    Int n = s.length()
    Bool neg = false
    if i < n && s.get(i) == 45 {
        neg = true
        i = i + 1
    } else if i < n && s.get(i) == 43 {
        i = i + 1
    }
    Int64 mant = 0
    Int fracExp = 0
    Bool any = false
    while i < n && s.get(i) >= 48 && s.get(i) <= 57 {
        mant = mant * 10 + (s.get(i) - 48)
        i = i + 1
        any = true
    }
    if i < n && s.get(i) == 46 {
        i = i + 1
        while i < n && s.get(i) >= 48 && s.get(i) <= 57 {
            mant = mant * 10 + (s.get(i) - 48)
            fracExp = fracExp + 1
            i = i + 1
            any = true
        }
    }
    if !any {
        return NaN()
    }
    Int expo = 0
    if i < n && (s.get(i) == 101 || s.get(i) == 69) {
        i = i + 1
        Bool eneg = false
        if i < n && s.get(i) == 45 {
            eneg = true
            i = i + 1
        } else if i < n && s.get(i) == 43 {
            i = i + 1
        }
        Int d2 = 0
        Bool eany = false
        while i < n && s.get(i) >= 48 && s.get(i) <= 57 {
            d2 = d2 * 10 + (s.get(i) - 48)
            i = i + 1
            eany = true
        }
        if !eany {
            return NaN()
        }
        if eneg {
            expo = -d2
        } else {
            expo = d2
        }
    }
    if i != n {
        return NaN()
    }
    Double v = mant * 1.0
    Int totalExp = expo - fracExp
    while totalExp > 0 {
        v = v * 10.0
        totalExp = totalExp - 1
    }
    while totalExp < 0 {
        v = v / 10.0
        totalExp = totalExp + 1
    }
    if neg {
        return -v
    }
    return v
}

Result<JsonValue, Error> jsonParse(String s) {
    JsonParser p = new JsonParser(s)
    Result<JsonValue, Error> v = p.parseValue()
    if v.isErr() {
        return v
    }
    p.skipWs()
    if p.i != s.length() {
        return Err(sysError(ErrorKind.DataCorrupted, "jsonParse: 存在尾随内容"))
    }
    return v
}

// ---------- CSV ----------
//
// 嵌套泛型（List<List<String>>）的 typeKey/C 名在当前编译器存在碰撞与损坏
// （已知缺口），CSV 以 CsvRow/CsvTable 类承载行结构规避。

              
                      

              
                       
     

               
                                  
     

              
                       
                                              
                     
         
                                
     

                        
                          
     
 

                
                     

                
                      
     

                    
                                 
     

              
                       
                                             
                               
         
                               
     

                           
                         
     
 

// 解析 CSV（RFC 4180 子集：引号包裹、双引号转义、CRLF/LF）。
Result<CsvTable, Error> csvParse(String s) {
    CsvTable table = new CsvTable()
    CsvRow row = new CsvRow()
    String field = ""
    Bool quoted = false
    Int i = 0
    Int n = s.length()
    if n == 0 {
        return Ok(table)
    }
    while i < n {
        Int c = s.get(i)
        if quoted {
            if c == 34 {
                if i + 1 < n && s.get(i + 1) == 34 {
                    field = field + "\""
                    i = i + 2
                    continue
                }
                quoted = false
                i = i + 1
                continue
            }
            field = field + s.substring(i, 1)
            i = i + 1
            continue
        }
        if c == 34 && field.length() == 0 {
            quoted = true
            i = i + 1
            continue
        }
        if c == 44 {
            row.add(field)
            field = ""
            i = i + 1
            continue
        }
        if c == 13 {
            i = i + 1
            continue
        }
        if c == 10 {
            row.add(field)
            field = ""
            table.addRow(row)
            row = new CsvRow()
            i = i + 1
            continue
        }
        field = field + s.substring(i, 1)
        i = i + 1
    }
    if quoted {
        return Err(sysError(ErrorKind.DataCorrupted, "csvParse: 引号未闭合"))
    }
    if field.length() > 0 || row.len() > 0 {
        row.add(field)
        table.addRow(row)
    }
    return Ok(table)
}

String csvField(String v, String sep) {
    Bool needQuote = v.indexOf("\"") >= 0 || v.indexOf(sep) >= 0 ||
        v.indexOf("\n") >= 0 || v.indexOf("\r") >= 0
    if !needQuote {
        return v
    }
    return "\"" + v.replace("\"", "\"\"") + "\""
}

String csvEncode(CsvTable table, String sep) {
    String out = ""
    Int r = 0
    while r < table.rowCount() {
        CsvRow row = table.row(r)
        Int c = 0
        while c < row.len() {
            if c > 0 {
                out = out + sep
            }
            out = out + csvField(row.get(c), sep)
            c = c + 1
        }
        out = out + "\n"
        r = r + 1
    }
    return out
}

                                             
                    
              
           

                           
                     
                    
     

                
                       
     

                      
                  
                 
         
                                   
                                  
         
                    
     

                     
                                            
     

                
                                             
     

                     
                                    
     

                  
                                       
                               
                
     

                     
                                                                           
                               
                
     

                     
                                                                           
                               
                
     

                     
                                                                             
                                                                                        
                               
                
     

                     
                                                                                          
                                                                           
                               
                
     

                       
                   
                     
                 
                     
                                                                   
                             
                     
         
                               
                
     

                       
                   
                 
                     
                                                     
                     
         
                               
                
     

                     
                                
                            
                              
         
                
     

                        
                                   
                                   
     

                        
                                     
                                   
     

                            
                                        
                 
                                                      
                                             
                                   
                     
         
                  
     
 
 

Int pow2(Int n) {
    Int v = 1
    Int i = 0
    while i < n {
        v = v * 2
        i = i + 1
    }
    return v
}
                    
             

                    
                                       
     

                     
                       
     

                  
                                
     

                         
                              
     

                            
                              
                                      
     

                            
                                      
                              
     

                            
                              
                                      
                                        
                                           
     

                            
                                           
                                        
                                      
                              
     

                              
                 
                     
                                                  
                     
         
     

                              
                 
                      
                                                  
                     
         
     

                            
                  
                              
         
                          
     

                               
                                      
     

                               
                                      
     

                                
                                   
                 
                              
                                   
                     
         
     

                              
                 
                              
                                   
                     
         
     
 
 
