// Tier: T0；依赖：xdk.runtime、xdk.errors；稳定性：preview。
// xdk.time —— 对标 Go time + Python datetime 的时钟与日期包。
// 约定：
//   - DateTime 内部统一持有 UNIX epoch 毫秒（UTC）；civil 字段按需换算。
//   - 时区：v1 只提供 UTC 语义（toUTC/toLocal 返回自身，等价直通）。
//   - Timer 闭包式 after/every 依赖函数类型形参（已知的源码层发射缺口），
//     v1 暂缓，仅提供阻塞 sleep 与 Duration/DateTime 全量能力。

package xdk.time

import xdk.errors
import xdk.sys

// ---------- 时钟 ----------

Long nowMs() {
    return nowMono()
}

Long nowWallMs() {
    return nowWall()
}

Long millis() {
    return nowMono()
}

Long micros() {
    return nowMicrosRaw()
}

void sleepMs(Long milliseconds) {
    sleepMsRaw(milliseconds)
}

void sleep(Duration d) {
    sleepMsRaw(d.millis())
}

Duration durationOfMillis(Long ms) {
    return new Duration(ms)
}

Duration durationOfSeconds(Long s) {
    return new Duration(s * 1000)
}

Duration durationOfMinutes(Long m) {
    return new Duration(m * 60000)
}

Duration durationOfHours(Long h) {
    return new Duration(h * 3600000)
}

Duration durationOfDays(Long dd) {
    return new Duration(dd * 86400000)
}

// ---------- civil 历法（Howard Hinnant 算法，纯整数实现） ----------

Int civilFloorDiv(Int a, Int b) {
    Int q = a / b
    if (a % b != 0) && ((a < 0) != (b < 0)) {
        q = q - 1
    }
    return q
}

Int civilMod(Int a, Int b) {
    return a - civilFloorDiv(a, b) * b
}

Int daysFromCivil(Int y, Int m, Int d) {
    if m <= 2 {
        y = y - 1
    }
    Int era = civilFloorDiv(y, 400)
    Int yoe = y - era * 400
    Int mp = m + (m > 2 ? -3 : 9)
    Int doy = (153 * mp + 2) / 5 + d - 1
    Int doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
    return era * 146097 + doe - 719468
}

             
         
         
         

                                   
                   
                   
                   
     
 

Civil civilFromDays(Int z) {
    Int doe = z + 719468
    Int era = civilFloorDiv(doe, 146097)
    Int doE = doe - era * 146097
    Int yoe = (doE - doE / 1460 + doE / 36524 - doE / 146096) / 365
    Int y = yoe + era * 400
    Int doy = doE - (365 * yoe + yoe / 4 - yoe / 100)
    Int mp = (5 * doy + 2) / 153
    Int d = doy - (153 * mp + 2) / 5 + 1
    Int m = mp + (mp < 10 ? 3 : -9)
    if m <= 2 {
        y = y + 1
    }
    return new Civil(y, m, d)
}

Bool civilIsLeap(Int y) {
    return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

Int civilDaysInMonth(Int y, Int m) {
    if m == 2 && civilIsLeap(y) {
        return 29
    }
    if m == 2 {
        return 28
    }
    if m == 4 || m == 6 || m == 9 || m == 11 {
        return 30
    }
    return 31
}

// ---------- DateTime ----------

                
            

                         
                     
     

                       
                      
     

                   
                                                                     
     

                
                             
     

                 
                             
     

               
                             
     

                
                                                           
     

                  
                                                        
     

                  
                                                     
     

                       
                                             
     

                                        
                   
                                                                       
     

                     
                              
                   
                 
                       
                                                
                     
         
                        
     

                              
                                           
     

                                   
                                               
     

                                 
                                 
     

                                
                                 
     

                                 
                               
                     
         
                               
                    
         
                
     

                      
                   
     

                        
                   
     

                                             
                                   
                                  
                           
                                                                  
                                                                        
                                                                 
                                                               
                                                                
                                                                  
                                                                  
                  
     

                      
                                                     
     

                      
                                                       
     
 

String padLeftNum(String s, Int width) {
    String out = s
    while out.length() < width {
        out = "0" + out
    }
    return out
}

// ---------- 工厂 ----------

DateTime dateTimeOf(Int y, Int mo, Int d, Int h, Int mi, Int s) {
    Int days = daysFromCivil(y, mo, d)
    Long ms = (days as Long) * 86400000 + ((h * 3600 + mi * 60 + s) as Long) * 1000
    return new DateTime(ms)
}

DateTime dateTimeOfMs(Int y, Int mo, Int d, Int h, Int mi, Int s, Int msPart) {
    DateTime base = dateTimeOf(y, mo, d, h, mi, s)
    return new DateTime(base.ms + msPart)
}

DateTime dateTimeFromTimestamp(Long ms) {
    return new DateTime(ms)
}

DateTime now() {
    return new DateTime(nowWall())
}

// ---------- 解析 ----------

// 十进制数字段解析；非法字符返回 -1（Char 面以单字符子串比对，避开 Char/Int 混合比较）。
Int parseDigits(String s, Int start, Int n) {
    Int v = 0
    Int i = 0
    while i < n {
        String c = s.substring(start + i, 1)
        if c == "0" { v = v * 10 + 0 }
        else if c == "1" { v = v * 10 + 1 }
        else if c == "2" { v = v * 10 + 2 }
        else if c == "3" { v = v * 10 + 3 }
        else if c == "4" { v = v * 10 + 4 }
        else if c == "5" { v = v * 10 + 5 }
        else if c == "6" { v = v * 10 + 6 }
        else if c == "7" { v = v * 10 + 7 }
        else if c == "8" { v = v * 10 + 8 }
        else if c == "9" { v = v * 10 + 9 }
        else { return -1 }
        i = i + 1
    }
    return v
}

// 仅接受 iso8601/rfc3339 子集：yyyy-MM-ddTHH:mm:ss[.SSS][Z]。
Result<DateTime, Error> parseDateTime(String s) {
    if s.length() < 19 {
        return Err(sysError(ErrorKind.InvalidArgument, "parseDateTime: 格式过短"))
    }
    Int y = parseDigits(s, 0, 4)
    Int mo = parseDigits(s, 5, 2)
    Int d = parseDigits(s, 8, 2)
    Int h = parseDigits(s, 11, 2)
    Int mi = parseDigits(s, 14, 2)
    Int sec = parseDigits(s, 17, 2)
    if y < 0 || mo < 1 || mo > 12 || d < 1 || d > civilDaysInMonth(y, mo) ||
        h < 0 || h > 23 || mi < 0 || mi > 59 || sec < 0 || sec > 60 {
        return Err(sysError(ErrorKind.InvalidArgument, "parseDateTime: 非法日期字段"))
    }
    DateTime dt = dateTimeOf(y, mo, d, h, mi, sec)
    if s.length() >= 23 && s.substring(19, 1) == "." {
        Int msPart = parseDigits(s, 20, 3)
        if msPart < 0 {
            return Err(sysError(ErrorKind.InvalidArgument, "parseDateTime: 非法毫秒段"))
        }
        dt = new DateTime(dt.ms + msPart)
    }
    return Ok(dt)
}
