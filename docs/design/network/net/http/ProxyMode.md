# `ProxyMode`

| 项 | 值 |
| --- | --- |
| 类型 | `enum ProxyMode` |
| 包 | `xdk.net.http` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

HTTP 代理模式：Forward、Reverse、Tunnel。

不做：SOCKS、透明代理、PAC。

---

## 2. 设计逻辑

- 简单枚举；`HttpProxyConfig.mode()`。
- 值语义；无 close。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Forward` | 正向代理 |
| `Reverse` | 反向代理 |
| `Tunnel` | CONNECT 隧道 |

---

## 4. 生命周期

值类型；无 close。

---

## 5. 构造契约

枚举成员直接使用。

---

## 6. 字段表

无实例字段。

---

## 7. 方法总表 / 详表

| 函数 | 用途 | 参数 | 返回 | 失败 |
| --- | --- | --- | --- | --- |
| `proxyModeName` | 名称 | `ProxyMode mode` | `String` | 无 |

---

## 8. 使用的技术

- 简单枚举。

---

## 9. 需要的支撑

- 语言：enum、String；
- 运行时：无。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源。

---

## 12. 示例与反例

正确：`config.mode() == ProxyMode.Tunnel`。  
反例：把 SOCKS 塞进枚举；模式混用。

---

## 13. 测试/场景义务

三成员；名称；配置。

---

## 14. XNull 伪代码

```xnull
enum ProxyMode {
    Forward,
    Reverse,
    Tunnel,
}

String proxyModeName(ProxyMode mode) {
    if mode == ProxyMode.Forward { return "forward" }
    if mode == ProxyMode.Reverse { return "reverse" }
    return "tunnel"
}
```
