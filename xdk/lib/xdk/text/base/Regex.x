// xdk.text 完整实现（源码层过渡单元，仅 XNULL_XDK_SOURCE=1 编入）
//
// POSIX ERE 子集公开面。匹配偏移为 UTF-8 字节下标；. 与字符类按码点推进。
// 替换文本是字面量，不支持 $1 反向引用。
package xdk.text
import xdk.errors

class Regex {
    final String pattern;
    RegexTree t
    Int groupCount
    Bool anchored
    Int root

    Regex(String pattern) {
        self.pattern = pattern
        self.t = new RegexTree()
        self.groupCount = 0
        self.anchored = false
        self.root = 0
    }

    static Result<Regex, Error> compile(String pattern) {
        return regexCompile(pattern)
    }

    Int groupCount() {
        return self.groupCount
    }

    Bool isMatch(String text) {
        return self.find(text) != null
    }

    // 首个匹配；未找到返回 null。
    Match? find(String text) {
        Int start = 0
        while start <= text.length() {
            RegexMatcher matcher = new RegexMatcher(self.t, text, self.groupCount)
            Int end = matcher.matchOne(self.root, start)
            if end >= start {
                return new Match(text, start, end, self.collectGroups(matcher))
            }
            if self.anchored {
                return null
            }
            start = start + 1
        }
        return null
    }

    List<String> collectGroups(RegexMatcher matcher) {
        List<String> groups = []
        Int index = 0
        while index < self.groupCount {
            Int groupStart = matcher.st.starts.get(index)
            Int groupEnd = matcher.st.ends.get(index)
            if groupStart >= 0 && groupEnd >= groupStart {
                groups.push(matcher.text.substring(groupStart, groupEnd - groupStart))
            } else {
                groups.push("")
            }
            index = index + 1
        }
        return groups
    }

    // 非空匹配列表（空匹配跳过并前进 1 字节）。
    List<Match> findAll(String text) {
        List<Match> matches = []
        Int start = 0
        while start < text.length() {
            RegexMatcher matcher = new RegexMatcher(self.t, text, self.groupCount)
            Int end = matcher.matchOne(self.root, start)
            if end > start {
                matches.push(new Match(text, start, end, self.collectGroups(matcher)))
                start = end
                continue
            }
            if self.anchored {
                break
            }
            start = start + 1
        }
        return matches
    }

    // 把全部非空匹配替换为 replacement（字面量）。
    String replaceAll(String text, String replacement) {
        String output = ""
        Int position = 0
        while position < text.length() {
            RegexMatcher matcher = new RegexMatcher(self.t, text, self.groupCount)
            Int end = matcher.matchOne(self.root, position)
            if end > position {
                output = output + replacement
                position = end
                continue
            }
            output = output + text.substring(position, 1)
            position = position + 1
        }
        return output
    }

    // 按非空匹配切分。
    List<String> split(String text) {
        List<String> parts = []
        Int position = 0
        Int last = 0
        while position < text.length() {
            RegexMatcher matcher = new RegexMatcher(self.t, text, self.groupCount)
            Int end = matcher.matchOne(self.root, position)
            if end > position {
                parts.push(text.substring(last, position - last))
                position = end
                last = end
                continue
            }
            position = position + 1
        }
        parts.push(text.substring(last, text.length() - last))
        return parts
    }
}
