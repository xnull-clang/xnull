# `IpFamily`

| 项 | 值 |
| --- | --- |
| 类型 | `enum IpFamily` |
| 包 | `xdk.net` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

IP 地址族：IPv4、IPv6、未指定。

不做：地址解析、协议版本协商、双栈策略。

---

## 2. 设计逻辑

- 简单枚举；`Unspecified` 用于 DNS/connect 的“任意族”偏好。
- 不定义数值码；需要文本时用 `ipFamilyName`。
- 值语义；无 close；可共享。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Ipv4` | IPv4 |
| `Ipv6` | IPv6 |
| `Unspecified` | 不限定/任意 |

不变量：成员固定；只允许追加。

---

## 4. 生命周期

值类型；无 close；可共享。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

无实例方法。相关顶层函数：

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `ipFamilyName` | 稳定名 | `IpFamily family` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举；
- 名称映射。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无；
- 接口：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源；可共享。

---

## 12. 示例与反例

正确：`Dns.resolveOne(ctx,"example.com",IpFamily.Ipv4)`。  
反例：把 `Unspecified` 当 IPv6；用整数表示地址族。

---

## 13. 测试/场景义务

成员；`ipFamilyName`；Unspecified 的“任意”语义；无隐式数值转换。

---

## 14. XNull 伪代码

```xnull
enum IpFamily {
    Ipv4,
    Ipv6,
    Unspecified,
}

String ipFamilyName(IpFamily family) {
    if family == IpFamily.Ipv4 { return "ipv4" }
    if family == IpFamily.Ipv6 { return "ipv6" }
    return "unspecified"
}
```
