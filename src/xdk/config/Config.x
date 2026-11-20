// Tier: T0；依赖：xdk.runtime、xdk.text；稳定性：preview。
// xdk.config —— 配置快照与覆盖（W5）
//
// 面：profile、键值快照（保持插入顺序）、覆盖、环境变量白名单导入。
// 文件/编码加载为后续切片；本切片用已证明的运行时原语完成内存快照。
package xdk.config

class Config {
    List<String> entries
    String profile

    Config(String profile) {
        self.entries = []
        self.profile = profile
    }

    Int indexOf(String key) {
        String prefix = key + "="
        Int i = 0
        while i < self.entries.length() {
            if self.entries.get(i).startsWith(prefix) {
                return i
            }
            i = i + 1
        }
        return -1
    }

    Int length() {
        return self.entries.length()
    }

    Bool has(String key) {
        return self.indexOf(key) >= 0
    }

    Void set(String key, String value) {
        String line = key + "=" + value
        Int i = self.indexOf(key)
        if i >= 0 {
            self.entries.set(i, line)
        } else {
            self.entries.push(line)
        }
    }

    String getOr(String key, String fallback) {
        Int i = self.indexOf(key)
        if i < 0 {
            return fallback
        }
        String line = self.entries.get(i)
        Int eq = line.indexOf("=")
        return line.substring(eq + 1, line.length() - eq - 1)
    }

    // 只导入显式白名单中的环境变量；缺失的键保持原值。
    Void loadEnv(List<String> keys) {
        Int i = 0
        while i < keys.length() {
            String key = keys.get(i)
            if envHasRaw(key) != 0 {
                self.set(key, envRaw(key))
            }
            i = i + 1
        }
    }

    String render() {
        return self.profile + ":" + self.entries.join(",")
    }
}
