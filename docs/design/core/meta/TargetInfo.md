# `TargetInfo`

| 项 | 值 |
| --- | --- |
| 类型 | `class TargetInfo` |
| 包 | `xdk.meta` |
| 稳定性 | `stable`（基础字段）/ `preview`（能力矩阵） |
| 依赖 | `Capability` |

---

## 1. 定位

构建目标平台只读快照：OS、架构、平台族、指针位宽、端序、能力列表。

不做：运行时探测、动态加载、包管理、交叉编译配置。

---

## 2. 设计逻辑

- 不可变快照；由 `targetInfo()` 创建。
- `family` 是粗平台族（`unix`/`windows`/`wasm`/`unknown`），不是具体发行版。
- 能力列表是目标支持，不是当前进程一定可用；运行时失败仍按错误处理。
- `pointerBits` 32/64；`endian` 用 `"little"`/`"big"`。

---

## 3. 表示与不变量

| 字段 | 类型 | 可变性 | 说明 |
| --- | --- | --- | --- |
| `_os` | `String` | final | 非空 |
| `_arch` | `String` | final | 非空 |
| `_family` | `String` | final | unix/windows/wasm/unknown |
| `_pointerBits` | `Int` | final | 32/64 |
| `_endian` | `String` | final | little/big |
| `_capabilities` | `List<Capability>` | final | 快照；无重复 |

不变量：os/arch 非空；pointerBits 32/64；endian 合法；能力快照；不可变。

---

## 4. 生命周期

不可变；无 close；可共享。

---

## 5. 构造契约

构造器内部；公共入口 `meta.targetInfo()`。

---

## 6. 字段表

见 §3；字段私有。

---

## 7. 方法面

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `os` | 操作系统 | 无 | `String` | 无 |
| `arch` | 架构 | 无 | `String` | 无 |
| `family` | 平台族 | 无 | `String` | 无 |
| `pointerBits` | 指针位宽 | 无 | `Int` | 无 |
| `endian` | 端序 | 无 | `String` | 无 |
| `capabilities` | 能力快照 | 无 | `List<Capability>` | 无 |
| `hasCapability` | 是否支持能力 | `Capability capability` | `Bool` | 无 |
| `describe` | 单行摘要 | 无 | `String` | 无 |
| `copy` | 复制快照 | 无 | `TargetInfo` | 无 |

---

## 8. 使用的技术

- 不可变快照；
- 能力列表线性查询；
- 字符串/整数枚举；
- 平台族分类。

---

## 9. 需要的支撑

- 语言：class、final 字段、String、Int、Bool、List；
- 运行时：目标平台常量；
- 接口：`Capability`。

---

## 10. 依赖的特性/接口/类

`Capability`、`List`、`String`。

---

## 11. 所有权与并发

不可变；可共享；快照列表；无资源。

---

## 12. 示例与反例

正确：`targetInfo().hasCapability(Capability.Tls)` 决定是否启用 TLS。  
反例：把目标能力当运行时保证；用 `os` 字符串做业务分支（优先能力查询）；依赖指针位宽做序列化协议而不显式声明。

---

## 13. 测试/场景义务

字段非空；pointerBits 32/64；endian；能力查询；快照独立性；describe；复制。

---

## 14. XNull 伪代码

```xnull
class TargetInfo {
    final String _os
    final String _arch
    final String _family
    final Int _pointerBits
    final String _endian
    final List<Capability> _capabilities

    TargetInfo(String os, String arch, String family,
               Int pointerBits, String endian,
               List<Capability> capabilities) {
        _os = os
        _arch = arch
        _family = family
        _pointerBits = pointerBits
        _endian = endian
        _capabilities = []
        Int index = 0
        while index < capabilities.length() {
            Capability capability = capabilities.get(index)
            if !_capabilities.contains(capability) {
                _capabilities.push(capability)
            }
            index = index + 1
        }
    }

    String os() { return _os }
    String arch() { return _arch }
    String family() { return _family }
    Int pointerBits() { return _pointerBits }
    String endian() { return _endian }

    List<Capability> capabilities() {
        List<Capability> result = []
        Int index = 0
        while index < _capabilities.length() {
            result.push(_capabilities.get(index))
            index = index + 1
        }
        return result
    }

    Bool hasCapability(Capability capability) {
        return _capabilities.contains(capability)
    }

    String describe() {
        return _os + "/" + _arch
            + " family=" + _family
            + " pointer=" + str(_pointerBits)
            + " endian=" + _endian
            + " capabilities=" + str(_capabilities.length())
    }

    TargetInfo copy() {
        return new TargetInfo(
            _os,
            _arch,
            _family,
            _pointerBits,
            _endian,
            self.capabilities()
        )
    }
}
```
