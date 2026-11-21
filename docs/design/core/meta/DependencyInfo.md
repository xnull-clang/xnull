# `DependencyInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class DependencyInfo` |
| 包 | `xdk.meta` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

构建期依赖的名称/版本/可选标记，用于诊断和依赖审计。

不做：依赖解析、包管理、远程仓库、许可证管理。

---

## 2. 设计逻辑

- 不可变值对象；name/version 非空。
- `isOptional` 表示构建时可选依赖，不表示运行时是否加载。
- 不包含路径/URL/许可证；需要时扩展字段需版本决策。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_name` | `String` | final | 非空 |
| `_version` | `String` | final | 非空 |
| `_isOptional` | `Bool` | final | 是否可选 |

不变量：name/version 非空；不可变；值语义。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `DependencyInfo(String name, String version, Bool isOptional)` | name/version/isOptional | name/version 非空 | 空 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `name` | 名称 | 无 | `String` | 无 |
| `version` | 版本 | 无 | `String` | 无 |
| `isOptional` | 是否可选 | 无 | `Bool` | 无 |
| `describe` | 单行 | 无 | `String` | 无 |
| `equals` | 值相等 | `DependencyInfo other` | `Bool` | 无 |
| `compare` | 排序 | `DependencyInfo other` | `Int` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 不可变值对象；
- 字符串比较；
- 可选标记。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Bool、Int；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

不可变；可共享；无资源。

---

## 12. 示例与反例

正确：`new DependencyInfo("xdk.net","1.0.0",false)`。  
反例：空名称；把 optional 当运行时已加载；用版本字符串做精确比较（需 semver 规则）。

---

## 13. 测试/场景义务

构造校验；equals/compare；describe；排序；复制/共享。

---

## 14. XNull 伪代码

```xnull
class DependencyInfo {
    final String _name
    final String _version
    final Bool _isOptional

    DependencyInfo(String name, String version, Bool isOptional) {
        if name == "" {
            throw "DependencyInfo: empty name"
        }
        if version == "" {
            throw "DependencyInfo: empty version"
        }
        _name = name
        _version = version
        _isOptional = isOptional
    }

    String name() { return _name }
    String version() { return _version }
    Bool isOptional() { return _isOptional }

    String describe() {
        String suffix = ""
        if _isOptional {
            suffix = " (optional)"
        }
        return _name + " " + _version + suffix
    }

    Bool equals(DependencyInfo other) {
        if other == null {
            return false
        }
        return _name == other._name
            && _version == other._version
            && _isOptional == other._isOptional
    }

    Int compare(DependencyInfo other) {
        if _name < other._name { return -1 }
        if _name > other._name { return 1 }
        if _version < other._version { return -1 }
        if _version > other._version { return 1 }
        if _isOptional == other._isOptional { return 0 }
        if !_isOptional { return -1 }
        return 1
    }

    String toString() {
        return self.describe()
    }
}
```
