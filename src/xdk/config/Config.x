// Tier: T0；依赖：xdk.runtime、xdk.text；稳定性：preview。
// xdk.config —— 配置快照与覆盖（W5）
//
// 面：profile、键值快照（保持插入顺序）、覆盖、环境变量白名单导入。
// 文件/编码加载为后续切片；本切片用已证明的运行时原语完成内存快照。
package xdk.config
import xdk.errors
import xdk.fs

static Error configError(ErrorKind kind, String message) {
    BasicError error = new BasicError(kind, message)
    return error
}

class ConfigEntry {
    final String key
    final String value

    ConfigEntry(String key, String value) {
        self.key = key
        self.value = value
    }
}

protocol ConfigSource {
    Result<List<ConfigEntry>, Error> load();
}

class MapSource implements ConfigSource {
    final List<ConfigEntry> entries

    MapSource(List<ConfigEntry> entries) {
        self.entries = entries
    }

    Result<List<ConfigEntry>, Error> load() {
        return Ok(self.entries)
    }
}

class FileSource implements ConfigSource {
    final String path

    FileSource(String path) {
        self.path = path
    }

    Result<List<ConfigEntry>, Error> load() {
        Result<String, Error> loaded = readText(self.path)
        if loaded.isErr() {
            return Err(loaded.error())
        }
        List<String> lines = loaded.value().split("\n")
        List<ConfigEntry> result = []
        Int index = 0
        Int lineNumber = 1
        while index < lines.length() {
            String line = lines.get(index).trim()
            if line.length() > 0 && !line.startsWith("#") {
                Int equalsAt = line.indexOf("=")
                if equalsAt <= 0 {
                    return Err(configError(ErrorKind.InvalidArgument, "FileSource: invalid line " + str(lineNumber)))
                }
                String key = line.substring(0, equalsAt).trim()
                String value = line.substring(equalsAt + 1, line.length() - equalsAt - 1).trim()
                if key.length() == 0 {
                    return Err(configError(ErrorKind.InvalidArgument, "FileSource: empty key at line " + str(lineNumber)))
                }
                result.push(new ConfigEntry(key, value))
            }
            index = index + 1
            lineNumber = lineNumber + 1
        }
        return Ok(result)
    }
}

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

    Config copy() {
        Config result = new Config(self.profile)
        Int index = 0
        while index < self.entries.length() {
            result.entries.push(self.entries.get(index))
            index = index + 1
        }
        return result
    }

    Result<Unit, Error> setChecked(String key, String value) {
        if key.length() == 0 {
            return Err(configError(ErrorKind.InvalidArgument, "Config: empty key"))
        }
        if key.indexOf("=") >= 0 {
            return Err(configError(ErrorKind.InvalidArgument, "Config: key contains '='"))
        }
        self.set(key, value)
        return Ok()
    }

    Result<Unit, Error> apply(ConfigSource source) {
        Result<List<ConfigEntry>, Error> loaded = source.load()
        if loaded.isErr() {
            return Err(loaded.error())
        }
        List<ConfigEntry> items = loaded.value()
        Int index = 0
        while index < items.length() {
            ConfigEntry entry = items.get(index)
            Result<Unit, Error> setResult = self.setChecked(entry.key, entry.value)
            if setResult.isErr() {
                return Err(setResult.error())
            }
            index = index + 1
        }
        return Ok()
    }

    Config overlay(Config other) {
        Config result = self.copy()
        Int index = 0
        while index < other.entries.length() {
            String line = other.entries.get(index)
            Int equalsAt = line.indexOf("=")
            if equalsAt > 0 {
                result.set(line.substring(0, equalsAt), line.substring(equalsAt + 1, line.length() - equalsAt - 1))
            }
            index = index + 1
        }
        return result
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
