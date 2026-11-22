# `BuildInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class BuildInfo` |
| 包 | `xdk.meta` |
| 稳定性 | `stable`（基础字段）/ `preview`（依赖元数据） |
| 依赖 | `DependencyInfo` |

---

## 1. 定位

构建元数据只读快照：语言/XDK 版本、编译器标识、目标平台、架构、构建模式、构建 ID、构建时间（诊断）、依赖列表。

不做：构建系统、包管理、依赖解析、远程仓库、许可证管理。

---

## 2. 设计逻辑

- 不可变快照；由 `buildInfo()` 创建，不提供公共构造器。
- 版本是字符串；不提供 semver 比较（避免把 meta 变成版本库）。
- 依赖列表是快照；`dependencyVersion` 线性查找。
- 不包含可复现构建所需的隐藏状态；`buildId` 可复现，`builtAt` 只作诊断、可为空，不参与缓存键/排序/业务判断。
- 编译器标识（`compiler`/`compilerVersion`）是诊断字段，不是 XDK 公共 ABI 承诺。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_languageVersion` | `String` | final | 非空三段式 |
| `_xdkVersion` | `String` | final | 非空三段式 |
| `_compiler` | `String` | final | 编译器名；诊断 |
| `_compilerVersion` | `String` | final | 编译器版本；诊断 |
| `_targetPlatform` | `String` | final | 非空 |
| `_architecture` | `String` | final | 非空 |
| `_buildMode` | `String` | final | `debug`/`release` |
| `_buildId` | `String` | final | 可为空；可复现 ID |
| `_builtAt` | `String` | final | 构建时间文本；可为空；仅诊断 |
| `_dependencies` | `List<DependencyInfo>` | final | 快照；无重复 name |

不变量：版本非空；依赖快照；`builtAt` 不参与可复现判断；不可变；可共享。

---

## 4. 生命周期

不可变；无 close；可跨任务共享。

---

## 5. 构造契约

构造器内部；公共入口 `meta.buildInfo()`。
测试可通过运行时注入构建元数据（不属于公共 API）。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `languageVersion` | 语言版本 | 无 | `String` | 无 |
| `xdkVersion` | XDK 版本 | 无 | `String` | 无 |
| `compiler` | 编译器名 | 无 | `String` | 无 |
| `compilerVersion` | 编译器版本 | 无 | `String` | 无 |
| `targetPlatform` | 目标平台 | 无 | `String` | 无 |
| `architecture` | 架构 | 无 | `String` | 无 |
| `buildMode` | 构建模式 | 无 | `String` | 无 |
| `buildId` | 构建 ID | 无 | `String` | 无 |
| `builtAt` | 构建时间文本 | 无 | `String` | 无 |
| `complete` | 关键字段非空 | 无 | `Bool` | 无 |
| `dependencies` | 依赖快照 | 无 | `List<DependencyInfo>` | 无 |
| `dependencyNames` | 依赖名快照 | 无 | `List<String>` | 无 |
| `dependency` | 按名查依赖 | `String name` | `DependencyInfo?` | 无 |
| `dependencyVersion` | 按名查版本 | `String name` | `String?` | 无 |
| `hasDependency` | 是否有依赖 | `String name` | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `copy` | 复制快照 | 无 | `BuildInfo` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 列表快照；
- 线性查找；
- 字符串拼接。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、List；
- 运行时：构建常量/依赖表读取、编译器名/版本、构建时间；
- 接口：`DependencyInfo`。

---

## 10. 依赖的特性/接口/类

`DependencyInfo`、`List`、`String`。

---

## 11. 所有权与并发

- 不可变；可共享。
- `dependencies()`/`dependencyNames()` 返回快照。
- 无资源、无 close。

---

## 12. 示例与反例

正确：`buildInfo().describe()` 启动横幅；`dependencyVersion("xdk.net")` 诊断；`buildInfo().builtAt()` 只写诊断日志。

反例：用 `buildId` 或 `builtAt` 做安全凭证；依赖版本做精确 semver 比较；构造伪造 BuildInfo；用 `builtAt` 做缓存键/排序；假设 `builtAt` 非空或可复现。

---

## 13. 测试/场景义务

字段格式；`compiler`/`compilerVersion`/`builtAt` 读取；`complete()` 对关键字段空值返回 false；`builtAt` 为空仍可构造；依赖查找命中/缺失；快照独立性；describe；复制；多任务共享；`builtAt` 不参与可复现断言。

---

## 14. XNull 伪代码

```xnull
class BuildInfo {
    final String _languageVersion
    final String _xdkVersion
    final String _compiler
    final String _compilerVersion
    final String _targetPlatform
    final String _architecture
    final String _buildMode
    final String _buildId
    final String _builtAt
    final List<DependencyInfo> _dependencies

