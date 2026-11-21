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

// T0-X：上下文感知 sleep；取消时返回 ErrorKind.Cancelled。
Result<Unit, Error> sleepContext(Context context, Duration duration) {
    Int rc = sleepContextRaw(context, duration.millis())
    if rc == 1 {
        return Err(sysError(ErrorKind.Cancelled, "sleepContext: 已取消"))
    }
    return Ok()
}

// T0-X：单调 Stopwatch。构造即开始；stop 冻结 elapsed，reset 清零点并继续。
class Stopwatch {
    Long startedAt
    Long stoppedAt
    Bool running

    Stopwatch() {
        self.startedAt = nowMono()
        self.stoppedAt = 0
        self.running = true
    }

    void start() {
        self.startedAt = nowMono()
        self.stoppedAt = 0
        self.running = true
    }

    Long stop() {
        if self.running {
            self.stoppedAt = nowMono()
            self.running = false
        }
        return self.elapsedMs()
    }

    Long reset() {
        Long previous = self.elapsedMs()
        self.startedAt = nowMono()
        self.stoppedAt = 0
        self.running = true
        return previous
    }

    Bool isRunning() {
        return self.running
    }

    Long elapsedMs() {
        if self.running {
            return nowMono() - self.startedAt
        }
        return self.stoppedAt - self.startedAt
    }

