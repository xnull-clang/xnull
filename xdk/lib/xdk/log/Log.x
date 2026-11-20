// Tier: T0；依赖：xdk.runtime、xdk.text；稳定性：preview。
// xdk.log —— 结构化日志（W5 首个可运行面）
//
// 面：Level 阈值、Logger 名称、debug/info/warn/error 便捷方法、stdout sink。
// 字段（fields）与可插拔 sink 为后续切片；本切片只承诺可执行的最小契约。
package xdk.log

enum Level {
    Debug,
    Info,
    Warn,
    Error
}

static Int levelRank(Level level) {
    if level == Level.Debug {
        return 0
    }
    if level == Level.Info {
        return 1
    }
    if level == Level.Warn {
        return 2
    }
    return 3
}

static String levelName(Level level) {
    if level == Level.Debug {
        return "DEBUG"
    }
    if level == Level.Info {
        return "INFO"
    }
    if level == Level.Warn {
        return "WARN"
    }
    return "ERROR"
}

class Logger {
    String name
    Level min

    Logger(String name, Level min) {
        self.name = name
        self.min = min
    }

    Bool enabled(Level level) {
        return levelRank(level) >= levelRank(self.min)
    }

    Void log(Level level, String message) {
        if self.enabled(level) {
            print("[" + levelName(level) + "] " + self.name + ": " + message)
        }
    }

    Void debug(String message) {
        self.log(Level.Debug, message)
    }

    Void info(String message) {
        self.log(Level.Info, message)
    }

    Void warn(String message) {
        self.log(Level.Warn, message)
    }

    Void error(String message) {
        self.log(Level.Error, message)
    }
}