    BuildInfo(String languageVersion, String xdkVersion,
              String compiler, String compilerVersion,
              String targetPlatform, String architecture,
              String buildMode, String buildId, String builtAt,
              List<DependencyInfo> dependencies) {
        _languageVersion = languageVersion
        _xdkVersion = xdkVersion
        _compiler = compiler
        _compilerVersion = compilerVersion
        _targetPlatform = targetPlatform
        _architecture = architecture
        _buildMode = buildMode
        _buildId = buildId
        _builtAt = builtAt
        _dependencies = []
        Int index = 0
        while index < dependencies.length() {
            _dependencies.push(dependencies.get(index))
            index = index + 1
        }
    }

    String languageVersion() { return _languageVersion }
    String xdkVersion() { return _xdkVersion }
    String compiler() { return _compiler }
    String compilerVersion() { return _compilerVersion }
    String targetPlatform() { return _targetPlatform }
    String architecture() { return _architecture }
    String buildMode() { return _buildMode }
    String buildId() { return _buildId }
    String builtAt() { return _builtAt }

    Bool complete() {
        return _languageVersion != ""
            && _xdkVersion != ""
            && _compiler != ""
            && _compilerVersion != ""
            && _targetPlatform != ""
            && _architecture != ""
            && _buildMode != ""
    }

    List<DependencyInfo> dependencies() {
        List<DependencyInfo> result = []
        Int index = 0
        while index < _dependencies.length() {
            result.push(_dependencies.get(index))
            index = index + 1
        }
        return result
    }

    List<String> dependencyNames() {
        List<String> result = []
        Int index = 0
        while index < _dependencies.length() {
            result.push(_dependencies.get(index).name())
            index = index + 1
        }
        return result
    }

    DependencyInfo? dependency(String name) {
        Int index = 0
        while index < _dependencies.length() {
            DependencyInfo current = _dependencies.get(index)
            if current.name() == name {
                return current
            }
            index = index + 1
        }
        return null
    }

    String? dependencyVersion(String name) {
        DependencyInfo? found = self.dependency(name)
        if found == null {
            return null
        }
        return found.version()
    }

    Bool hasDependency(String name) {
        return self.dependency(name) != null
    }

    String describe() {
        return "xdk " + _xdkVersion
            + " lang " + _languageVersion
            + " compiler " + _compiler + " " + _compilerVersion
            + " target " + _targetPlatform + "/" + _architecture
            + " mode " + _buildMode
            + " build " + _buildId
            + " builtAt " + _builtAt
    }

    BuildInfo copy() {
        return new BuildInfo(
            _languageVersion,
            _xdkVersion,
            _compiler,
            _compilerVersion,
            _targetPlatform,
            _architecture,
            _buildMode,
            _buildId,
            _builtAt,
            self.dependencies()
        )
    }
}
```

---

## 15. 1.x 兼容边界（C7）

1.x `BuildInfo` 公共字段/构造：

```text
BuildInfo(String languageVersion, String xdkVersion, String compiler,
          String compilerVersion, String platform, String arch,
          String mode, String builtAt)
Bool complete()
String describe()
String buildDate()
```

- 2.x 保留 `languageVersion/xdkVersion/compiler/compilerVersion/targetPlatform/architecture/buildMode/builtAt`；`platform`/`arch` 迁移为 `targetPlatform`/`architecture`。
- 2.x 新增 `buildId`/`dependencies`；1.x 无这两个字段。
- `builtAt` 来自 1.x `buildDate()`，只作诊断；2.x 不保证可复现、不保证非空，不得用于缓存键/排序/业务判断。
- `complete()` 检查 `languageVersion/xdkVersion/compiler/compilerVersion/targetPlatform/architecture/buildMode` 非空；`builtAt` 可为空。
- 1.x 公共字段访问迁移到 2.x 访问器；不保留第二个 `BuildInfo` 类。

测试义务：1.x 字段映射；`complete()` 空/非空；`builtAt` 空值仍可用；`buildId`/dependencies 2.x 增量；不把 `builtAt` 当版本排序键。
