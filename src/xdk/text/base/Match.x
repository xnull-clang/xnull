// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// 一次正则匹配结果：字节下标区间与捕获组文本。
package xdk.text
import xdk.errors

class Match {
    Int start
    Int end
    String text
    List<String> groups

    Match(String text, Int start, Int end, List<String> groups) {
        self.text = text
        self.start = start
        self.end = end
        self.groups = groups
    }

    Int length() {
        return self.end - self.start
    }

    // group(0) 为整匹配；index ≥ 1 为捕获组（未捕获为空串）。
    String group(Int groupIndex) {
        if groupIndex == 0 {
            return self.text.substring(self.start, self.end - self.start)
        }
        Int listIndex = groupIndex - 1
        if listIndex < 0 || listIndex >= self.groups.length() {
            return ""
        }
        return self.groups.get(listIndex)
    }

    Int groupCount() {
        return self.groups.length()
    }
}
