# `UuidVersion`

| 项 | 值 |
| --- | --- |
| 类型 | `enum UuidVersion` |
| 包 | `xdk.uuid` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

支持的 UUID 版本：v4、v7。

不做：v1/v3/v5、非标准变体。

---

## 2. 设计逻辑

- 简单枚举；`Uuid.version()` 返回。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `V4` | 随机 |
| `V7` | 时间有序 |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `uuidVersionName` | 名称 | `UuidVersion version` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举。

---

## 9. 需要的支撑

- 语言：enum、String。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：`Uuid.v7().version() == UuidVersion.V7`。  
反例：把 v1 塞进枚举；用版本判断唯一性。

---

## 13. 测试/场景义务

两成员；名称；生成/解析版本。

---

## 14. XNull 伪代码

```xnull
enum UuidVersion {
    V4,
    V7,
}

String uuidVersionName(UuidVersion version) {
    if version == UuidVersion.V4 { return "v4" }
    return "v7"
}
```
