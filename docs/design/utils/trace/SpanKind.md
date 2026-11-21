# `SpanKind`

| 项 | 值 |
| --- | --- |
| 类型 | `enum SpanKind` |
| 包 | `xdk.trace` |
| 稳定性 | `preview` |
| 依赖 | 无 |

---

## 1. 定位

span 在调用链中的角色：Internal、Server、Client、Producer、Consumer。

不做：方向推断、协议识别、采样决策、导出格式映射。

---

## 2. 设计逻辑

- `Internal`：进程内操作，不跨越网络/消息边界。
- `Server`：接收请求的一侧，例如 HTTP 服务端、RPC 服务端。
- `Client`：发起请求的一侧，例如 HTTP 客户端、数据库客户端。
- `Producer`：向消息系统发送消息。
- `Consumer`：从消息系统接收消息。
- kind 是**语义提示**，不改变父子关系、采样或导出行为。
- 枚举无实例方法；值语义；无生命周期。

---

## 3. 表示与不变量

| 成员 | 含义 |
| --- | --- |
| `Internal` | 进程内操作 |
| `Server` | 服务端入站 |
| `Client` | 客户端出站 |
| `Producer` | 消息生产者 |
| `Consumer` | 消息消费者 |

不变量：成员固定；不存在 `Unknown`/`Unspecified`；一个 span 只有一个 kind；kind 在构造后不变。

---

## 4. 生命周期

值类型；无 close；无资源。

---

## 5. 构造契约

枚举成员直接使用；不提供整数/字符串隐式转换。

---

## 6. 字段表

无。

---

## 7. 方法总表 / 详表

无实例方法；显示名由导出/日志层映射，核心不承诺固定文本。

---

## 8. 使用的技术

- 简单枚举；
- 开放语义提示。

---

## 9. 需要的支撑

- 语言：enum。

---

## 10. 依赖的特性/接口/类

无。

---

## 11. 所有权与并发

值语义；无资源；可跨任务共享。

---

## 12. 示例与反例

正确：入站 HTTP span 用 `SpanKind.Server`，出站数据库 span 用 `SpanKind.Client`。  
反例：把 `Client` 用在服务端入站；把 `Producer`/`Consumer` 当队列内部线程池；依赖 kind 自动推断采样。

---

## 13. 测试/场景义务

每个成员存在；相等/不等；Map 键；导出映射；父子 span 的 kind 独立；不因 kind 改变采样。

---

## 14. XNull 伪代码

```xnull
enum SpanKind {
    Internal,
    Server,
    Client,
    Producer,
    Consumer,
}
```
