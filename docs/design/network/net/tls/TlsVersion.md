# `TlsVersion`

| 项 | 值 |
| --- | --- |
| 类型 | `enum TlsVersion` |
| 包 | `xdk.net.tls` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

TLS 协议版本：1.2、1.3。

不做：TLS 1.0/1.1、DTLS、QUIC、版本协商算法。

---

## 2. 设计逻辑

- 简单枚举；比较/协商由运行时完成。
- `TlsConfig.withMinVersion/withMaxVersion` 接受本枚举。
- 值语义；无 close；可共享。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Tls12` | TLS 1.2 |
| `Tls13` | TLS 1.3 |

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
| `tlsVersionName` | 稳定名 | `TlsVersion version` | `String` | 无 |

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

正确：`config.withMinVersion(TlsVersion.Tls12)`。  
反例：把 TLS 1.1 塞进枚举；用整数表示版本。

---

## 13. 测试/场景义务

成员；名称；min/max 配置；协商结果 `TlsSessionInfo.version`。

---

## 14. XNull 伪代码

```xnull
enum TlsVersion {
    Tls12,
    Tls13,
}

String tlsVersionName(TlsVersion version) {
    if version == TlsVersion.Tls12 { return "tls1.2" }
    return "tls1.3"
}
```