    Duration elapsed() {
        return durationOfMillis(self.elapsedMs())
    }
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

// 布局名称匹配：从 start 起严格匹配 name（大小写敏感，与 format 输出一致）。
Bool layoutNameAt(String text, Int start, String name) {
    if start < 0 || start + name.length() > text.length() {
        return false
    }
    return text.substring(start, name.length()) == name
}

Int monthFromShortAt(String text, Int start) {
    if layoutNameAt(text, start, "Jan") { return 1 }
    if layoutNameAt(text, start, "Feb") { return 2 }
    if layoutNameAt(text, start, "Mar") { return 3 }
    if layoutNameAt(text, start, "Apr") { return 4 }
    if layoutNameAt(text, start, "May") { return 5 }
    if layoutNameAt(text, start, "Jun") { return 6 }
    if layoutNameAt(text, start, "Jul") { return 7 }
    if layoutNameAt(text, start, "Aug") { return 8 }
    if layoutNameAt(text, start, "Sep") { return 9 }
    if layoutNameAt(text, start, "Oct") { return 10 }
    if layoutNameAt(text, start, "Nov") { return 11 }
    if layoutNameAt(text, start, "Dec") { return 12 }
    return 0
}

Int monthFromLongAt(String text, Int start) {
    if layoutNameAt(text, start, "January") { return 1 }
    if layoutNameAt(text, start, "February") { return 2 }
    if layoutNameAt(text, start, "March") { return 3 }
    if layoutNameAt(text, start, "April") { return 4 }
    if layoutNameAt(text, start, "May") { return 5 }
    if layoutNameAt(text, start, "June") { return 6 }
    if layoutNameAt(text, start, "July") { return 7 }
    if layoutNameAt(text, start, "August") { return 8 }
    if layoutNameAt(text, start, "September") { return 9 }
    if layoutNameAt(text, start, "October") { return 10 }
    if layoutNameAt(text, start, "November") { return 11 }
    if layoutNameAt(text, start, "December") { return 12 }
    return 0
}

Int weekdayFromShortAt(String text, Int start) {
    if layoutNameAt(text, start, "Sun") { return 0 }
    if layoutNameAt(text, start, "Mon") { return 1 }
    if layoutNameAt(text, start, "Tue") { return 2 }
    if layoutNameAt(text, start, "Wed") { return 3 }
    if layoutNameAt(text, start, "Thu") { return 4 }
    if layoutNameAt(text, start, "Fri") { return 5 }
    if layoutNameAt(text, start, "Sat") { return 6 }
    return -1
}

Int weekdayFromLongAt(String text, Int start) {
    if layoutNameAt(text, start, "Sunday") { return 0 }
    if layoutNameAt(text, start, "Monday") { return 1 }
    if layoutNameAt(text, start, "Tuesday") { return 2 }
    if layoutNameAt(text, start, "Wednesday") { return 3 }
    if layoutNameAt(text, start, "Thursday") { return 4 }
    if layoutNameAt(text, start, "Friday") { return 5 }
    if layoutNameAt(text, start, "Saturday") { return 6 }
    return -1
}

Error layoutParseError(String detail) {
    return sysError(ErrorKind.InvalidArgument, "parseDateTimeLayout: " + detail)
}

// 全量布局解析：与 DateTime.format 使用同一令牌集合与最长匹配顺序。
// 缺失字段按 1970-01-01 00:00:00.000 补齐；重复字段、非法字段、尾随字符均报错。
Result<DateTime, Error> parseDateTimeLayout(String text, String layout) {
    Int year = 1970
    Int month = 1
    Int day = 1
    Int hour = 0
    Int minute = 0
    Int second = 0
    Int millisecond = 0
    Bool sawYear = false
    Bool sawMonth = false
    Bool sawDay = false
    Bool sawHour = false
    Bool sawMinute = false
    Bool sawSecond = false
    Bool sawMillisecond = false
    Bool sawWeekday = false
    Int weekday = 0
    Int textIndex = 0
    Int layoutIndex = 0
    while layoutIndex < layout.length() {
        if layoutAt(layout, layoutIndex, "yyyy") {
            if sawYear { return Err(layoutParseError("年份字段重复")) }
            if textIndex + 4 > text.length() { return Err(layoutParseError("年份字段不完整")) }
            year = parseDigits(text, textIndex, 4)
            if year < 0 { return Err(layoutParseError("年份不是数字")) }
            sawYear = true
            textIndex = textIndex + 4
            layoutIndex = layoutIndex + 4
        } else if layoutAt(layout, layoutIndex, "MMMM") {
            if sawMonth { return Err(layoutParseError("月份字段重复")) }
            month = monthFromLongAt(text, textIndex)
            if month == 0 { return Err(layoutParseError("月份名称非法")) }
            sawMonth = true
            textIndex = textIndex + monthLongName(month).length()
            layoutIndex = layoutIndex + 4
        } else if layoutAt(layout, layoutIndex, "EEEE") {
            if sawWeekday { return Err(layoutParseError("星期字段重复")) }
            weekday = weekdayFromLongAt(text, textIndex)
            if weekday < 0 { return Err(layoutParseError("星期名称非法")) }
            sawWeekday = true
            textIndex = textIndex + weekdayLongName(weekday).length()
            layoutIndex = layoutIndex + 4
        } else if layoutAt(layout, layoutIndex, "dddd") {
            if sawWeekday { return Err(layoutParseError("星期字段重复")) }
            weekday = weekdayFromLongAt(text, textIndex)
            if weekday < 0 { return Err(layoutParseError("星期名称非法")) }
            sawWeekday = true
            textIndex = textIndex + weekdayLongName(weekday).length()
            layoutIndex = layoutIndex + 4
        } else if layoutAt(layout, layoutIndex, "SSS") {
            if sawMillisecond { return Err(layoutParseError("毫秒字段重复")) }
            if textIndex + 3 > text.length() { return Err(layoutParseError("毫秒字段不完整")) }
            millisecond = parseDigits(text, textIndex, 3)
            if millisecond < 0 { return Err(layoutParseError("毫秒不是数字")) }
            sawMillisecond = true
            textIndex = textIndex + 3
            layoutIndex = layoutIndex + 3
        } else if layoutAt(layout, layoutIndex, "MMM") {
            if sawMonth { return Err(layoutParseError("月份字段重复")) }
            month = monthFromShortAt(text, textIndex)
            if month == 0 { return Err(layoutParseError("月份简称非法")) }
            sawMonth = true
            textIndex = textIndex + 3
            layoutIndex = layoutIndex + 3
        } else if layoutAt(layout, layoutIndex, "EEE") {
            if sawWeekday { return Err(layoutParseError("星期字段重复")) }
            weekday = weekdayFromShortAt(text, textIndex)
            if weekday < 0 { return Err(layoutParseError("星期简称非法")) }
            sawWeekday = true
            textIndex = textIndex + 3
            layoutIndex = layoutIndex + 3
        } else if layoutAt(layout, layoutIndex, "ddd") {
            if sawWeekday { return Err(layoutParseError("星期字段重复")) }
            weekday = weekdayFromShortAt(text, textIndex)
            if weekday < 0 { return Err(layoutParseError("星期简称非法")) }
            sawWeekday = true
            textIndex = textIndex + 3
            layoutIndex = layoutIndex + 3
        } else if layoutAt(layout, layoutIndex, "MM") {
            if sawMonth { return Err(layoutParseError("月份字段重复")) }
            if textIndex + 2 > text.length() { return Err(layoutParseError("月份字段不完整")) }
            month = parseDigits(text, textIndex, 2)
            if month < 0 { return Err(layoutParseError("月份不是数字")) }
            sawMonth = true
            textIndex = textIndex + 2
            layoutIndex = layoutIndex + 2
        } else if layoutAt(layout, layoutIndex, "dd") {
            if sawDay { return Err(layoutParseError("日期字段重复")) }
            if textIndex + 2 > text.length() { return Err(layoutParseError("日期字段不完整")) }
            day = parseDigits(text, textIndex, 2)
            if day < 0 { return Err(layoutParseError("日期不是数字")) }
            sawDay = true
            textIndex = textIndex + 2
            layoutIndex = layoutIndex + 2
        } else if layoutAt(layout, layoutIndex, "HH") {
            if sawHour { return Err(layoutParseError("小时字段重复")) }
            if textIndex + 2 > text.length() { return Err(layoutParseError("小时字段不完整")) }
            hour = parseDigits(text, textIndex, 2)
            if hour < 0 { return Err(layoutParseError("小时不是数字")) }
            sawHour = true
            textIndex = textIndex + 2
            layoutIndex = layoutIndex + 2
        } else if layoutAt(layout, layoutIndex, "mm") {
            if sawMinute { return Err(layoutParseError("分钟字段重复")) }
            if textIndex + 2 > text.length() { return Err(layoutParseError("分钟字段不完整")) }
            minute = parseDigits(text, textIndex, 2)
            if minute < 0 { return Err(layoutParseError("分钟不是数字")) }
            sawMinute = true
            textIndex = textIndex + 2
            layoutIndex = layoutIndex + 2
        } else if layoutAt(layout, layoutIndex, "ss") {
            if sawSecond { return Err(layoutParseError("秒字段重复")) }
            if textIndex + 2 > text.length() { return Err(layoutParseError("秒字段不完整")) }
            second = parseDigits(text, textIndex, 2)
            if second < 0 { return Err(layoutParseError("秒不是数字")) }
            sawSecond = true
            textIndex = textIndex + 2
            layoutIndex = layoutIndex + 2
        } else {
            if textIndex >= text.length() { return Err(layoutParseError("文本提前结束")) }
            if text.substring(textIndex, 1) != layout.substring(layoutIndex, 1) {
                return Err(layoutParseError("字面量不匹配"))
            }
            textIndex = textIndex + 1
            layoutIndex = layoutIndex + 1
        }
    }
    if textIndex != text.length() {
        return Err(layoutParseError("存在尾随字符"))
    }
    if month < 1 || month > 12 || day < 1 || day > civilDaysInMonth(year, month) ||
        hour < 0 || hour > 23 || minute < 0 || minute > 59 ||
        second < 0 || second > 59 || millisecond < 0 || millisecond > 999 {
        return Err(layoutParseError("非法日期字段"))
    }
    DateTime parsed = dateTimeOf(year, month, day, hour, minute, second)
    if millisecond != 0 {
        parsed = new DateTime(parsed.ms + millisecond)
    }
    if sawWeekday && parsed.weekday() != weekday {
        return Err(layoutParseError("星期与日期不一致"))
    }
    return Ok(parsed)
}

// ISO 8601 / RFC 3339 子集：yyyy-MM-ddTHH:mm:ss[.SSS][Z]；空格分隔也接受。
Result<DateTime, Error> parseDateTime(String s) {
    String text = s
    if text.endsWith("Z") {
        text = text.substring(0, text.length() - 1)
    }
    Result<DateTime, Error> parsed = parseDateTimeLayout(text, "yyyy-MM-ddTHH:mm:ss.SSS")
    if parsed.isOk() { return parsed }
    parsed = parseDateTimeLayout(text, "yyyy-MM-dd HH:mm:ss.SSS")
    if parsed.isOk() { return parsed }
    parsed = parseDateTimeLayout(text, "yyyy-MM-ddTHH:mm:ss")
    if parsed.isOk() { return parsed }
    parsed = parseDateTimeLayout(text, "yyyy-MM-dd HH:mm:ss")
    if parsed.isOk() { return parsed }
    return Err(sysError(ErrorKind.InvalidArgument, "parseDateTime: 非法日期时间"))
}
