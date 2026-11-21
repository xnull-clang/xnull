# `ConstantTime`

| 项 | 值 |
| --- | --- |
| 类型 | `class ConstantTime` |
| 包 | `xdk.crypto` |
| 稳定性 | `preview` |
| 依赖 | `Bytes` |

---

## 1. 定位

常量时间比较：字节相等、字典序、全零/非零。

不做：哈希、加密、随机。

---

## 2. 设计逻辑

- 无状态；构造器私有。
- 比较不依赖提前退出；长度不同仍比较最大长度。
- 无 close；可并发。

---

## 3. 表示与不变量

无实例字段。

---

## 4. 生命周期

静态命名空间；无 close。

---

## 5. 构造契约

| 构造 | 参数 | 合法域 | 失败 |
| --- | --- | --- | --- |
| `ConstantTime()` | 无 | 私有 | 外部构造 → 编译错误 |

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 方法 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `equals` | 常量时间相等 | `Bytes left, Bytes right` | `Bool` | null → panic |
| `compare` | 常量时间比较 | `Bytes left, Bytes right` | `Int` | null → panic |
| `isZero` | 是否全零 | `Bytes data` | `Bool` | null → panic |

---

## 8. 使用的技术

- 无分支比较；
- 掩码。

---

## 9. 需要的支撑

- 语言：class、Bytes、Bool、Int；
- 运行时：`constantTimeEqualsRaw`、`constantTimeCompareRaw`。

---

## 10. 依赖的特性/接口/类

`Bytes`、常量时间运行时原语。

---

## 11. 所有权与并发

无状态；无资源；可并发。

---

## 12. 示例与反例

正确：`ConstantTime.equals(mac1,mac2)`。  
反例：用 `==` 比较 MAC；对密钥做短路比较。

---

## 13. 测试/场景义务

等长/不等长；空；全零；不同首字节；边界。

---

## 14. XNull 伪代码

```xnull
class ConstantTime {
    private ConstantTime() {
    }

    static Bool equals(Bytes left, Bytes right) {
        if left == null || right == null { throw "ConstantTime.equals: null" }
        return constantTimeEqualsRaw(left, right)
    }

    static Int compare(Bytes left, Bytes right) {
        if left == null || right == null { throw "ConstantTime.compare: null" }
        return constantTimeCompareRaw(left, right)
    }

    static Bool isZero(Bytes data) {
        if data == null { throw "ConstantTime.isZero: null" }
        Int index = 0
        Int result = 0
        while index < data.length() {
            result = result | data.get(index)
            index = index + 1
        }
        return result == 0
    }
}
```

> `constantTime*Raw` 是运行时原语；不是 XDK 公共类型。
