# `Permissions`

| 项 | 值 |
| --- | --- |
| 类型 | `class Permissions` |
| 包 | `xdk.fs` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

POSIX 权限位值对象：owner/group/other 的 rwx。

不做：ACL、扩展属性、Windows 完整 ACL 映射。

---

## 2. 设计逻辑

- 唯一字段 `_mode: Int`（低 9 位）。
- `fromOctal("755")`、`toOctal()`。
- `isReadable/isWritable/isExecutable` 判断当前进程（ 近似）。
- 不可变；值语义。

---

## 3. 表示与不变量

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `_mode` | `Int` | 0..511 |

不变量：mode 在 0..511；只使用低 9 位。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `Permissions(Int mode)` | mode | 0..511 | 越界 → panic |
| `fromOctal(String)` | octal | 0..777 | 非法 → panic |

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `mode` | 位值 | 无 | `Int` | 无 |
| `toOctal` | 八进制文本 | 无 | `String` | 无 |
| `fromOctal` | 解析 | `String` | `Permissions` | 非法 → panic |
| `isReadable` | 可读 | 无 | `Bool` | 无 |
| `isWritable` | 可写 | 无 | `Bool` | 无 |
| `isExecutable` | 可执行 | 无 | `Bool` | 无 |
| `ownerRead` 等 | 单权限位 | 无 | `Bool` | 无 |
| `equals` | 值相等 | `Permissions` | `Bool` | 无 |
| `toString` | 文本 | 无 | `String` | 无 |

---

## 8. 使用的技术

- 位掩码；
- 八进制解析/格式化；
- 权限位。

---

## 9. 需要的支撑

- 语言：class、Int、Bool、String；
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

正确：`Permissions.fromOctal("644")`。  
反例：mode 1000；把 ACL 塞进 9 位；用字符串权限做位运算。

---

## 13. 测试/场景义务

0/777/644；fromOctal/toOctal；单权限位；equals；越界。

---

## 14. XNull 伪代码

```xnull
class Permissions {
    final Int _mode

    Permissions(Int mode) {
        if mode < 0 || mode > 511 {
            throw "Permissions: mode out of range"
        }
        _mode = mode
    }

    static Permissions fromOctal(String octal) {
        if octal == "" { throw "Permissions.fromOctal: empty" }
        Int value = 0
        Int index = 0
        while index < octal.length() {
            Char character = octal.charAt(index)
            if character < '0' || character > '7' {
                throw "Permissions.fromOctal: invalid digit"
            }
            value = value * 8 + (character as Int - 48)
            index = index + 1
        }
        return new Permissions(value)
    }

    Int mode() { return _mode }

    String toOctal() {
        Int owner = (_mode / 64) % 8
        Int group = (_mode / 8) % 8
        Int other = _mode % 8
        return str(owner) + str(group) + str(other)
    }

    Bool ownerRead() { return (_mode & 256) != 0 }
    Bool ownerWrite() { return (_mode & 128) != 0 }
    Bool ownerExecute() { return (_mode & 64) != 0 }
    Bool groupRead() { return (_mode & 32) != 0 }
    Bool groupWrite() { return (_mode & 16) != 0 }
    Bool groupExecute() { return (_mode & 8) != 0 }
    Bool otherRead() { return (_mode & 4) != 0 }
    Bool otherWrite() { return (_mode & 2) != 0 }
    Bool otherExecute() { return (_mode & 1) != 0 }

    Bool isReadable() { return self.ownerRead() || self.groupRead() || self.otherRead() }
    Bool isWritable() { return self.ownerWrite() || self.groupWrite() || self.otherWrite() }
    Bool isExecutable() { return self.ownerExecute() || self.groupExecute() || self.otherExecute() }

    Bool equals(Permissions other) {
        if other == null { return false }
        return _mode == other._mode
    }

    String toString() { return self.toOctal() }
}
```
