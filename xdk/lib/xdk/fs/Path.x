// Tier: T0；依赖：无；稳定性：preview。
// xdk.fs —— 路径字符串的轻量视图；不访问文件系统。
package xdk.fs

class Path {
    final String raw

    Path(String raw) {
        self.raw = raw
    }

    String toString() {
        return self.raw
    }

    String text() {
        return self.raw
    }

    Bool isAbsolute() {
        return self.raw.length() > 0 && self.raw.substring(0, 1) == "/"
    }

    String name() {
        String trimmed = self.raw
        while trimmed.length() > 1 && trimmed.substring(trimmed.length() - 1, 1) == "/" {
            trimmed = trimmed.substring(0, trimmed.length() - 1)
        }
        if trimmed == "/" {
            return "/"
        }
        Int slash = -1
        Int index = 0
        while index < trimmed.length() {
            if trimmed.substring(index, 1) == "/" {
                slash = index
            }
            index = index + 1
        }
        if slash < 0 {
            return trimmed
        }
        return trimmed.substring(slash + 1, trimmed.length() - slash - 1)
    }

    Path parent() {
        String trimmed = self.raw
        while trimmed.length() > 1 && trimmed.substring(trimmed.length() - 1, 1) == "/" {
            trimmed = trimmed.substring(0, trimmed.length() - 1)
        }
        if trimmed == "/" {
            return new Path("/")
        }
        Int slash = -1
        Int index = 0
        while index < trimmed.length() {
            if trimmed.substring(index, 1) == "/" {
                slash = index
            }
            index = index + 1
        }
        if slash < 0 {
            return new Path(".")
        }
        if slash == 0 {
            return new Path("/")
        }
        return new Path(trimmed.substring(0, slash))
    }

    String extension() {
        String fileName = self.name()
        Int dot = -1
        Int index = 0
        while index < fileName.length() {
            if fileName.substring(index, 1) == "." {
                dot = index
            }
            index = index + 1
        }
        if dot <= 0 || dot + 1 >= fileName.length() {
            return ""
        }
        return fileName.substring(dot + 1, fileName.length() - dot - 1)
    }

    Path join(String child) {
        if child.length() == 0 {
            return new Path(self.raw)
        }
        if child.substring(0, 1) == "/" {
            return new Path(child)
        }
        if self.raw.length() == 0 || self.raw == "." {
            return new Path(child)
        }
        if self.raw.substring(self.raw.length() - 1, 1) == "/" {
            return new Path($"{self.raw}{child}")
        }
        return new Path($"{self.raw}/{child}")
    }

    Path normalize() {
        if self.raw.length() == 0 {
            return new Path(".")
        }
        Bool absolute = self.raw.substring(0, 1) == "/"
        List<String> parts = []
        Int start = 0
        Int index = 0
        while index <= self.raw.length() {
            Bool atEnd = index == self.raw.length()
            Bool atSlash = !atEnd && self.raw.substring(index, 1) == "/"
            if atEnd || atSlash {
                String part = self.raw.substring(start, index - start)
                if part != "" && part != "." {
                    if part == ".." {
                        if parts.length() > 0 && parts.get(parts.length() - 1) != ".." {
                            parts.remove(parts.length() - 1)
                        } else if !absolute {
                            parts.push("..")
                        }
                    } else {
                        parts.push(part)
                    }
                }
                start = index + 1
            }
            index = index + 1
        }
        String result = ""
        if absolute {
            result = "/"
        }
        Int partIndex = 0
        while partIndex < parts.length() {
            if partIndex > 0 {
                result = $"{result}/"
            }
            result = $"{result}{parts.get(partIndex)}"
            partIndex = partIndex + 1
        }
        if result.length() == 0 {
            return new Path(".")
        }
        return new Path(result)
    }
}
